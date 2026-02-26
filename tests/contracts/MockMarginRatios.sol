// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockMarginRatios
/// @notice Returns configurable margin ratio constants matching the MarginRatios module ABI.
/// Ratios are scaled by 1e6 (e.g., 100000 = 10% = 10x leverage).
contract MockMarginRatios {
    uint24 public MIN_TAKER_RATIO;
    uint24 public MAX_TAKER_RATIO;
    uint24 public LIQUIDATION_TAKER_RATIO;
    uint24 public MIN_MAKER_RATIO;
    uint24 public MAX_MAKER_RATIO;
    uint24 public LIQUIDATION_MAKER_RATIO;

    constructor(
        uint24 minTaker,
        uint24 maxTaker,
        uint24 liqTaker,
        uint24 minMaker,
        uint24 maxMaker,
        uint24 liqMaker
    ) {
        MIN_TAKER_RATIO = minTaker;
        MAX_TAKER_RATIO = maxTaker;
        LIQUIDATION_TAKER_RATIO = liqTaker;
        MIN_MAKER_RATIO = minMaker;
        MAX_MAKER_RATIO = maxMaker;
        LIQUIDATION_MAKER_RATIO = liqMaker;
    }
}
