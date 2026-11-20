// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import { DCAGuardReactive } from "../src/DCAGuardReactive.sol";
import { DCAGuardCallback } from "../src/DCAGuardCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @notice FASE 2 deploy — Reactive side (Lasna 5318007).
/// Deploys DCAGuardReactive funded with 2 lREACT at construction.
/// Run: forge script script/DeployDCA2.s.sol:DeployDCA2Reactive
///   --rpc-url https://lasna-rpc.rnk.dev --account reactive-deployer
///   --password-file ~/.agent-wallets/reactive-deployer.pw --broadcast
contract DeployDCA2Reactive is Script {
    uint256 constant ORIGIN_CHAIN = 84532; // Base Sepolia (pair lives here)
    address constant PAIR = 0xeb1033094A4716d360A0828cf598cB09adbCF084;
    uint256 constant SYNC_TOPIC0 = 0x1c411e9a96e071241c2f21f7726b17ae89e3cab4c78be50e062b03a9fffbbad1;
    uint256 constant DEST_CHAIN = 84532;

    function run() external {
        vm.startBroadcast();
        DCAGuardReactive rc = new DCAGuardReactive{ value: 2 ether }(
            ORIGIN_CHAIN, PAIR, SYNC_TOPIC0, DEST_CHAIN
        );
        vm.stopBroadcast();
        console.log("DCAGuardReactive (Fase 2):", address(rc));
        console.log("owner:", rc.owner());
        console.log("buyAmount:", rc.buyAmount());
    }
}

/// @notice FASE 2 deploy — Callback side (Base Sepolia 84532).
/// Deploys DCAGuardCallback funded with 0.005 ETH at construction.
/// Needs DCA_RC env var = Fase 2 reactive contract address (Lasna).
/// Run: DCA_RC=0x... forge script script/DeployDCA2.s.sol:DeployDCA2Callback
///   --rpc-url https://sepolia.base.org --account reactive-deployer
///   --password-file ~/.agent-wallets/reactive-deployer.pw --broadcast
contract DeployDCA2Callback is Script {
    address payable constant CALLBACK_PROXY = payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant PAIR = 0xeb1033094A4716d360A0828cf598cB09adbCF084;
    address constant DCAT = 0x7350783C525C902f5dC2e8dDF4170978840269C2;

    function run() external {
        address rc = vm.envAddress("DCA_RC");
        vm.startBroadcast();
        DCAGuardCallback cb = new DCAGuardCallback{ value: 0.005 ether }(
            IPayable(CALLBACK_PROXY), rc, WETH, PAIR, DCAT
        );
        vm.stopBroadcast();
        console.log("DCAGuardCallback (Fase 2):", address(cb));
        console.log("callbackSender (RC):", rc);
        console.log("owner:", cb.owner());
    }
}
