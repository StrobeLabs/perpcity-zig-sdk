const std = @import("std");
const sdk = @import("perpcity_sdk");
const conversions = sdk.conversions;
const constants = sdk.constants;

// =============================================================================
// priceToSqrtPriceX96
// =============================================================================

test "priceToSqrtPriceX96 - price of 1 should approximately equal Q96" {
    const result = try conversions.priceToSqrtPriceX96(1.0);
    // sqrt(1) * Q96 = Q96
    const diff = if (result > constants.Q96) result - constants.Q96 else constants.Q96 - result;
    try std.testing.expect(diff < constants.Q96 / 1_000_000);
}

test "priceToSqrtPriceX96 - price of 100 should be approximately 10 * Q96" {
    const result = try conversions.priceToSqrtPriceX96(100.0);
    // sqrt(100) = 10, so result ~ 10 * Q96
    try std.testing.expect(result > 0);
    const expected = constants.Q96 * 10;
    const diff = if (result > expected) result - expected else expected - result;
    try std.testing.expect(diff < expected / 1_000_000);
}

test "priceToSqrtPriceX96 - decimal price 0.5 should be between 0 and Q96" {
    const result = try conversions.priceToSqrtPriceX96(0.5);
    try std.testing.expect(result > 0);
    try std.testing.expect(result < constants.Q96);
}

test "priceToSqrtPriceX96 - very small price 0.0001 should be > 0" {
    const result = try conversions.priceToSqrtPriceX96(0.0001);
    try std.testing.expect(result > 0);
    try std.testing.expect(result < constants.Q96);
}

test "priceToSqrtPriceX96 - large price 1_000_000 should be > Q96" {
    const result = try conversions.priceToSqrtPriceX96(1_000_000.0);
    try std.testing.expect(result > constants.Q96);
}

test "priceToSqrtPriceX96 - zero price returns PriceMustBePositive" {
    try std.testing.expectError(error.PriceMustBePositive, conversions.priceToSqrtPriceX96(0.0));
}

test "priceToSqrtPriceX96 - negative price returns PriceMustBePositive" {
    try std.testing.expectError(error.PriceMustBePositive, conversions.priceToSqrtPriceX96(-1.0));
}

test "priceToSqrtPriceX96 - negative fractional price returns PriceMustBePositive" {
    try std.testing.expectError(error.PriceMustBePositive, conversions.priceToSqrtPriceX96(-0.5));
}

// =============================================================================
// scale6Decimals
// =============================================================================

test "scale6Decimals - 100 should return 100_000_000" {
    const result = try conversions.scale6Decimals(100.0);
    try std.testing.expectEqual(@as(i128, 100_000_000), result);
}

test "scale6Decimals - 100.5 should return 100_500_000" {
    const result = try conversions.scale6Decimals(100.5);
    try std.testing.expectEqual(@as(i128, 100_500_000), result);
}

test "scale6Decimals - 0 should return 0" {
    const result = try conversions.scale6Decimals(0.0);
    try std.testing.expectEqual(@as(i128, 0), result);
}

test "scale6Decimals - 0.000001 should return 1" {
    const result = try conversions.scale6Decimals(0.000001);
    try std.testing.expectEqual(@as(i128, 1), result);
}

test "scale6Decimals - 100.5555555 should floor to 100_555_555" {
    const result = try conversions.scale6Decimals(100.5555555);
    try std.testing.expectEqual(@as(i128, 100_555_555), result);
}

test "scale6Decimals - negative value -100 should return -100_000_000" {
    const result = try conversions.scale6Decimals(-100.0);
    try std.testing.expectEqual(@as(i128, -100_000_000), result);
}

test "scale6Decimals - negative decimal -2.5 should return -2_500_000" {
    const result = try conversions.scale6Decimals(-2.5);
    try std.testing.expectEqual(@as(i128, -2_500_000), result);
}

test "scale6Decimals - 1 should return 1_000_000" {
    const result = try conversions.scale6Decimals(1.0);
    try std.testing.expectEqual(@as(i128, 1_000_000), result);
}

test "scale6Decimals - 0.5 should return 500_000" {
    const result = try conversions.scale6Decimals(0.5);
    try std.testing.expectEqual(@as(i128, 500_000), result);
}

test "scale6Decimals - 1.999999 should return 1_999_999" {
    const result = try conversions.scale6Decimals(1.999999);
    try std.testing.expectEqual(@as(i128, 1_999_999), result);
}

