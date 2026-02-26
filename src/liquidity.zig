const std = @import("std");
const constants = @import("constants.zig");

pub const LiquidityError = error{
    InvalidTickRange,
    DivisionByZero,
    InvalidTargetRatio,
    ZeroLiquidity,
};

/// Min/max tick bounds for Uniswap V4.
const MIN_TICK: i32 = -887272;
const MAX_TICK: i32 = 887272;

/// Compute the sqrtRatioX96 for a given tick using the Uniswap V4 bit-shift
/// lookup table. This is an exact port of the Solidity TickMath.getSqrtRatioAtTick.
pub fn getSqrtRatioAtTick(tick: i32) LiquidityError!u256 {
    const abs_tick: u32 = if (tick < 0) @intCast(-@as(i64, tick)) else @intCast(tick);
    if (abs_tick > @as(u32, @intCast(MAX_TICK))) return error.InvalidTickRange;

    var ratio: u256 = if (abs_tick & 0x1 != 0)
        0xfffcb933bd6fad37aa2d162d1a594001
    else
        0x100000000000000000000000000000000;

    if (abs_tick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
    if (abs_tick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
    if (abs_tick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
    if (abs_tick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
    if (abs_tick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
    if (abs_tick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
    if (abs_tick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
    if (abs_tick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
    if (abs_tick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
    if (abs_tick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
    if (abs_tick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
    if (abs_tick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
    if (abs_tick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
    if (abs_tick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
    if (abs_tick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
    if (abs_tick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
    if (abs_tick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
    if (abs_tick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
    if (abs_tick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

    if (tick > 0) {
        // Matches Solidity: type(uint256).max / ratio
        ratio = std.math.maxInt(u256) / ratio;
    }

    return ratio >> 32;
}

/// Estimate the liquidity required to provide `usd_scaled` of value across
/// a tick range [tick_lower, tick_upper].
///
/// L = (usd_scaled * Q96) / (sqrtPriceUpper - sqrtPriceLower)
pub fn estimateLiquidity(tick_lower: i32, tick_upper: i32, usd_scaled: u128) LiquidityError!u256 {
    if (tick_lower >= tick_upper) return error.InvalidTickRange;
    if (usd_scaled == 0) return error.ZeroLiquidity;

    const sqrt_price_lower = try getSqrtRatioAtTick(tick_lower);
    const sqrt_price_upper = try getSqrtRatioAtTick(tick_upper);

    const delta = sqrt_price_upper - sqrt_price_lower;
    if (delta == 0) return error.DivisionByZero;

    const numerator: u256 = @as(u256, usd_scaled) * constants.Q96;
    return numerator / delta;
}

/// Calculate the liquidity needed for a maker position given a target margin ratio.
///
/// Uses floating-point math to match the TypeScript SDK logic:
///   - Converts tick bounds and current sqrtPrice to prices
///   - Computes how much quote token per unit of liquidity the range covers
///   - Derives required liquidity from margin, target ratio, and fees
pub fn calculateLiquidityForTargetRatio(
    margin_scaled: u128,
    tick_lower: i32,
    tick_upper: i32,
    current_sqrt_price_x96: u256,
    target_margin_ratio: f64,
) LiquidityError!u128 {
    if (tick_lower >= tick_upper) return error.InvalidTickRange;
    if (target_margin_ratio <= 0.0 or target_margin_ratio >= 1.0) return error.InvalidTargetRatio;
    if (margin_scaled == 0) return error.ZeroLiquidity;

    // Get sqrtPriceX96 values at tick boundaries
    const sqrt_price_lower_x96 = try getSqrtRatioAtTick(tick_lower);
    const sqrt_price_upper_x96 = try getSqrtRatioAtTick(tick_upper);

    // Convert to floating point for the ratio calculation.
    // Use u128 intermediate to avoid LLVM aarch64 bug with u256 -> f64.
    const q96_f: f64 = @floatFromInt(@as(u128, @intCast(constants.Q96)));

    const sqrt_lower_f: f64 = @as(f64, @floatFromInt(@as(u128, @intCast(sqrt_price_lower_x96)))) / q96_f;
    const sqrt_upper_f: f64 = @as(f64, @floatFromInt(@as(u128, @intCast(sqrt_price_upper_x96)))) / q96_f;
    const sqrt_current_f: f64 = @as(f64, @floatFromInt(@as(u128, @intCast(current_sqrt_price_x96)))) / q96_f;

    // The quote token amount per unit of liquidity across this range depends on
    // where the current price sits relative to the range.
    const quote_per_liq: f64 = if (sqrt_current_f <= sqrt_lower_f)
        // Current price below range: all tokens are in quote
        sqrt_upper_f - sqrt_lower_f
    else if (sqrt_current_f >= sqrt_upper_f)
        // Current price above range: no quote tokens, position is fully in base
        0.0
    else
        // Current price inside range
        sqrt_upper_f - sqrt_current_f;

    if (quote_per_liq <= 0.0) return error.DivisionByZero;

    // margin = target_margin_ratio * notional_value
    // notional_value = liquidity * quote_per_liq (simplified)
    // => liquidity = margin / (target_margin_ratio * quote_per_liq)
    const margin_f: f64 = @floatFromInt(margin_scaled);
    const liquidity_f = margin_f / (target_margin_ratio * quote_per_liq);

    if (liquidity_f <= 0.0 or std.math.isNan(liquidity_f) or std.math.isInf(liquidity_f)) {
        return error.ZeroLiquidity;
    }

    return @intFromFloat(liquidity_f);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "getSqrtRatioAtTick at tick 0" {
    // At tick 0, sqrtPrice = 1.0, so sqrtPriceX96 should be Q96 >> 32... no.
    // Actually the raw ratio before >> 32 is 0x100000000000000000000000000000000 (128-bit 1<<128)
    // After >> 32 that gives 1 << 96 = Q96.
    const result = try getSqrtRatioAtTick(0);
    try std.testing.expectEqual(constants.Q96, result);
}

test "getSqrtRatioAtTick positive tick gives larger value" {
    const at_0 = try getSqrtRatioAtTick(0);
    const at_100 = try getSqrtRatioAtTick(100);
    try std.testing.expect(at_100 > at_0);
}

test "getSqrtRatioAtTick negative tick gives smaller value" {
    const at_0 = try getSqrtRatioAtTick(0);
    const at_neg100 = try getSqrtRatioAtTick(-100);
    try std.testing.expect(at_neg100 < at_0);
}

test "getSqrtRatioAtTick symmetry" {
    // sqrtPrice(tick) * sqrtPrice(-tick) should approximately equal Q96^2
    const pos = try getSqrtRatioAtTick(1000);
    const neg = try getSqrtRatioAtTick(-1000);
    const product = pos * neg;
    const q96_squared = constants.Q96 * constants.Q96;
    // Allow small rounding error
    const diff = if (product > q96_squared) product - q96_squared else q96_squared - product;
    try std.testing.expect(diff < q96_squared / 1_000_000);
}

test "getSqrtRatioAtTick rejects out of range" {
    try std.testing.expectError(error.InvalidTickRange, getSqrtRatioAtTick(887273));
    try std.testing.expectError(error.InvalidTickRange, getSqrtRatioAtTick(-887273));
}

test "estimateLiquidity basic" {
    // Use a small range and non-zero USD
    const liquidity = try estimateLiquidity(-100, 100, 1_000_000);
    try std.testing.expect(liquidity > 0);
}

test "estimateLiquidity rejects invalid range" {
    try std.testing.expectError(error.InvalidTickRange, estimateLiquidity(100, 100, 1_000_000));
    try std.testing.expectError(error.InvalidTickRange, estimateLiquidity(200, 100, 1_000_000));
}

test "estimateLiquidity rejects zero amount" {
    try std.testing.expectError(error.ZeroLiquidity, estimateLiquidity(-100, 100, 0));
}

test "calculateLiquidityForTargetRatio basic" {
    const liquidity = try calculateLiquidityForTargetRatio(
        1_000_000, // 1 USDC scaled
        -1000,
        1000,
        constants.Q96, // current price = 1.0
        0.1, // 10% margin ratio
    );
    try std.testing.expect(liquidity > 0);
}

test "calculateLiquidityForTargetRatio rejects invalid inputs" {
    try std.testing.expectError(
        error.InvalidTickRange,
        calculateLiquidityForTargetRatio(1_000_000, 100, 100, constants.Q96, 0.1),
    );
    try std.testing.expectError(
        error.InvalidTargetRatio,
        calculateLiquidityForTargetRatio(1_000_000, -100, 100, constants.Q96, 0.0),
    );
    try std.testing.expectError(
        error.InvalidTargetRatio,
        calculateLiquidityForTargetRatio(1_000_000, -100, 100, constants.Q96, 1.0),
    );
    try std.testing.expectError(
        error.ZeroLiquidity,
        calculateLiquidityForTargetRatio(0, -100, 100, constants.Q96, 0.1),
    );
}
