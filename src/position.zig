const std = @import("std");
const types = @import("types.zig");
const constants = @import("constants.zig");

/// Compute the absolute value of an i256, returned as u256.
fn absI256(x: i256) u256 {
    return if (x < 0) @intCast(-x) else @intCast(x);
}

/// Safely convert an i256 to f64. Since i256 may not directly convert, we
/// check if it fits in i128 first (which covers all practical position sizes).
fn i256ToF64(x: i256) f64 {
    if (x >= std.math.minInt(i128) and x <= std.math.maxInt(i128)) {
        const narrow: i128 = @intCast(x);
        return @floatFromInt(narrow);
    }
    // For extremely large values, convert via the absolute value as u128
    // and apply the sign manually.
    const abs_val = absI256(x);
    if (abs_val <= std.math.maxInt(u128)) {
        const narrow: u128 = @intCast(abs_val);
        const f: f64 = @floatFromInt(narrow);
        return if (x < 0) -f else f;
    }
    // Values beyond u128 range: use f64 infinity as a sentinel.
    return if (x < 0) -std.math.inf(f64) else std.math.inf(f64);
}

/// Calculate the entry price of a position.
/// entry_price = abs(entryUsdDelta) / abs(entryPerpDelta)
pub fn calculateEntryPrice(raw_data: types.PositionRawData) f64 {
    const abs_perp = absI256(raw_data.entry_perp_delta);
    if (abs_perp == 0) return 0.0;

    const abs_usd = absI256(raw_data.entry_usd_delta);

    // Both are scaled by 1e6, so the ratio gives us the price directly.
    const abs_usd_f: f64 = @floatFromInt(@as(u128, @intCast(abs_usd)));
    const abs_perp_f: f64 = @floatFromInt(@as(u128, @intCast(abs_perp)));

    return abs_usd_f / abs_perp_f;
}

/// Calculate the position size in base units (not scaled).
/// size = entryPerpDelta / 1e6
pub fn calculatePositionSize(raw_data: types.PositionRawData) f64 {
    const perp_f = i256ToF64(raw_data.entry_perp_delta);
    return perp_f / constants.F64_1E6;
}

/// Calculate the current position value at a given mark price.
/// value = abs(size) * mark_price
pub fn calculatePositionValue(raw_data: types.PositionRawData, mark_price: f64) f64 {
    const size = calculatePositionSize(raw_data);
    return @abs(size) * mark_price;
}

/// Calculate the leverage of a position.
/// leverage = position_value / effective_margin
/// Returns inf if effective_margin <= 0.
pub fn calculateLeverage(position_value: f64, effective_margin: f64) f64 {
    if (effective_margin <= 0.0) return std.math.inf(f64);
    return position_value / effective_margin;
}

/// Calculate the liquidation price of a position.
/// Returns null if size is zero or margin <= 0.
///
/// For long:  liq_price = entry_price - (margin - liq_ratio * notional) / size, clamped to 0
/// For short: liq_price = entry_price + (margin - liq_ratio * notional) / abs(size)
pub fn calculateLiquidationPrice(raw_data: types.PositionRawData, is_long: bool) ?f64 {
    const size = calculatePositionSize(raw_data);
    if (size == 0.0) return null;
    if (raw_data.margin <= 0.0) return null;

    const entry_price = calculateEntryPrice(raw_data);
    const abs_size = @abs(size);
    const notional = abs_size * entry_price;
    const liq_ratio = @as(f64, @floatFromInt(raw_data.margin_ratios.liq)) / constants.F64_1E6;

    const margin_excess = raw_data.margin - liq_ratio * notional;

    if (is_long) {
        const liq_price = entry_price - margin_excess / abs_size;
        return @max(liq_price, 0.0);
    } else {
        const liq_price = entry_price + margin_excess / abs_size;
        return liq_price;
    }
}

// -------------------------------------------------------------------------
// Accessor functions for OpenPositionData
// -------------------------------------------------------------------------

pub fn getPositionPerpId(pos: types.OpenPositionData) types.Bytes32 {
    return pos.perp_id;
}

pub fn getPositionId(pos: types.OpenPositionData) u256 {
    return pos.position_id;
}

pub fn getPositionIsLong(pos: types.OpenPositionData) ?bool {
    return pos.is_long;
}

pub fn getPositionIsMaker(pos: types.OpenPositionData) ?bool {
    return pos.is_maker;
}

pub fn getPositionLiveDetails(pos: types.OpenPositionData) types.LiveDetails {
    return pos.live_details;
}

