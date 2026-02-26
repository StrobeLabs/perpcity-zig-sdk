const std = @import("std");
const sdk = @import("perpcity_sdk");
const liquidity = sdk.liquidity;
const constants = sdk.constants;

// =============================================================================
// getSqrtRatioAtTick
// =============================================================================

test "getSqrtRatioAtTick - tick 0 should return Q96" {
    // At tick 0: price=1, sqrtPrice=1, so sqrtPriceX96 = Q96
    // The ratio starts at 2^128, then >> 32 gives 2^96 = Q96.
    const result = try liquidity.getSqrtRatioAtTick(0);
    try std.testing.expectEqual(constants.Q96, result);
}

test "getSqrtRatioAtTick - positive tick should give larger sqrtPrice than tick 0" {
    const at_0 = try liquidity.getSqrtRatioAtTick(0);
    const at_100 = try liquidity.getSqrtRatioAtTick(100);
    try std.testing.expect(at_100 > at_0);
}

test "getSqrtRatioAtTick - negative tick should give smaller sqrtPrice than tick 0" {
    const at_0 = try liquidity.getSqrtRatioAtTick(0);
    const at_neg100 = try liquidity.getSqrtRatioAtTick(-100);
    try std.testing.expect(at_neg100 < at_0);
}

test "getSqrtRatioAtTick - tick 1 should be slightly larger than Q96" {
    const at_0 = try liquidity.getSqrtRatioAtTick(0);
    const at_1 = try liquidity.getSqrtRatioAtTick(1);
    try std.testing.expect(at_1 > at_0);
    // The difference should be small (one tick step)
    const diff = at_1 - at_0;
    try std.testing.expect(diff < at_0 / 10_000);
}

test "getSqrtRatioAtTick - tick -1 should be slightly smaller than Q96" {
    const at_0 = try liquidity.getSqrtRatioAtTick(0);
    const at_neg1 = try liquidity.getSqrtRatioAtTick(-1);
    try std.testing.expect(at_neg1 < at_0);
    const diff = at_0 - at_neg1;
    try std.testing.expect(diff < at_0 / 10_000);
}

test "getSqrtRatioAtTick - symmetry: sqrtPrice(tick) * sqrtPrice(-tick) approx Q96^2" {
    const pos = try liquidity.getSqrtRatioAtTick(1000);
    const neg = try liquidity.getSqrtRatioAtTick(-1000);
    const product = pos * neg;
    const q96_squared = constants.Q96 * constants.Q96;
    const diff = if (product > q96_squared) product - q96_squared else q96_squared - product;
    try std.testing.expect(diff < q96_squared / 1_000_000);
}

test "getSqrtRatioAtTick - monotonically increasing with tick" {
    const at_neg500 = try liquidity.getSqrtRatioAtTick(-500);
    const at_0 = try liquidity.getSqrtRatioAtTick(0);
    const at_500 = try liquidity.getSqrtRatioAtTick(500);
    const at_1000 = try liquidity.getSqrtRatioAtTick(1000);
    try std.testing.expect(at_neg500 < at_0);
    try std.testing.expect(at_0 < at_500);
    try std.testing.expect(at_500 < at_1000);
}

test "getSqrtRatioAtTick - large positive tick 10000" {
    const result = try liquidity.getSqrtRatioAtTick(10000);
    try std.testing.expect(result > constants.Q96);
}

test "getSqrtRatioAtTick - large negative tick -10000" {
    const result = try liquidity.getSqrtRatioAtTick(-10000);
    try std.testing.expect(result < constants.Q96);
    try std.testing.expect(result > 0);
}

test "getSqrtRatioAtTick - out of range positive returns InvalidTickRange" {
    try std.testing.expectError(error.InvalidTickRange, liquidity.getSqrtRatioAtTick(887273));
}

test "getSqrtRatioAtTick - out of range negative returns InvalidTickRange" {
    try std.testing.expectError(error.InvalidTickRange, liquidity.getSqrtRatioAtTick(-887273));
}

test "getSqrtRatioAtTick - max valid tick 887272 does not error" {
    const result = try liquidity.getSqrtRatioAtTick(887272);
    try std.testing.expect(result > 0);
}

test "getSqrtRatioAtTick - min valid tick -887272 does not error" {
    const result = try liquidity.getSqrtRatioAtTick(-887272);
    try std.testing.expect(result > 0);
}

// =============================================================================
// estimateLiquidity
// =============================================================================

