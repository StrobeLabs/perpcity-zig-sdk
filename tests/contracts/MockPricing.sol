// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockPricing
/// @notice IPricing.fairPrice returns the supplied ammPrice -- enough for SDK
/// integration tests that only inspect routing/decoding.
contract MockPricing {
    function fairPrice(uint256 ammPrice, uint256, uint256, uint256) external pure returns (uint256) {
        return ammPrice;
    }
}
