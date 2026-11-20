// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title DcaMath — pure decision + pricing math for DCA Guard (Fase 2).
/// @notice Shared by DCAGuardReactive (decision) and DCAGuardCallback
/// (swap pricing) so the same rules are unit-tested once in test/DcaGuard.t.sol.
library DcaMath {
    /// @notice Buy band: price must stay within ±30% of the reference price.
    uint256 internal constant BAND_BPS = 3000;
    /// @notice Circuit breaker: |price change| >= 20% vs previous tick auto-pauses.
    uint256 internal constant BREAKER_BPS = 2000;
    uint256 internal constant BPS_DENOM = 10_000;

    /// @notice True when price is within ±BAND_BPS of the reference price.
    /// @dev ref == 0 means "no reference yet" — treated as in-band so the
    /// first tick can set the reference and still BUY.
    function priceWithinBand(uint256 price, uint256 ref) internal pure returns (bool) {
        if (ref == 0) return true;
        uint256 lo = (ref * (BPS_DENOM - BAND_BPS)) / BPS_DENOM;
        uint256 hi = (ref * (BPS_DENOM + BAND_BPS)) / BPS_DENOM;
        return price >= lo && price <= hi;
    }

    /// @notice Absolute price change vs previous tick, in basis points.
    /// @dev prev == 0 means "no previous tick" — change is 0 by definition.
    function changeBps(uint256 price, uint256 prev) internal pure returns (uint256) {
        if (prev == 0) return 0;
        uint256 diff = price >= prev ? price - prev : prev - price;
        return (diff * BPS_DENOM) / prev;
    }

    /// @notice True when the move vs previous tick trips the circuit breaker.
    function breakerTripped(uint256 price, uint256 prev) internal pure returns (bool) {
        if (prev == 0) return false;
        return changeBps(price, prev) >= BREAKER_BPS;
    }

    /// @notice Uniswap V2 amountOut with the 0.3% fee.
    /// @dev amountIn * 997 * reserveOut / (reserveIn * 1000 + amountIn * 997).
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "insufficient liquidity");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }
}
