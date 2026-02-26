const std = @import("std");
const sdk = @import("perpcity_sdk");
const position = sdk.position;
const types = sdk.types;

// =============================================================================
// Test helpers
// =============================================================================

fn makeLongPosition(entry_perp_delta: i256, entry_usd_delta: i256, margin: f64) types.PositionRawData {
    return .{
        .perp_id = types.ZERO_BYTES32,
        .position_id = 1,
        .margin = margin,
        .entry_perp_delta = entry_perp_delta,
        .entry_usd_delta = entry_usd_delta,
        .margin_ratios = .{
            .min = 50_000, // 5%
            .max = 1_000_000, // 100%
            .liq = 25_000, // 2.5%
        },
    };
}

fn makeShortPosition(entry_perp_delta: i256, entry_usd_delta: i256, margin: f64) types.PositionRawData {
    return .{
        .perp_id = types.ZERO_BYTES32,
        .position_id = 2,
        .margin = margin,
        .entry_perp_delta = entry_perp_delta,
        .entry_usd_delta = entry_usd_delta,
        .margin_ratios = .{
            .min = 50_000,
            .max = 1_000_000,
            .liq = 25_000,
        },
    };
}

fn makeZeroPosition() types.PositionRawData {
    return .{
        .perp_id = types.ZERO_BYTES32,
        .position_id = 3,
        .margin = 100.0,
        .entry_perp_delta = 0,
        .entry_usd_delta = 0,
        .margin_ratios = .{
            .min = 50_000,
            .max = 1_000_000,
            .liq = 25_000,
        },
    };
}

// Standard test positions:
// Long: 200 units at price 1.0 (entry_perp_delta=200e6, entry_usd_delta=-200e6)
// Short: -200 units at price 1.0 (entry_perp_delta=-200e6, entry_usd_delta=200e6)

// =============================================================================
// calculateEntryPrice
// =============================================================================

test "calculateEntryPrice - long position 200 units at price 1.0" {
    const raw = makeLongPosition(200_000_000, -200_000_000, 100.0);
    const price = position.calculateEntryPrice(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), price, 0.000001);
}

test "calculateEntryPrice - short position 200 units at price 1.0" {
    const raw = makeShortPosition(-200_000_000, 200_000_000, 100.0);
    const price = position.calculateEntryPrice(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), price, 0.000001);
}

test "calculateEntryPrice - 1 ETH at 1500 USDC" {
    const raw = makeLongPosition(1_000_000, -1_500_000_000, 100.0);
    const price = position.calculateEntryPrice(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 1500.0), price, 0.001);
}

test "calculateEntryPrice - 10 ETH at 2000 USDC" {
    const raw = makeLongPosition(10_000_000, -20_000_000_000, 1000.0);
    const price = position.calculateEntryPrice(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 2000.0), price, 0.001);
}

test "calculateEntryPrice - zero perp delta returns 0.0" {
    const raw = makeZeroPosition();
    const price = position.calculateEntryPrice(raw);
    try std.testing.expectEqual(@as(f64, 0.0), price);
}

test "calculateEntryPrice - entry price is independent of margin" {
    const raw_a = makeLongPosition(1_000_000, -1_500_000_000, 50.0);
    const raw_b = makeLongPosition(1_000_000, -1_500_000_000, 500.0);
    const price_a = position.calculateEntryPrice(raw_a);
    const price_b = position.calculateEntryPrice(raw_b);
    try std.testing.expectEqual(price_a, price_b);
}

test "calculateEntryPrice - fractional price 0.5" {
    // 2 units, 1 USD total => price = 0.5
    const raw = makeLongPosition(2_000_000, -1_000_000, 10.0);
    const price = position.calculateEntryPrice(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), price, 0.000001);
}

// =============================================================================
// calculatePositionSize
// =============================================================================

test "calculatePositionSize - long 200 units" {
    const raw = makeLongPosition(200_000_000, -200_000_000, 100.0);
    const size = position.calculatePositionSize(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), size, 0.000001);
}

