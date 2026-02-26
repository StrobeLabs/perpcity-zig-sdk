const std = @import("std");
const constants = @import("constants.zig");

pub const ConversionError = error{
    PriceMustBePositive,
    PriceTooLarge,
    AmountTooLarge,
    ValueTooLarge,
    MarginRatioMustBePositive,
};

/// Convert a price (f64) to sqrtPriceX96 (u256).
/// Computes: sqrt(price) * 1e6 -> bigint -> * Q96 / 1e6
pub fn priceToSqrtPriceX96(price: f64) ConversionError!u256 {
    if (price <= 0.0) return error.PriceMustBePositive;
    if (price > 1e30) return error.PriceTooLarge;

    const sqrt_price = @sqrt(price);
    const scaled = sqrt_price * constants.F64_1E6;
    if (scaled > @as(f64, @floatFromInt(constants.MAX_SAFE_F64_INT))) {
        return error.PriceTooLarge;
    }

    // Convert via u128 to avoid LLVM aarch64 bug with fptoui -> i256
    const scaled_int: u256 = @as(u128, @intFromFloat(scaled));
    return (scaled_int * constants.Q96) / constants.BIGINT_1E6;
}

/// Scale a floating point amount to 6-decimal integer representation.
/// Supports negative values (matching the TS SDK behavior).
pub fn scale6Decimals(amount: f64) ConversionError!i128 {
    if (amount > @as(f64, @floatFromInt(constants.MAX_SAFE_F64_INT)) or
        amount < -@as(f64, @floatFromInt(constants.MAX_SAFE_F64_INT)))
    {
        return error.AmountTooLarge;
    }

    const scaled = amount * constants.F64_1E6;
    return @intFromFloat(@floor(scaled));
}

/// Scale a floating point amount to X96 fixed-point representation.
/// Computes: scale6Decimals(amount) * Q96 / 1e6
pub fn scaleToX96(amount: f64) ConversionError!u256 {
    if (amount < 0.0) return error.AmountTooLarge;

    const scaled = try scale6Decimals(amount);
    if (scaled < 0) return error.AmountTooLarge;

    const scaled_u: u256 = @intCast(scaled);
    return (scaled_u * constants.Q96) / constants.BIGINT_1E6;
}

/// Convert an X96 fixed-point value back to a floating point number.
/// Computes: (valueX96 * 1e6 / Q96) / 1e6
pub fn scaleFromX96(value_x96: u256) ConversionError!f64 {
    const intermediate = (value_x96 * constants.BIGINT_1E6) / constants.Q96;

    // Check if the intermediate fits in a safe f64 range
    if (intermediate > @as(u256, constants.MAX_SAFE_F64_INT)) {
        return error.ValueTooLarge;
    }

    const int_val: u64 = @intCast(intermediate);
    return @as(f64, @floatFromInt(int_val)) / constants.F64_1E6;
}

/// Convert a price to a Uniswap V4 tick.
/// tick = log(price) / log(1.0001)
/// If round_down is true, floor the result; otherwise ceil.
pub fn priceToTick(price: f64, round_down: bool) ConversionError!i32 {
    if (price <= 0.0) return error.PriceMustBePositive;

    const log_price = @log(price);
    const log_base: f64 = @log(1.0001);
    const tick_exact = log_price / log_base;

    if (round_down) {
        return @intFromFloat(@floor(tick_exact));
    } else {
        return @intFromFloat(@ceil(tick_exact));
    }
}

/// Convert a Uniswap V4 tick to a price.
/// price = 1.0001 ^ tick
pub fn tickToPrice(tick: i32) f64 {
    return std.math.pow(f64, 1.0001, @as(f64, @floatFromInt(tick)));
}

/// Convert a sqrtPriceX96 value to a price.
/// Computes: (sqrtPriceX96^2 / Q96) -> scaleFromX96
pub fn sqrtPriceX96ToPrice(sqrt_price_x96: u256) ConversionError!f64 {
    const squared = sqrt_price_x96 * sqrt_price_x96;
    const price_x96 = squared / constants.Q96;
    return scaleFromX96(price_x96);
}

/// Convert a margin ratio (scaled by 1e6) to leverage.
/// leverage = 1e6 / marginRatio
pub fn marginRatioToLeverage(margin_ratio: u32) ConversionError!f64 {
    if (margin_ratio == 0) return error.MarginRatioMustBePositive;
    return constants.F64_1E6 / @as(f64, @floatFromInt(margin_ratio));
}

/// Convert a 6-decimal scaled integer value to a floating point number.
/// value / 1e6
pub fn scaleFrom6Decimals(value: i64) f64 {
    return @as(f64, @floatFromInt(value)) / constants.F64_1E6;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "priceToSqrtPriceX96 basic" {
    // price = 1.0 => sqrtPrice = 1.0 => sqrtPriceX96 ~= Q96
    const result = try priceToSqrtPriceX96(1.0);
    // Should be approximately Q96
    const diff = if (result > constants.Q96) result - constants.Q96 else constants.Q96 - result;
    try std.testing.expect(diff < constants.Q96 / 1_000_000);
}

test "priceToSqrtPriceX96 rejects zero and negative" {
    try std.testing.expectError(error.PriceMustBePositive, priceToSqrtPriceX96(0.0));
    try std.testing.expectError(error.PriceMustBePositive, priceToSqrtPriceX96(-1.0));
}

test "scale6Decimals basic" {
    const result = try scale6Decimals(1.5);
    try std.testing.expectEqual(@as(i128, 1_500_000), result);
}

test "scale6Decimals negative" {
    const result = try scale6Decimals(-2.5);
    try std.testing.expectEqual(@as(i128, -2_500_000), result);
}

test "scaleToX96 basic" {
    const result = try scaleToX96(1.0);
    // Should be approximately Q96
    const diff = if (result > constants.Q96) result - constants.Q96 else constants.Q96 - result;
    try std.testing.expect(diff < constants.Q96 / 1_000_000);
}

test "scaleFromX96 basic" {
    const result = try scaleFromX96(constants.Q96);
    // Should be approximately 1.0
    try std.testing.expect(@abs(result - 1.0) < 0.000001);
}

test "priceToTick and tickToPrice roundtrip" {
    const price: f64 = 1500.0;
    const tick = try priceToTick(price, true);
    const recovered = tickToPrice(tick);
    // Should be close to original price (within one tick step)
    const ratio = recovered / price;
    try std.testing.expect(ratio > 0.999 and ratio < 1.001);
}

test "tickToPrice at tick 0" {
    const price = tickToPrice(0);
    try std.testing.expectEqual(@as(f64, 1.0), price);
}

test "sqrtPriceX96ToPrice basic" {
    const result = try sqrtPriceX96ToPrice(constants.Q96);
    try std.testing.expect(@abs(result - 1.0) < 0.000001);
}

test "marginRatioToLeverage basic" {
    // 100000 = 10% margin ratio => 10x leverage
    const result = try marginRatioToLeverage(100_000);
    try std.testing.expect(@abs(result - 10.0) < 0.0001);
}

test "marginRatioToLeverage rejects zero" {
    try std.testing.expectError(error.MarginRatioMustBePositive, marginRatioToLeverage(0));
}

test "scaleFrom6Decimals basic" {
    const result = scaleFrom6Decimals(1_500_000);
    try std.testing.expectEqual(@as(f64, 1.5), result);
}

test "scaleFrom6Decimals negative" {
    const result = scaleFrom6Decimals(-2_000_000);
    try std.testing.expectEqual(@as(f64, -2.0), result);
}
