// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";
import { DcaMath } from "./DcaMath.sol";

/// @title DCAGuardReactive — reactive contract for DCA Guard (Lasna testnet).
/// @notice FASE 2: full DCA decision logic on CRON100 ticks.
/// Subscribes to Sync events of our own Uniswap V2 pair on Base Sepolia and
/// forwards reserves to DCAGuardCallback. On every CRON100 tick (~2 min) it
/// decides BUY / SKIP with explicit, measurable rules and (on BUY) requests
/// an `onDcaTick` callback that executes a real WETH -> DCAT swap.
///
/// Rules (all evaluated on the latest synced reserves, price = DCAT per WETH,
/// 1e18-scaled):
///  - BUY when: not paused AND price within ±30% of the reference price
///    (reference = price at the first CRON tick after deploy) AND
///    |price change vs previous tick| < 20%.
///  - SKIP otherwise, with the reason recorded on-chain.
///  - Circuit breaker: |price change| >= 20% vs previous tick auto-pauses
///    (paused = true + event); only the owner can unpause.
///  - First tick: sets the reference price (and prev price), change is 0 by
///    definition, so it BUYs when not paused.
/// FASE 1 contract (0x314413299c2835fA91e5AC183cc10F0e8aDaA74b) is left deployed
/// untouched as an artifact; this is a fresh deployment.
contract DCAGuardReactive is AbstractReactive {
    address internal constant LEGACY_SYSTEM_ADDR = 0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant CRON100_TOPIC_0 =
        0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

    uint8 internal constant DECISION_NONE = 0;
    uint8 internal constant DECISION_BUY = 1;
    uint8 internal constant DECISION_SKIP = 2;

    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;
    address public immutable pair;
    uint256 public immutable syncTopic0;

    address public owner;
    address public callback;
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    uint256 public syncCount;
    uint256 public cronTicks;
    uint112 public lastReserve0;
    uint112 public lastReserve1;
    uint256 public lastSyncBlock;
    bool public cronSubscribed;

    // ---- Fase 2: DCA state ----
    uint256 public referencePrice; // DCAT per WETH, 1e18-scaled; 0 = not set yet
    uint256 public prevPrice; // price at the previous CRON tick, 1e18-scaled
    uint256 public buyAmount = 0.001 ether; // WETH per BUY
    bool public paused;

    struct DecisionRecord {
        uint256 tick;
        uint256 price;
        uint8 decision; // 1 = BUY, 2 = SKIP
        string reason;
    }

    DecisionRecord[] public decisionHistory;
    uint256 public lastDecision; // 1 = BUY, 2 = SKIP, 0 = none yet
    string public lastDecisionReason;
    uint256 public lastDecisionTick;

    event SyncObserved(uint256 reserve0, uint256 reserve1, uint256 blockNumber);
    event CronTick(uint256 indexed tick, uint256 blockNumber);
    event PriceCallbackRequested(address indexed callback, uint256 reserve0, uint256 reserve1);
    event DcaDecision(uint256 indexed tick, uint256 price, uint8 decision, string reason);
    event DcaCallbackRequested(address indexed callback, uint256 tick, uint256 price, uint256 amountIn);
    event CircuitBreakerTriggered(uint256 indexed tick, uint256 price, uint256 changeBps);
    event ReferencePriceSet(uint256 price);
    event Paused(address indexed by);
    event Unpaused(address indexed by);
    event BuyAmountSet(uint256 amount);

    /// @notice Payable so the contract can be funded with lREACT at deploy.
    constructor(uint256 originChainId_, address pair_, uint256 syncTopic0_, uint256 destinationChainId_)
        payable
    {
        originChainId = originChainId_;
        pair = pair_;
        syncTopic0 = syncTopic0_;
        destinationChainId = destinationChainId_;
        owner = msg.sender;
        SYSTEM.subscribe(
            originChainId_,
            pair_,
            syncTopic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice Set the callback recipient (deploy order: RC, callback, then point).
    function setCallback(address callback_) external onlyOwner {
        callback = callback_;
    }

    /// @notice Opt in to CRON100 ticks (~every 2 min on Lasna).
    function subscribeCron() external onlyOwner {
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON100_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        cronSubscribed = true;
    }

    function unsubscribeCron() external onlyOwner {
        SYSTEM.unsubscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON100_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        cronSubscribed = false;
    }

    // ---- Fase 2: owner controls ----
    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function setReferencePrice(uint256 price_) external onlyOwner {
        referencePrice = price_;
        emit ReferencePriceSet(price_);
    }

    function setBuyAmount(uint256 amount_) external onlyOwner {
        buyAmount = amount_;
        emit BuyAmountSet(amount_);
    }

    function decisionCount() external view returns (uint256) {
        return decisionHistory.length;
    }

    /// @notice Current price from the latest synced reserves (DCAT per WETH, 1e18).
    function currentPrice() public view returns (uint256) {
        if (lastReserve0 == 0) return 0;
        return (uint256(lastReserve1) * 1e18) / uint256(lastReserve0);
    }

    /// @notice Pure decision evaluation. Returns (decision, reason).
    /// @dev Also sets referencePrice on first use and trips the breaker.
    /// Separated so the rules are readable and unit-testable via DcaMath.
    function _decide(uint256 tick, uint256 price) internal returns (uint8 decision, string memory reason) {
        if (paused) {
            return (DECISION_SKIP, "paused");
        }
        if (price == 0) {
            return (DECISION_SKIP, "no price");
        }
        if (referencePrice == 0) {
            referencePrice = price;
            emit ReferencePriceSet(price);
        }
        if (DcaMath.breakerTripped(price, prevPrice)) {
            uint256 change = DcaMath.changeBps(price, prevPrice);
            paused = true;
            emit CircuitBreakerTriggered(tick, price, change);
            return (DECISION_SKIP, "circuit breaker: change >=20%");
        }
        if (!DcaMath.priceWithinBand(price, referencePrice)) {
            return (DECISION_SKIP, "outside +-30% band");
        }
        return (DECISION_BUY, "within band");
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 == syncTopic0) {
            (uint112 reserve0, uint112 reserve1) = abi.decode(log_.data, (uint112, uint112));
            syncCount++;
            lastReserve0 = reserve0;
            lastReserve1 = reserve1;
            lastSyncBlock = log_.blockNumber;
            emit SyncObserved(reserve0, reserve1, log_.blockNumber);
            if (callback != address(0)) {
                bytes memory payload = abi.encodeWithSignature(
                    "onPriceUpdate(address,uint256,uint256)",
                    address(0),
                    uint256(reserve0),
                    uint256(reserve1)
                );
                SYSTEM.requestCallbackV_1_0(
                    ISystemContract.CallbackConfiguration_V_1_0({
                        chainId: destinationChainId,
                        recipient: callback,
                        gasLimit: CALLBACK_GAS_LIMIT,
                        payload: payload
                    })
                );
                emit PriceCallbackRequested(callback, reserve0, reserve1);
            }
        } else if (log_.topic0 == CRON100_TOPIC_0) {
            cronTicks++;
            emit CronTick(cronTicks, log_.blockNumber);
            uint256 price = currentPrice();
            (uint8 decision, string memory reason) = _decide(cronTicks, price);
            decisionHistory.push(
                DecisionRecord({ tick: cronTicks, price: price, decision: decision, reason: reason })
            );
            lastDecision = decision;
            lastDecisionReason = reason;
            lastDecisionTick = cronTicks;
            if (price > 0) prevPrice = price;
            emit DcaDecision(cronTicks, price, decision, reason);
            if (decision == DECISION_BUY && callback != address(0)) {
                bytes memory payload = abi.encodeWithSignature(
                    "onDcaTick(address,uint256,uint8,uint256)",
                    address(0),
                    price,
                    decision,
                    buyAmount
                );
                SYSTEM.requestCallbackV_1_0(
                    ISystemContract.CallbackConfiguration_V_1_0({
                        chainId: destinationChainId,
                        recipient: callback,
                        gasLimit: CALLBACK_GAS_LIMIT,
                        payload: payload
                    })
                );
                emit DcaCallbackRequested(callback, cronTicks, price, buyAmount);
            }
        }
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
