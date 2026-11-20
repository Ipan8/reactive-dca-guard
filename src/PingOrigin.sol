// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PingOrigin — origin contract on Base Sepolia (testnet).
/// @notice Emits a Ping event whenever anyone calls ping(). The Reactive
/// contract on Lasna subscribes to this event and answers with a callback.
contract PingOrigin {
    event Ping(address indexed sender, uint256 indexed value, uint256 timestamp);

    function ping(uint256 value) external {
        emit Ping(msg.sender, value, block.timestamp);
    }
}