test "estimateLiquidity - basic range with non-zero USD returns > 0" {
    const result = try liquidity.estimateLiquidity(-100, 100, 1_000_000);
    try std.testing.expect(result > 0);
}

test "estimateLiquidity - larger USD should give larger liquidity" {
    const small = try liquidity.estimateLiquidity(-100, 100, 1_000_000);
    const large = try liquidity.estimateLiquidity(-100, 100, 10_000_000);
    try std.testing.expect(large > small);
}

test "estimateLiquidity - wider range should give smaller liquidity for same USD" {
    const narrow = try liquidity.estimateLiquidity(-100, 100, 1_000_000);
    const wide = try liquidity.estimateLiquidity(-1000, 1000, 1_000_000);
    try std.testing.expect(wide < narrow);
}

test "estimateLiquidity - tick_lower == tick_upper returns InvalidTickRange" {
    try std.testing.expectError(error.InvalidTickRange, liquidity.estimateLiquidity(100, 100, 1_000_000));
}

test "estimateLiquidity - tick_lower > tick_upper returns InvalidTickRange" {
    try std.testing.expectError(error.InvalidTickRange, liquidity.estimateLiquidity(200, 100, 1_000_000));
}

test "estimateLiquidity - zero USD returns ZeroLiquidity" {
    try std.testing.expectError(error.ZeroLiquidity, liquidity.estimateLiquidity(-100, 100, 0));
}

test "estimateLiquidity - large USD amount 1_000_000_000_000 returns > 0" {
    const result = try liquidity.estimateLiquidity(-1000, 1000, 1_000_000_000_000);
    try std.testing.expect(result > 0);
}

test "estimateLiquidity - adjacent ticks should give very large liquidity" {
    // Extremely narrow range should concentrate liquidity heavily
    const result = try liquidity.estimateLiquidity(0, 1, 1_000_000);
    try std.testing.expect(result > 0);
    // With a wider range, liquidity should be much less
    const wider = try liquidity.estimateLiquidity(0, 100, 1_000_000);
    try std.testing.expect(result > wider);
}

test "estimateLiquidity - negative tick range returns > 0" {
    const result = try liquidity.estimateLiquidity(-500, -100, 1_000_000);
    try std.testing.expect(result > 0);
}

test "estimateLiquidity - positive tick range returns > 0" {
    const result = try liquidity.estimateLiquidity(100, 500, 1_000_000);
    try std.testing.expect(result > 0);
}

// =============================================================================
// calculateLiquidityForTargetRatio
// =============================================================================

test "calculateLiquidityForTargetRatio - basic case at tick 0 returns > 0" {
    const result = try liquidity.calculateLiquidityForTargetRatio(
        1_000_000, // 1 USDC scaled
        -1000,
        1000,
        constants.Q96, // current price = 1.0
        0.1, // 10% margin ratio
    );
    try std.testing.expect(result > 0);
}

test "calculateLiquidityForTargetRatio - higher margin ratio gives lower liquidity" {
    const high_ratio = try liquidity.calculateLiquidityForTargetRatio(
        1_000_000,
        -1000,
        1000,
        constants.Q96,
        0.5, // 50% ratio
    );
    const low_ratio = try liquidity.calculateLiquidityForTargetRatio(
        1_000_000,
        -1000,
        1000,
        constants.Q96,
        0.1, // 10% ratio
    );
    // Lower margin ratio = more leverage = more liquidity
    try std.testing.expect(low_ratio > high_ratio);
}

test "calculateLiquidityForTargetRatio - rejects tick_lower >= tick_upper" {
    try std.testing.expectError(
        error.InvalidTickRange,
        liquidity.calculateLiquidityForTargetRatio(1_000_000, 100, 100, constants.Q96, 0.1),
    );
}

test "calculateLiquidityForTargetRatio - rejects target_margin_ratio of 0" {
    try std.testing.expectError(
        error.InvalidTargetRatio,
        liquidity.calculateLiquidityForTargetRatio(1_000_000, -100, 100, constants.Q96, 0.0),
    );
}

test "calculateLiquidityForTargetRatio - rejects target_margin_ratio of 1.0" {
    try std.testing.expectError(
        error.InvalidTargetRatio,
        liquidity.calculateLiquidityForTargetRatio(1_000_000, -100, 100, constants.Q96, 1.0),
    );
}

test "calculateLiquidityForTargetRatio - rejects zero margin" {
    try std.testing.expectError(
        error.ZeroLiquidity,
        liquidity.calculateLiquidityForTargetRatio(0, -100, 100, constants.Q96, 0.1),
    );
}
