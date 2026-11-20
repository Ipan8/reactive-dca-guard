// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title PingPongCallback — destination contract on Base Sepolia (testnet).
/// @notice Receives callbacks from PingPongReactive on Lasna. The callback
/// proxy overwrites the first payload argument with the RC address, so both
/// guards (onlyServiceProvider + onlyCallbackSender) authenticate the call.
contract PingPongCallback is AbstractCallback {
    uint256 public pongs;
    uint256 public lastValue;
    uint256 public lastTimestamp;

    event PongReceived(address indexed reactive, uint256 value, uint256 timestamp);

    /// @notice Payable so the contract can be funded with Base Sepolia ETH at deploy.
    constructor(IPayable callbackProxy_, address callbackSender_)
        payable
        AbstractCallback(callbackProxy_, callbackSender_)
    {}

    function pong(address reactive_, uint256 value_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        pongs++;
        lastValue = value_;
        lastTimestamp = block.timestamp;
        emit PongReceived(reactive_, value_, block.timestamp);
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
