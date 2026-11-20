// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "forge-std/Test.sol";
import { DcaMath } from "../src/DcaMath.sol";
import { DCAGuardCallback } from "../src/DCAGuardCallback.sol";
import { MiniFactory, MiniPair } from "../src/MiniAMM.sol";
import { MockToken } from "../src/MockToken.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @notice Minimal WETH9 stand-in for local tests (deposit mints 1:1).
contract MockWETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 value) external {
        require(balanceOf[msg.sender] >= value, "insufficient");
        balanceOf[msg.sender] -= value;
        payable(msg.sender).transfer(value);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "insufficient");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "insufficient");
        require(allowance[from][msg.sender] >= value, "allowance");
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// @notice External wrapper so DcaMath reverts can be tested via expectRevert.
contract DcaMathHarness {
    function amountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256) {
        return DcaMath.getAmountOut(amountIn, reserveIn, reserveOut);
    }
}

/// @title DCA Guard Fase 2 tests — decision math + local swap execution.
contract DcaGuardTest is Test {
    // ---- DcaMath: band ±30% ----
    function testBandEdges() public {
        uint256 ref = 1000 ether;
        assertTrue(DcaMath.priceWithinBand(1000 ether, ref));
        assertTrue(DcaMath.priceWithinBand(1300 ether, ref)); // +30% exactly: in
        assertTrue(DcaMath.priceWithinBand(700 ether, ref)); // -30% exactly: in
        assertFalse(DcaMath.priceWithinBand(1300 ether + 1, ref));
        assertFalse(DcaMath.priceWithinBand(700 ether - 1, ref));
        assertFalse(DcaMath.priceWithinBand(2000 ether, ref));
        assertFalse(DcaMath.priceWithinBand(100 ether, ref));
        assertTrue(DcaMath.priceWithinBand(123 ether, 0)); // no reference yet: in-band
    }

    // ---- DcaMath: circuit breaker 20% ----
    function testBreakerEdges() public {
        uint256 prev = 1000 ether;
        assertFalse(DcaMath.breakerTripped(1000 ether, prev));
        assertFalse(DcaMath.breakerTripped(1199 ether, prev)); // +19.9%: safe
        assertTrue(DcaMath.breakerTripped(1200 ether, prev)); // +20% exactly: trips
        assertFalse(DcaMath.breakerTripped(801 ether, prev)); // -19.9%: safe
        assertTrue(DcaMath.breakerTripped(800 ether, prev)); // -20% exactly: trips
        assertTrue(DcaMath.breakerTripped(2000 ether, prev));
        assertFalse(DcaMath.breakerTripped(999 ether, 0)); // no previous tick: never trips
        assertEq(DcaMath.changeBps(1200 ether, prev), 2000);
        assertEq(DcaMath.changeBps(800 ether, prev), 2000);
        assertEq(DcaMath.changeBps(1100 ether, prev), 1000);
    }

    // ---- DcaMath: V2 amountOut, 0.3% fee ----
    function testGetAmountOut() public {
        // Simple case, hand-computed: 1000 in, 100k/100k reserves -> 987 out.
        assertEq(DcaMath.getAmountOut(1000, 100_000, 100_000), 987);
        // Production-like reserves (0.0191 WETH / 21,000 DCAT), 0.001 WETH in.
        assertEq(DcaMath.getAmountOut(0.001 ether, 0.0191 ether, 21_000 ether), 1041797283176593521421);
        // Zero input / zero reserves revert (via external harness call).
        DcaMathHarness harness = new DcaMathHarness();
        vm.expectRevert("insufficient input");
        harness.amountOut(0, 100_000, 100_000);
        vm.expectRevert("insufficient liquidity");
        harness.amountOut(1000, 0, 100_000);
    }

    // ---- Callback: real swap on a local MiniAMM pair ----
    function _deployPairWithLiquidity() internal returns (MockWETH weth, MockToken dcat, MiniPair pair) {
        vm.deal(address(this), 10 ether);
        dcat = new MockToken();
        // Deploy WETH via CREATE2 until its address sorts below DCAT,
        // mirroring production (WETH 0x4200... < DCAT 0x7350... => token0).
        for (uint256 i = 0; i < 1000; i++) {
            weth = new MockWETH{ salt: bytes32(i) }();
            if (address(weth) < address(dcat)) break;
            require(i < 999, "no low weth address");
        }
        MiniFactory factory = new MiniFactory();
        address pairAddr = factory.createPair(address(weth), address(dcat));
        pair = MiniPair(pairAddr);
        assertEq(pair.token0(), address(weth));
        assertEq(pair.token1(), address(dcat));

        weth.deposit{ value: 0.03 ether }();
        dcat.mint(address(this), 20_000 ether);
        weth.transfer(pairAddr, 0.02 ether);
        dcat.transfer(pairAddr, 20_000 ether);
        pair.mint(address(this));
    }

    function testCallbackExecutesBuy() public {
        (MockWETH weth, MockToken dcat, MiniPair pair) = _deployPairWithLiquidity();
        address fakeReactive = address(0xBEEF);
        // This test contract acts as the callback proxy (msg.sender == proxy).
        DCAGuardCallback cb = new DCAGuardCallback(
            IPayable(payable(address(this))), fakeReactive, address(weth), address(pair), address(dcat)
        );
        weth.transfer(address(cb), 0.01 ether);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 expectedOut = DcaMath.getAmountOut(0.001 ether, uint256(r0), uint256(r1));

        cb.onDcaTick(fakeReactive, 1_100_000 ether, 1, 0.001 ether);

        assertEq(cb.buyCount(), 1);
        assertEq(cb.skipCount(), 0);
        assertEq(cb.totalWethSpent(), 0.001 ether);
        assertEq(cb.totalDcatBought(), expectedOut);
        assertEq(dcat.balanceOf(address(cb)), expectedOut);
        assertEq(weth.balanceOf(address(cb)), 0.009 ether);
        assertGt(cb.lastBuyPrice(), 0);
        (uint112 r0b, uint112 r1b,) = pair.getReserves();
        assertEq(uint256(r0b), uint256(r0) + 0.001 ether);
        assertEq(uint256(r1b), uint256(r1) - expectedOut);
    }

    function testCallbackSkipsWithoutRevertWhenWethShort() public {
        (MockWETH weth, MockToken dcat, MiniPair pair) = _deployPairWithLiquidity();
        address fakeReactive = address(0xBEEF);
        DCAGuardCallback cb = new DCAGuardCallback(
            IPayable(payable(address(this))), fakeReactive, address(weth), address(pair), address(dcat)
        );
        // Callback holds 0 WETH — BUY must skip, not revert.
        cb.onDcaTick(fakeReactive, 1_100_000 ether, 1, 0.001 ether);
        assertEq(cb.buyCount(), 0);
        assertEq(cb.skipCount(), 1);
        assertEq(cb.totalDcatBought(), 0);
        // A non-BUY decision also skips cleanly.
        cb.onDcaTick(fakeReactive, 1_100_000 ether, 2, 0.001 ether);
        assertEq(cb.skipCount(), 2);
    }

    function testCallbackRejectsWrongSender() public {
        (MockWETH weth, MockToken dcat, MiniPair pair) = _deployPairWithLiquidity();
        address fakeReactive = address(0xBEEF);
        DCAGuardCallback cb = new DCAGuardCallback(
            IPayable(payable(address(this))), fakeReactive, address(weth), address(pair), address(dcat)
        );
        vm.expectRevert();
        cb.onDcaTick(address(0xDEAD), 1_100_000 ether, 1, 0.001 ether);
    }
}
