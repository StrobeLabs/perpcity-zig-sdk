// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockPriceImpact
/// @notice IPriceImpact returning wide bounds suitable for SDK ABI smoke tests.
contract MockPriceImpact {
    uint256 public constant MIN_SQRT_PRICE_X96 = 4295128739;
    uint256 public constant MAX_SQRT_PRICE_X96 = 1461446703485210103287273052203988822378723970342;

    function sqrtPriceBounds(uint256, uint256, uint256, uint256) external pure returns (uint256, uint256) {
        return (MIN_SQRT_PRICE_X96, MAX_SQRT_PRICE_X96);
    }
}