test "calculatePositionSize - short 200 units (negative)" {
    const raw = makeShortPosition(-200_000_000, 200_000_000, 100.0);
    const size = position.calculatePositionSize(raw);
    try std.testing.expectApproxEqAbs(@as(f64, -200.0), size, 0.000001);
}

test "calculatePositionSize - zero position" {
    const raw = makeZeroPosition();
    const size = position.calculatePositionSize(raw);
    try std.testing.expectEqual(@as(f64, 0.0), size);
}

test "calculatePositionSize - 2.5 units" {
    const raw = makeLongPosition(2_500_000, -3_750_000_000, 100.0);
    const size = position.calculatePositionSize(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), size, 0.000001);
}

test "calculatePositionSize - 0.001 units (tiny position)" {
    const raw = makeLongPosition(1_000, -1_500, 10.0);
    const size = position.calculatePositionSize(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 0.001), size, 0.000001);
}

test "calculatePositionSize - 1_000_000 units (large position)" {
    const raw = makeLongPosition(1_000_000_000_000, -1_500_000_000_000_000, 10000.0);
    const size = position.calculatePositionSize(raw);
    try std.testing.expectApproxEqAbs(@as(f64, 1_000_000.0), size, 0.001);
}

// =============================================================================
// calculatePositionValue
// =============================================================================

test "calculatePositionValue - long position at mark price" {
    const raw = makeLongPosition(200_000_000, -200_000_000, 100.0);
    const value = position.calculatePositionValue(raw, 1.0);
    // abs(200) * 1.0 = 200.0
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), value, 0.001);
}

test "calculatePositionValue - long position at higher mark price" {
    const raw = makeLongPosition(200_000_000, -200_000_000, 100.0);
    const value = position.calculatePositionValue(raw, 2.0);
    // abs(200) * 2.0 = 400.0
    try std.testing.expectApproxEqAbs(@as(f64, 400.0), value, 0.001);
}

test "calculatePositionValue - short position at mark price" {
    const raw = makeShortPosition(-200_000_000, 200_000_000, 100.0);
    const value = position.calculatePositionValue(raw, 1.0);
    // abs(-200) * 1.0 = 200.0
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), value, 0.001);
}

test "calculatePositionValue - zero position at any mark price" {
    const raw = makeZeroPosition();
    const value = position.calculatePositionValue(raw, 1500.0);
    try std.testing.expectEqual(@as(f64, 0.0), value);
}

test "calculatePositionValue - 1 ETH at mark 1600" {
    const raw = makeLongPosition(1_000_000, -1_500_000_000, 100.0);
    const value = position.calculatePositionValue(raw, 1600.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1600.0), value, 0.001);
}

test "calculatePositionValue - value is always positive regardless of direction" {
    const long_raw = makeLongPosition(100_000_000, -100_000_000, 50.0);
    const short_raw = makeShortPosition(-100_000_000, 100_000_000, 50.0);
    const long_val = position.calculatePositionValue(long_raw, 10.0);
    const short_val = position.calculatePositionValue(short_raw, 10.0);
    try std.testing.expect(long_val > 0);
    try std.testing.expect(short_val > 0);
    try std.testing.expectApproxEqAbs(long_val, short_val, 0.001);
}

// =============================================================================
// calculateLeverage
// =============================================================================

test "calculateLeverage - 1000 value with 100 margin gives 10x" {
    const lev = position.calculateLeverage(1000.0, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 10.0), lev, 0.001);
}

test "calculateLeverage - equal value and margin gives 1x" {
    const lev = position.calculateLeverage(100.0, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), lev, 0.001);
}

test "calculateLeverage - 500 value with 100 margin gives 5x" {
    const lev = position.calculateLeverage(500.0, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0), lev, 0.001);
}

test "calculateLeverage - zero margin gives infinity" {
    const lev = position.calculateLeverage(1000.0, 0.0);
    try std.testing.expect(std.math.isInf(lev));
}

test "calculateLeverage - negative margin gives infinity" {
    const lev = position.calculateLeverage(1000.0, -10.0);
    try std.testing.expect(std.math.isInf(lev));
}

test "calculateLeverage - zero value with positive margin gives 0" {
    const lev = position.calculateLeverage(0.0, 100.0);
    try std.testing.expectEqual(@as(f64, 0.0), lev);
}