// =============================================================================
// scaleToX96
// =============================================================================

test "scaleToX96 - 100 should return approximately 100 * Q96" {
    const result = try conversions.scaleToX96(100.0);
    const expected = constants.Q96 * 100;
    const diff = if (result > expected) result - expected else expected - result;
    try std.testing.expect(diff < expected / 1_000_000);
}

test "scaleToX96 - 1 should return approximately Q96" {
    const result = try conversions.scaleToX96(1.0);
    const diff = if (result > constants.Q96) result - constants.Q96 else constants.Q96 - result;
    try std.testing.expect(diff < constants.Q96 / 1_000_000);
}

test "scaleToX96 - 0.5 should be between 0 and Q96" {
    const result = try conversions.scaleToX96(0.5);
    try std.testing.expect(result > 0);
    try std.testing.expect(result < constants.Q96);
}

test "scaleToX96 - 0 should return 0" {
    const result = try conversions.scaleToX96(0.0);
    try std.testing.expectEqual(@as(u256, 0), result);
}

test "scaleToX96 - negative value should return AmountTooLarge" {
    try std.testing.expectError(error.AmountTooLarge, conversions.scaleToX96(-1.0));
}

test "scaleToX96 - 10 should be 10x Q96" {
    const result = try conversions.scaleToX96(10.0);
    const expected = constants.Q96 * 10;
    const diff = if (result > expected) result - expected else expected - result;
    try std.testing.expect(diff < expected / 1_000_000);
}

// =============================================================================
// scaleFromX96
// =============================================================================

test "scaleFromX96 - 100 * Q96 should return approximately 100.0" {
    const result = try conversions.scaleFromX96(constants.Q96 * 100);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), result, 0.001);
}

test "scaleFromX96 - Q96 should return approximately 1.0" {
    const result = try conversions.scaleFromX96(constants.Q96);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result, 0.000001);
}

test "scaleFromX96 - Q96 / 2 should return approximately 0.5" {
    const result = try conversions.scaleFromX96(constants.Q96 / 2);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), result, 0.001);
}

test "scaleFromX96 - 0 should return 0.0" {
    const result = try conversions.scaleFromX96(0);
    try std.testing.expectEqual(@as(f64, 0.0), result);
}

test "scaleFromX96 - 10 * Q96 should return approximately 10.0" {
    const result = try conversions.scaleFromX96(constants.Q96 * 10);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result, 0.001);
}

test "scaleFromX96 - 50 * Q96 should return approximately 50.0" {
    const result = try conversions.scaleFromX96(constants.Q96 * 50);
    try std.testing.expectApproxEqAbs(@as(f64, 50.0), result, 0.001);
}

// =============================================================================
// priceToTick
// =============================================================================

test "priceToTick - price of 1 with round_down gives tick 0" {
    const tick = try conversions.priceToTick(1.0, true);
    try std.testing.expectEqual(@as(i32, 0), tick);
}

test "priceToTick - price of 1 with round_up gives tick 0" {
    const tick = try conversions.priceToTick(1.0, false);
    try std.testing.expectEqual(@as(i32, 0), tick);
}

test "priceToTick - 1.0001^100 should give tick approximately 100" {
    const price = std.math.pow(f64, 1.0001, 100.0);
    const tick_down = try conversions.priceToTick(price, true);
    const tick_up = try conversions.priceToTick(price, false);
    // Due to floating point, tick should be very close to 100
    try std.testing.expect(tick_down >= 99 and tick_down <= 100);
    try std.testing.expect(tick_up >= 100 and tick_up <= 101);
}

test "priceToTick - price less than 1 gives negative tick" {
    const tick = try conversions.priceToTick(0.5, true);
    try std.testing.expect(tick < 0);
}

test "priceToTick - very small price gives large negative tick" {
    const tick = try conversions.priceToTick(0.001, true);
    try std.testing.expect(tick < -1000);
}

test "priceToTick - large price gives large positive tick" {
    const tick = try conversions.priceToTick(1000.0, true);
    try std.testing.expect(tick > 1000);
}

test "priceToTick - zero price returns PriceMustBePositive" {
    try std.testing.expectError(error.PriceMustBePositive, conversions.priceToTick(0.0, true));
}

