// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockFees {
    uint24 public immutable CREATOR_FEE;
    uint24 public immutable INSURANCE_FEE;
    uint24 public immutable LP_FEE;
    uint24 public immutable LIQUIDATION_FEE;

    constructor(uint24 creatorFee, uint24 insuranceFee, uint24 lpFee, uint24 liquidationFee) {
        CREATOR_FEE = creatorFee;
        INSURANCE_FEE = insuranceFee;
        LP_FEE = lpFee;
        LIQUIDATION_FEE = liquidationFee;
    }
}