test "calculateLeverage - very small margin gives very high leverage" {
    const lev = position.calculateLeverage(10000.0, 0.01);
    try std.testing.expect(lev > 100_000.0);
}

test "calculateLeverage - 20x leverage" {
    const lev = position.calculateLeverage(2000.0, 100.0);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), lev, 0.001);
}

// =============================================================================
// calculateLiquidationPrice
// =============================================================================

test "calculateLiquidationPrice - long position should return price below entry" {
    // Long: 1 ETH at $1500, $100 margin, 2.5% liq ratio
    const raw = makeLongPosition(1_000_000, -1_500_000_000, 100.0);
    const liq_price = position.calculateLiquidationPrice(raw, true);
    try std.testing.expect(liq_price != null);
    const entry_price = position.calculateEntryPrice(raw);
    try std.testing.expect(liq_price.? < entry_price);
}

test "calculateLiquidationPrice - long position exact value" {
    // Long: 1 ETH at $1500, $100 margin, 2.5% liq ratio
    // liq_price = 1500 - (100 - 0.025 * 1500) / 1 = 1500 - 62.5 = 1437.5
    const raw = makeLongPosition(1_000_000, -1_500_000_000, 100.0);
    const liq_price = position.calculateLiquidationPrice(raw, true);
    try std.testing.expect(liq_price != null);
    try std.testing.expectApproxEqAbs(@as(f64, 1437.5), liq_price.?, 0.01);
}

test "calculateLiquidationPrice - short position should return price above entry" {
    // Short: -1 ETH at $1500, $100 margin, 2.5% liq ratio
    const raw = makeShortPosition(-1_000_000, 1_500_000_000, 100.0);
    const liq_price = position.calculateLiquidationPrice(raw, false);
    try std.testing.expect(liq_price != null);
    const entry_price = position.calculateEntryPrice(raw);
    try std.testing.expect(liq_price.? > entry_price);
}

test "calculateLiquidationPrice - short position exact value" {
    // Short: -1 ETH at $1500, $100 margin, 2.5% liq ratio
    // liq_price = 1500 + (100 - 0.025 * 1500) / 1 = 1500 + 62.5 = 1562.5
    const raw = makeShortPosition(-1_000_000, 1_500_000_000, 100.0);
    const liq_price = position.calculateLiquidationPrice(raw, false);
    try std.testing.expect(liq_price != null);
    try std.testing.expectApproxEqAbs(@as(f64, 1562.5), liq_price.?, 0.01);
}

test "calculateLiquidationPrice - zero size position returns null" {
    const raw = makeZeroPosition();
    try std.testing.expectEqual(@as(?f64, null), position.calculateLiquidationPrice(raw, true));
    try std.testing.expectEqual(@as(?f64, null), position.calculateLiquidationPrice(raw, false));
}

test "calculateLiquidationPrice - zero margin position returns null" {
    const raw = makeLongPosition(1_000_000, -1_500_000_000, 0.0);
    try std.testing.expectEqual(@as(?f64, null), position.calculateLiquidationPrice(raw, true));
}

test "calculateLiquidationPrice - negative margin position returns null" {
    const raw = makeLongPosition(1_000_000, -1_500_000_000, -10.0);
    try std.testing.expectEqual(@as(?f64, null), position.calculateLiquidationPrice(raw, true));
}

test "calculateLiquidationPrice - long liq price is clamped to 0 minimum" {
    // Very small margin relative to position: margin < liq_ratio * notional
    // => margin_excess < 0 => liq_price > entry_price, but for long it's
    //    entry_price - negative_excess = entry_price + positive => still > 0
    // Actually let's test with very large position and tiny margin
    // 100 ETH at $1000, $1 margin, 2.5% liq ratio
    // liq_price = 1000 - (1 - 0.025*100000) / 100 = 1000 - (1-2500)/100 = 1000 + 24.99 = 1024.99
    // That's above entry price, so clamp check doesn't apply here.
    // For a case that clamps to zero: impossible under normal circumstances since
    // liq_price = entry - something. If something > entry, it would clamp.
    // 1 unit at $1, $100 margin => liq_price = 1 - (100 - 0.025*1)/1 = 1 - 99.975 = -98.975 => clamped to 0
    const raw = makeLongPosition(1_000_000, -1_000_000, 100.0);
    const liq_price = position.calculateLiquidationPrice(raw, true);
    try std.testing.expect(liq_price != null);
    try std.testing.expectEqual(@as(f64, 0.0), liq_price.?);
}