test "priceToTick - negative price returns PriceMustBePositive" {
    try std.testing.expectError(error.PriceMustBePositive, conversions.priceToTick(-5.0, true));
}

test "priceToTick - round_down and round_up differ for non-integer ticks" {
    // A price that doesn't land exactly on a tick
    const price: f64 = 1.5;
    const tick_down = try conversions.priceToTick(price, true);
    const tick_up = try conversions.priceToTick(price, false);
    // ceil >= floor
    try std.testing.expect(tick_up >= tick_down);
}

test "priceToTick - 1.0001^(-100) should give tick approximately -100" {
    const price = std.math.pow(f64, 1.0001, -100.0);
    const tick = try conversions.priceToTick(price, true);
    try std.testing.expect(tick >= -101 and tick <= -99);
}

// =============================================================================
// tickToPrice
// =============================================================================

test "tickToPrice - tick 0 should return 1.0" {
    const price = conversions.tickToPrice(0);
    try std.testing.expectEqual(@as(f64, 1.0), price);
}

test "tickToPrice - positive tick should return > 1.0" {
    const price = conversions.tickToPrice(100);
    try std.testing.expect(price > 1.0);
}

test "tickToPrice - negative tick should return < 1.0" {
    const price = conversions.tickToPrice(-100);
    try std.testing.expect(price < 1.0);
    try std.testing.expect(price > 0.0);
}

test "tickToPrice - tick 1 should return approximately 1.0001" {
    const price = conversions.tickToPrice(1);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0001), price, 0.00001);
}

test "tickToPrice - tick -1 should return approximately 1/1.0001" {
    const price = conversions.tickToPrice(-1);
    const expected: f64 = 1.0 / 1.0001;
    try std.testing.expectApproxEqAbs(expected, price, 0.00001);
}

// =============================================================================
// sqrtPriceX96ToPrice
// =============================================================================

test "sqrtPriceX96ToPrice - Q96 should return approximately 1.0" {
    const result = try conversions.sqrtPriceX96ToPrice(constants.Q96);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result, 0.000001);
}

test "sqrtPriceX96ToPrice - 10 * Q96 should return approximately 100.0" {
    const result = try conversions.sqrtPriceX96ToPrice(constants.Q96 * 10);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), result, 0.01);
}

test "sqrtPriceX96ToPrice - Q96 / 2 should return approximately 0.25" {
    const result = try conversions.sqrtPriceX96ToPrice(constants.Q96 / 2);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), result, 0.001);
}

test "sqrtPriceX96ToPrice - 2 * Q96 should return approximately 4.0" {
    const result = try conversions.sqrtPriceX96ToPrice(constants.Q96 * 2);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), result, 0.001);
}

test "sqrtPriceX96ToPrice - 3 * Q96 should return approximately 9.0" {
    const result = try conversions.sqrtPriceX96ToPrice(constants.Q96 * 3);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0), result, 0.01);
}

// =============================================================================
// marginRatioToLeverage
// =============================================================================

test "marginRatioToLeverage - 100_000 (10%) should return 10.0x" {
    const result = try conversions.marginRatioToLeverage(100_000);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), result, 0.0001);
}

test "marginRatioToLeverage - 1_000_000 (100%) should return 1.0x" {
    // u32 fits 1_000_000 fine
    const result = try conversions.marginRatioToLeverage(1_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), result, 0.0001);
}

test "marginRatioToLeverage - 50_000 (5%) should return 20.0x" {
    const result = try conversions.marginRatioToLeverage(50_000);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), result, 0.0001);
}

test "marginRatioToLeverage - 200_000 (20%) should return 5.0x" {
    const result = try conversions.marginRatioToLeverage(200_000);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), result, 0.0001);
}

test "marginRatioToLeverage - 500_000 (50%) should return 2.0x" {
    const result = try conversions.marginRatioToLeverage(500_000);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), result, 0.0001);
}

test "marginRatioToLeverage - 0 returns MarginRatioMustBePositive" {
    try std.testing.expectError(error.MarginRatioMustBePositive, conversions.marginRatioToLeverage(0));
}

test "marginRatioToLeverage - 25_000 (2.5%) should return 40.0x" {
    const result = try conversions.marginRatioToLeverage(25_000);
    try std.testing.expectApproxEqAbs(@as(f64, 40.0), result, 0.0001);
}

// =============================================================================
// scaleFrom6Decimals
// =============================================================================

