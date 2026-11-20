// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title PingPongReactive — hello-world reactive contract on Lasna testnet.
/// @notice Subscribes to Ping events from PingOrigin on Base Sepolia and
/// answers each one with a callback to PingPongCallback on Base Sepolia.
/// Follows the official Omni docs pattern (dev.reactive.network).
contract PingPongReactive is AbstractReactive {
    uint256 public immutable originChainId;
    uint256 public immutable destinationChainId;
    address public immutable originContract;
    uint256 public immutable pingTopic0;

    address public owner;
    address public callback;
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;

    uint256 public reactCount;
    uint256 public lastValue;

    event Reacted(uint256 indexed chainId, address indexed origin, uint256 value, uint256 blockNumber);
    event CallbackRequested(address indexed callback, uint256 value);

    /// @notice Payable so the contract can be funded with lREACT at deploy.
    constructor(
        uint256 originChainId_,
        address originContract_,
        uint256 pingTopic0_,
        uint256 destinationChainId_
    ) payable {
        originChainId = originChainId_;
        originContract = originContract_;
        pingTopic0 = pingTopic0_;
        destinationChainId = destinationChainId_;
        owner = msg.sender;
        SYSTEM.subscribe(
            originChainId_,
            originContract_,
            pingTopic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    /// @notice Set the callback recipient (breaks the deploy-order cycle:
    /// RC first, callback second, then point the RC at it).
    function setCallback(address callback_) external onlyOwner {
        callback = callback_;
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        reactCount++;
        // Ping(address indexed sender, uint256 indexed value, uint256 timestamp)
        // topic0 = signature, topic1 = sender, topic2 = value.
        uint256 value = log_.topic2;
        lastValue = value;
        emit Reacted(log_.chainId, log_.contractAddress, value, log_.blockNumber);
        if (callback != address(0)) {
            bytes memory payload = abi.encodeWithSignature("pong(address,uint256)", address(0), value);
            SYSTEM.requestCallbackV_1_0(
                ISystemContract.CallbackConfiguration_V_1_0({
                    chainId: destinationChainId,
                    recipient: callback,
                    gasLimit: CALLBACK_GAS_LIMIT,
                    payload: payload
                })
            );
            emit CallbackRequested(callback, value);
        }
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