test "calculateLiquidationPrice - more margin pushes long liq price further below entry" {
    const raw_small = makeLongPosition(1_000_000, -1_500_000_000, 50.0);
    const raw_large = makeLongPosition(1_000_000, -1_500_000_000, 200.0);
    const liq_small = position.calculateLiquidationPrice(raw_small, true);
    const liq_large = position.calculateLiquidationPrice(raw_large, true);
    try std.testing.expect(liq_small != null);
    try std.testing.expect(liq_large != null);
    // More margin means further from liquidation => lower liq price for long
    try std.testing.expect(liq_large.? < liq_small.?);
}

test "calculateLiquidationPrice - more margin pushes short liq price further above entry" {
    const raw_small = makeShortPosition(-1_000_000, 1_500_000_000, 50.0);
    const raw_large = makeShortPosition(-1_000_000, 1_500_000_000, 200.0);
    const liq_small = position.calculateLiquidationPrice(raw_small, false);
    const liq_large = position.calculateLiquidationPrice(raw_large, false);
    try std.testing.expect(liq_small != null);
    try std.testing.expect(liq_large != null);
    // More margin means further from liquidation => higher liq price for short
    try std.testing.expect(liq_large.? > liq_small.?);
}

// =============================================================================
// Accessor functions for OpenPositionData
// =============================================================================

fn makeTestOpenPosition() types.OpenPositionData {
    return .{
        .perp_id = types.ZERO_BYTES32,
        .position_id = 42,
        .is_long = true,
        .is_maker = false,
        .live_details = .{
            .pnl = 50.0,
            .funding_payment = -2.5,
            .effective_margin = 100.0,
            .is_liquidatable = false,
        },
    };
}

test "getPositionId returns correct id" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(@as(u256, 42), position.getPositionId(pos));
}

test "getPositionIsLong returns correct value" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(@as(?bool, true), position.getPositionIsLong(pos));
}

test "getPositionIsLong returns null when not set" {
    var pos = makeTestOpenPosition();
    pos.is_long = null;
    try std.testing.expectEqual(@as(?bool, null), position.getPositionIsLong(pos));
}

test "getPositionIsMaker returns correct value" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(@as(?bool, false), position.getPositionIsMaker(pos));
}

test "getPositionIsMaker returns null when not set" {
    var pos = makeTestOpenPosition();
    pos.is_maker = null;
    try std.testing.expectEqual(@as(?bool, null), position.getPositionIsMaker(pos));
}

test "getPositionPnl returns correct pnl" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(@as(f64, 50.0), position.getPositionPnl(pos));
}

test "getPositionFundingPayment returns correct funding" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(@as(f64, -2.5), position.getPositionFundingPayment(pos));
}

test "getPositionEffectiveMargin returns correct margin" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(@as(f64, 100.0), position.getPositionEffectiveMargin(pos));
}

test "getPositionIsLiquidatable returns correct value" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(false, position.getPositionIsLiquidatable(pos));
}

test "getPositionLiveDetails returns full struct" {
    const pos = makeTestOpenPosition();
    const details = position.getPositionLiveDetails(pos);
    try std.testing.expectEqual(@as(f64, 50.0), details.pnl);
    try std.testing.expectEqual(@as(f64, -2.5), details.funding_payment);
    try std.testing.expectEqual(@as(f64, 100.0), details.effective_margin);
    try std.testing.expectEqual(false, details.is_liquidatable);
}

test "getPositionPerpId returns correct perp id" {
    const pos = makeTestOpenPosition();
    try std.testing.expectEqual(types.ZERO_BYTES32, position.getPositionPerpId(pos));
}
