// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title MockMarginRatios
/// @notice Minimal IMarginRatios implementation matching perpcity-contracts v0.1.0.
/// All ratios scaled by 1e6.
contract MockMarginRatios {
    uint24 public immutable INIT_MAKER;
    uint24 public immutable LIQ_MAKER;
    uint24 public immutable BACKSTOP_MAKER;
    uint24 public immutable INIT_TAKER;
    uint24 public immutable LIQ_TAKER;
    uint24 public immutable BACKSTOP_TAKER;

    constructor(
        uint24 initMaker,
        uint24 liqMaker,
        uint24 backstopMaker,
        uint24 initTaker,
        uint24 liqTaker,
        uint24 backstopTaker
    ) {
        INIT_MAKER = initMaker;
        LIQ_MAKER = liqMaker;
        BACKSTOP_MAKER = backstopMaker;
        INIT_TAKER = initTaker;
        LIQ_TAKER = liqTaker;
        BACKSTOP_TAKER = backstopTaker;
    }

    function makerMarginRatios() external view returns (uint24, uint24, uint24) {
        return (INIT_MAKER, LIQ_MAKER, BACKSTOP_MAKER);
    }

    function takerMarginRatios() external view returns (uint24, uint24, uint24) {
        return (INIT_TAKER, LIQ_TAKER, BACKSTOP_TAKER);
    }
}
