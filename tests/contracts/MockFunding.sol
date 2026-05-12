// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct PricePair {
    uint128 ammPrice;
    uint128 index;
}

/// @title MockFunding
/// @notice Returns a configured constant funding rate. Outputs scaled by 1e18.
contract MockFunding {
    int88 public immutable FUNDING_PER_DAY;

    constructor(int88 fundingPerDay) {
        FUNDING_PER_DAY = fundingPerDay;
    }

    function funding(PricePair memory, PricePair memory) external view returns (int88) {
        return FUNDING_PER_DAY;
    }
}