test "scaleFrom6Decimals - 100_000_000 should return 100.0" {
    const result = conversions.scaleFrom6Decimals(100_000_000);
    try std.testing.expectEqual(@as(f64, 100.0), result);
}

test "scaleFrom6Decimals - 1_000_000 should return 1.0" {
    const result = conversions.scaleFrom6Decimals(1_000_000);
    try std.testing.expectEqual(@as(f64, 1.0), result);
}

test "scaleFrom6Decimals - 0 should return 0.0" {
    const result = conversions.scaleFrom6Decimals(0);
    try std.testing.expectEqual(@as(f64, 0.0), result);
}

test "scaleFrom6Decimals - 500_000 should return 0.5" {
    const result = conversions.scaleFrom6Decimals(500_000);
    try std.testing.expectEqual(@as(f64, 0.5), result);
}

test "scaleFrom6Decimals - 1 should return 0.000001" {
    const result = conversions.scaleFrom6Decimals(1);
    try std.testing.expectApproxEqAbs(@as(f64, 0.000001), result, 1e-12);
}

test "scaleFrom6Decimals - negative value -2_000_000 should return -2.0" {
    const result = conversions.scaleFrom6Decimals(-2_000_000);
    try std.testing.expectEqual(@as(f64, -2.0), result);
}

test "scaleFrom6Decimals - 1_500_000 should return 1.5" {
    const result = conversions.scaleFrom6Decimals(1_500_000);
    try std.testing.expectEqual(@as(f64, 1.5), result);
}

// =============================================================================
// Round-trip tests
// =============================================================================

test "round-trip: price -> sqrtPriceX96 -> price should be close" {
    const original_price: f64 = 1500.0;
    const sqrt_price = try conversions.priceToSqrtPriceX96(original_price);
    const recovered_price = try conversions.sqrtPriceX96ToPrice(sqrt_price);
    try std.testing.expectApproxEqAbs(original_price, recovered_price, 0.01);
}

test "round-trip: price 0.01 -> sqrtPriceX96 -> price should be close" {
    const original_price: f64 = 0.01;
    const sqrt_price = try conversions.priceToSqrtPriceX96(original_price);
    const recovered_price = try conversions.sqrtPriceX96ToPrice(sqrt_price);
    try std.testing.expectApproxEqAbs(original_price, recovered_price, 0.0001);
}

test "round-trip: price 50000 -> sqrtPriceX96 -> price should be close" {
    const original_price: f64 = 50000.0;
    const sqrt_price = try conversions.priceToSqrtPriceX96(original_price);
    const recovered_price = try conversions.sqrtPriceX96ToPrice(sqrt_price);
    // Larger prices have slightly more absolute error but relative should be small
    const relative_error = @abs(recovered_price - original_price) / original_price;
    try std.testing.expect(relative_error < 0.0001);
}

test "round-trip: tick -> price -> tick should match within 1" {
    const original_tick: i32 = 5000;
    const price = conversions.tickToPrice(original_tick);
    const recovered_tick = try conversions.priceToTick(price, true);
    const diff = if (recovered_tick > original_tick)
        recovered_tick - original_tick
    else
        original_tick - recovered_tick;
    try std.testing.expect(diff <= 1);
}

test "round-trip: negative tick -> price -> tick should match within 1" {
    const original_tick: i32 = -3000;
    const price = conversions.tickToPrice(original_tick);
    const recovered_tick = try conversions.priceToTick(price, true);
    const diff = if (recovered_tick > original_tick)
        recovered_tick - original_tick
    else
        original_tick - recovered_tick;
    try std.testing.expect(diff <= 1);
}

test "round-trip: scale6Decimals -> scaleFrom6Decimals should be close" {
    const original: f64 = 123.456789;
    const scaled = try conversions.scale6Decimals(original);
    // scale6Decimals returns i128, scaleFrom6Decimals takes i64
    const recovered = conversions.scaleFrom6Decimals(@intCast(scaled));
    // floor truncation means we lose sub-microsecond precision
    try std.testing.expectApproxEqAbs(original, recovered, 0.000001);
}

test "round-trip: scaleToX96 -> scaleFromX96 should be close for integer" {
    const original: f64 = 42.0;
    const scaled = try conversions.scaleToX96(original);
    const recovered = try conversions.scaleFromX96(scaled);
    try std.testing.expectApproxEqAbs(original, recovered, 0.001);
}
