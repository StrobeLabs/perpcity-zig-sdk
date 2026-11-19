// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct PricePair {
    uint128 ammPrice;
    uint128 index;
}

/// @title MockFees
/// @notice Minimal IFees implementation matching perpcity-contracts v1.0.0,
/// with a constant LP fee in place of the liquidity- and volatility-priced one.
contract MockFees {
    uint24 public immutable CREATOR_FEE;
    uint24 public immutable INSURANCE_FEE;
    uint24 public immutable LP_FEE;
    uint24 public immutable LIQ_FEE;
    uint64 public immutable UTIL_FEE_PER_DAY;

    constructor(
        uint24 creatorFee,
        uint24 insuranceFee,
        uint24 lpFee,
        uint24 liqFee,
        uint64 utilFeePerDay
    ) {
        CREATOR_FEE = creatorFee;
        INSURANCE_FEE = insuranceFee;
        LP_FEE = lpFee;
        LIQ_FEE = liqFee;
        UTIL_FEE_PER_DAY = utilFeePerDay;
    }

    function fees(uint128, PricePair calldata, PricePair calldata) external view returns (uint24, uint24, uint24) {
        return (CREATOR_FEE, INSURANCE_FEE, LP_FEE);
    }

    function maxSwapFee() external view returns (uint256) {
        return uint256(CREATOR_FEE) + INSURANCE_FEE + LP_FEE;
    }

    function utilFees(uint256, uint256) external view returns (uint64, uint64) {
        return (UTIL_FEE_PER_DAY, UTIL_FEE_PER_DAY);
    }

    function liqFee() external view returns (uint24) {
        return LIQ_FEE;
    }
}
