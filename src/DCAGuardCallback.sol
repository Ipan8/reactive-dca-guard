// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { DcaMath } from "./DcaMath.sol";

interface IERC20Mini {
    function balanceOf(address owner) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}

interface IWETH9Mini is IERC20Mini {
    function deposit() external payable;
    function withdraw(uint256 value) external;
}

interface IMiniPair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;
}

/// @title DCAGuardCallback — destination contract for DCA Guard (Base Sepolia).
/// @notice FASE 2: executes real DCA buys.
///  - `onPriceUpdate` (unchanged from Fase 1): records reserves + price.
///  - `onDcaTick` (new): on a BUY decision from the reactive contract, swaps
///    a fixed WETH amount for DCAT on our MiniAMM pair (WETH -> DCAT,
///    token0 -> token1) using the V2 0.3%-fee formula. If the callback holds
///    too little WETH it emits DcaSkipped and does NOT revert, so one failed
///    buy never blocks later ticks.
///  - `wrapEth`: turns plain ETH held by this contract into WETH (funding path).
/// FASE 1 contract (0x65c58531814906A70BcCB1c759E630bca7259829) is left deployed
/// untouched as an artifact; this is a fresh deployment.
contract DCAGuardCallback is AbstractCallback {
    uint8 internal constant DECISION_BUY = 1;

    address public immutable weth;
    address public immutable pair;
    address public immutable dcat;
    address public owner;

    uint256 public updateCount;
    uint256 public lastReserve0;
    uint256 public lastReserve1;
    uint256 public lastPrice; // token1 per token0, scaled by 1e18
    uint256 public lastUpdate;

    // ---- Fase 2: DCA execution state ----
    uint256 public buyCount;
    uint256 public skipCount;
    uint256 public totalDcatBought;
    uint256 public totalWethSpent;
    uint256 public lastBuyAmountIn;
    uint256 public lastBuyAmountOut;
    uint256 public lastBuyPrice; // DCAT per WETH executed, 1e18-scaled

    event PriceUpdated(
        address indexed reactive,
        uint256 reserve0,
        uint256 reserve1,
        uint256 price,
        uint256 timestamp
    );
    event DcaBuy(
        address indexed reactive,
        uint256 amountIn,
        uint256 amountOut,
        uint256 execPrice,
        uint256 timestamp
    );
    event DcaSkipped(address indexed reactive, string reason);

    /// @notice Payable so the contract can be funded with Base Sepolia ETH at deploy.
    constructor(IPayable callbackProxy_, address callbackSender_, address weth_, address pair_, address dcat_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {
        owner = msg.sender;
        weth = weth_;
        pair = pair_;
        dcat = dcat_;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function onPriceUpdate(address reactive_, uint256 reserve0_, uint256 reserve1_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        updateCount++;
        lastReserve0 = reserve0_;
        lastReserve1 = reserve1_;
        lastPrice = reserve0_ > 0 ? (reserve1_ * 1e18) / reserve0_ : 0;
        lastUpdate = block.timestamp;
        emit PriceUpdated(reactive_, reserve0_, reserve1_, lastPrice, block.timestamp);
    }

    /// @notice Executes one DCA buy when the reactive contract decided BUY.
    /// @dev Guards identical to onPriceUpdate. Never reverts on a skipped buy.
    function onDcaTick(address reactive_, uint256 price_, uint8 decision_, uint256 amountIn_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        price_; // price is recorded by the RC; execution uses live reserves.
        if (decision_ != DECISION_BUY) {
            skipCount++;
            emit DcaSkipped(reactive_, "not BUY");
            return;
        }
        if (amountIn_ == 0) {
            skipCount++;
            emit DcaSkipped(reactive_, "zero amount");
            return;
        }
        if (IERC20Mini(weth).balanceOf(address(this)) < amountIn_) {
            skipCount++;
            emit DcaSkipped(reactive_, "insufficient WETH");
            return;
        }
        (uint112 reserve0, uint112 reserve1,) = IMiniPair(pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            skipCount++;
            emit DcaSkipped(reactive_, "no liquidity");
            return;
        }
        uint256 amountOut = DcaMath.getAmountOut(amountIn_, uint256(reserve0), uint256(reserve1));
        if (amountOut == 0 || amountOut >= uint256(reserve1)) {
            skipCount++;
            emit DcaSkipped(reactive_, "zero output");
            return;
        }
        // WETH (token0) in, DCAT (token1) out.
        require(IERC20Mini(weth).transfer(pair, amountIn_), "weth transfer failed");
        IMiniPair(pair).swap(0, amountOut, address(this));
        buyCount++;
        totalDcatBought += amountOut;
        totalWethSpent += amountIn_;
        lastBuyAmountIn = amountIn_;
        lastBuyAmountOut = amountOut;
        lastBuyPrice = (amountOut * 1e18) / amountIn_;
        emit DcaBuy(reactive_, amountIn_, amountOut, lastBuyPrice, block.timestamp);
    }

    /// @notice Wrap this contract's ETH balance (or msg.value) into WETH.
    function wrapEth() external payable {
        IWETH9Mini(weth).deposit{ value: msg.value }();
    }

    /// @notice Wrap the contract's whole plain-ETH balance into WETH.
    function wrapBalance() external {
        uint256 bal = address(this).balance;
        require(bal > 0, "no eth");
        IWETH9Mini(weth).deposit{ value: bal }();
    }

    // ---- Testnet owner helpers (recover funds, never mainnet) ----
    function withdrawWeth(uint256 amount_) external onlyOwner {
        require(IERC20Mini(weth).transfer(msg.sender, amount_), "transfer failed");
    }

    function withdrawDcat(uint256 amount_) external onlyOwner {
        require(IERC20Mini(dcat).transfer(msg.sender, amount_), "transfer failed");
    }

    function withdrawEth(uint256 amount_) external onlyOwner {
        (bool ok,) = payable(msg.sender).call{ value: amount_ }("");
        require(ok, "eth transfer failed");
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