pub fn getPositionPnl(pos: types.OpenPositionData) f64 {
    return pos.live_details.pnl;
}

pub fn getPositionFundingPayment(pos: types.OpenPositionData) f64 {
    return pos.live_details.funding_payment;
}

pub fn getPositionEffectiveMargin(pos: types.OpenPositionData) f64 {
    return pos.live_details.effective_margin;
}

pub fn getPositionIsLiquidatable(pos: types.OpenPositionData) bool {
    return pos.live_details.is_liquidatable;
}

// -------------------------------------------------------------------------
// Tests
// -------------------------------------------------------------------------

fn makeTestRawData(entry_perp_delta: i256, entry_usd_delta: i256, margin: f64) types.PositionRawData {
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

test "calculateEntryPrice basic" {
    // 1 ETH at 1500 USDC: perpDelta = 1e6, usdDelta = -1500e6
    const raw = makeTestRawData(1_000_000, -1_500_000_000, 100.0);
    const price = calculateEntryPrice(raw);
    try std.testing.expect(@abs(price - 1500.0) < 0.001);
}

test "calculateEntryPrice zero perp delta returns 0" {
    const raw = makeTestRawData(0, 0, 100.0);
    try std.testing.expectEqual(@as(f64, 0.0), calculateEntryPrice(raw));
}

test "calculatePositionSize basic" {
    const raw = makeTestRawData(2_500_000, -3_750_000_000, 100.0);
    const size = calculatePositionSize(raw);
    try std.testing.expect(@abs(size - 2.5) < 0.000001);
}

test "calculatePositionValue basic" {
    const raw = makeTestRawData(1_000_000, -1_500_000_000, 100.0);
    const value = calculatePositionValue(raw, 1600.0);
    try std.testing.expect(@abs(value - 1600.0) < 0.001);
}

test "calculateLeverage basic" {
    const lev = calculateLeverage(1000.0, 100.0);
    try std.testing.expect(@abs(lev - 10.0) < 0.001);
}

test "calculateLeverage with zero margin" {
    const lev = calculateLeverage(1000.0, 0.0);
    try std.testing.expect(std.math.isInf(lev));
}

test "calculateLiquidationPrice long" {
    // Long position: 1 ETH at $1500, $100 margin, 2.5% liq ratio
    const raw = makeTestRawData(1_000_000, -1_500_000_000, 100.0);
    const liq_price = calculateLiquidationPrice(raw, true);
    try std.testing.expect(liq_price != null);
    // liq_price = 1500 - (100 - 0.025 * 1500) / 1 = 1500 - (100 - 37.5) = 1500 - 62.5 = 1437.5
    try std.testing.expect(@abs(liq_price.? - 1437.5) < 0.01);
}

test "calculateLiquidationPrice short" {
    // Short position: -1 ETH at $1500, $100 margin, 2.5% liq ratio
    const raw = makeTestRawData(-1_000_000, 1_500_000_000, 100.0);
    const liq_price = calculateLiquidationPrice(raw, false);
    try std.testing.expect(liq_price != null);
    // liq_price = 1500 + (100 - 0.025 * 1500) / 1 = 1500 + 62.5 = 1562.5
    try std.testing.expect(@abs(liq_price.? - 1562.5) < 0.01);
}

test "calculateLiquidationPrice returns null for zero size" {
    const raw = makeTestRawData(0, 0, 100.0);
    try std.testing.expectEqual(@as(?f64, null), calculateLiquidationPrice(raw, true));
}

test "calculateLiquidationPrice returns null for non-positive margin" {
    const raw = makeTestRawData(1_000_000, -1_500_000_000, 0.0);
    try std.testing.expectEqual(@as(?f64, null), calculateLiquidationPrice(raw, true));
}

test "accessor functions" {
    const pos = types.OpenPositionData{
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

    try std.testing.expectEqual(@as(u256, 42), getPositionId(pos));
    try std.testing.expectEqual(@as(?bool, true), getPositionIsLong(pos));
    try std.testing.expectEqual(@as(?bool, false), getPositionIsMaker(pos));
    try std.testing.expectEqual(@as(f64, 50.0), getPositionPnl(pos));
    try std.testing.expectEqual(@as(f64, -2.5), getPositionFundingPayment(pos));
    try std.testing.expectEqual(@as(f64, 100.0), getPositionEffectiveMargin(pos));
    try std.testing.expectEqual(false, getPositionIsLiquidatable(pos));
}
