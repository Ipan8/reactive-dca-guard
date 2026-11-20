// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Script.sol";
import { MiniFactory, MiniPair } from "../src/MiniAMM.sol";
import { MockToken } from "../src/MockToken.sol";

interface IWETH9 {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
}

/// @notice Deploys the DCA Guard AMM foundation on Base Sepolia testnet:
/// MockToken (DCAT), MiniFactory (V2-compatible), WETH/DCAT pair + initial
/// liquidity (0.02 WETH + 20,000 DCAT).
contract DeployDCA is Script {
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DEPLOYER = 0xa9cB01C54930511202fd75734bcdDe8FbE9B2453;

    function run() external {
        vm.startBroadcast();
        MockToken token = new MockToken();
        token.mint(DEPLOYER, 1_000_000 ether);

        MiniFactory factory = new MiniFactory();
        address pair = factory.createPair(WETH, address(token));

        IWETH9(WETH).deposit{value: 0.02 ether}();
        IWETH9(WETH).transfer(pair, 0.02 ether);
        token.transfer(pair, 20_000 ether);
        MiniPair(pair).mint(DEPLOYER);
        vm.stopBroadcast();

        console.log("MockToken (DCAT):", address(token));
        console.log("Factory:", address(factory));
        console.log("Pair:", pair);
        console.log("token0:", MiniPair(pair).token0());
        console.log("token1:", MiniPair(pair).token1());
        (uint112 r0, uint112 r1,) = MiniPair(pair).getReserves();
        console.log("reserve0:", r0);
        console.log("reserve1:", r1);
    }
}
