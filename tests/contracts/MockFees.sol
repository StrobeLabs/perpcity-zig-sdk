// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockFees
/// @notice Returns configurable fee constants matching the Fees module ABI.
/// Fees are scaled by 1e6 (e.g., 1000 = 0.1%).
contract MockFees {
    uint24 public CREATOR_FEE;
    uint24 public INSURANCE_FEE;
    uint24 public LP_FEE;
    uint24 public LIQUIDATION_FEE;

    constructor(uint24 creatorFee, uint24 insuranceFee, uint24 lpFee, uint24 liquidationFee) {
        CREATOR_FEE = creatorFee;
        INSURANCE_FEE = insuranceFee;
        LP_FEE = lpFee;
        LIQUIDATION_FEE = liquidationFee;
    }
}
