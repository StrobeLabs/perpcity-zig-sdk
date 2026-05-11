const std = @import("std");
const types = @import("types.zig");
const constants = @import("constants.zig");

// ---------------------------------------------------------------------------
// BalanceDelta packing
// ---------------------------------------------------------------------------
//
// Solidity `BalanceDelta` is a `int256` with `amount0` packed in the high 128
// bits and `amount1` packed in the low 128 bits. `Perp.positions()` returns
// the position's delta in this format -- the SDK unpacks it here so callers
// can read perp / usd balances directly.

pub const Delta = struct {
    /// currency0 amount (perp side).
    amount0: i128,
    /// currency1 amount (usd side).
    amount1: i128,
};

/// Unpack a `BalanceDelta` (Solidity int256 holding two packed int128s).
pub fn unpackDelta(packed_delta: i256) Delta {
    const u: u256 = @bitCast(packed_delta);
    const high: u128 = @intCast(u >> 128);
    const low: u128 = @intCast(u & std.math.maxInt(u128));
    return .{
        .amount0 = @bitCast(high),
        .amount1 = @bitCast(low),
    };
}

/// Pack two int128s into a single `BalanceDelta` int256.
pub fn packDelta(amount0: i128, amount1: i128) i256 {
    const a: u128 = @bitCast(amount0);
    const b: u128 = @bitCast(amount1);
    const u: u256 = (@as(u256, a) << 128) | @as(u256, b);
    return @bitCast(u);
}

// ---------------------------------------------------------------------------
// Position helpers
// ---------------------------------------------------------------------------

/// Returns the perp-side balance of a position (currency0 amount).
pub fn perpDelta(raw: types.PositionRawData) i128 {
    return unpackDelta(raw.delta).amount0;
}

/// Returns the USD-side balance of a position (currency1 amount).
pub fn usdDelta(raw: types.PositionRawData) i128 {
    return unpackDelta(raw.delta).amount1;
}

/// Returns the position size (perp delta) in human units (1e6-scaled to float).
pub fn positionSize(raw: types.PositionRawData) f64 {
    const pd = perpDelta(raw);
    return @as(f64, @floatFromInt(pd)) / constants.F64_1E6;
}

/// Returns the position margin in human units.
pub fn marginHuman(raw: types.PositionRawData) f64 {
    return @as(f64, @floatFromInt(raw.margin)) / constants.F64_1E6;
}

/// Position value at a given mark price: |size| * mark.
pub fn positionValue(raw: types.PositionRawData, mark_price: f64) f64 {
    return @abs(positionSize(raw)) * mark_price;
}

/// Notional leverage at the supplied mark: value / margin. Returns +inf for
/// zero margin (matches the v0.0.1 helper's behavior).
pub fn currentLeverage(raw: types.PositionRawData, mark_price: f64) f64 {
    const m = marginHuman(raw);
    if (m <= 0.0) return std.math.inf(f64);
    return positionValue(raw, mark_price) / m;
}

// ---------------------------------------------------------------------------
// Accessors for OpenPositionData
// ---------------------------------------------------------------------------

pub fn getPositionPerp(pos: types.OpenPositionData) types.Address {
    return pos.perp;
}

pub fn getPositionId(pos: types.OpenPositionData) u256 {
    return pos.position_id;
}

pub fn getPositionIsMaker(pos: types.OpenPositionData) bool {
    return pos.is_maker;
}

pub fn getPositionLiveDetails(pos: types.OpenPositionData) types.LiveDetails {
    return pos.live_details;
}

pub fn getPositionMargin(pos: types.OpenPositionData) f64 {
    return pos.live_details.margin;
}

pub fn getPositionPerpDelta(pos: types.OpenPositionData) i256 {
    return pos.live_details.perp_delta;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "unpackDelta zero" {
    const d = unpackDelta(0);
    try std.testing.expectEqual(@as(i128, 0), d.amount0);
    try std.testing.expectEqual(@as(i128, 0), d.amount1);
}

test "packDelta then unpackDelta roundtrip" {
    const cases = [_]struct { a0: i128, a1: i128 }{
        .{ .a0 = 0, .a1 = 0 },
        .{ .a0 = 1, .a1 = -1 },
        .{ .a0 = 12345, .a1 = -67890 },
        .{ .a0 = std.math.maxInt(i128), .a1 = std.math.minInt(i128) },
        .{ .a0 = std.math.minInt(i128), .a1 = std.math.maxInt(i128) },
    };
    for (cases) |c| {
        const packed_v = packDelta(c.a0, c.a1);
        const d = unpackDelta(packed_v);
        try std.testing.expectEqual(c.a0, d.amount0);
        try std.testing.expectEqual(c.a1, d.amount1);
    }
}

fn makeRaw(perp_amt: i128, usd_amt: i128, margin: u128) types.PositionRawData {
    return .{
        .perp = types.ZERO_ADDRESS,
        .position_id = 1,
        .delta = packDelta(perp_amt, usd_amt),
        .margin = margin,
        .liq_margin_ratio = 50_000,
        .backstop_margin_ratio = 20_000,
        .last_cuml_funding_x96 = 0,
    };
}

test "positionSize converts perp delta into human units" {
    const raw = makeRaw(2_500_000, -3_750_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), positionSize(raw), 0.0000001);
}

test "positionValue at mark" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 1600.0), positionValue(raw, 1600.0), 0.0001);
}

test "currentLeverage with positive margin" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000); // margin 100 USDC
    const lev = currentLeverage(raw, 1500.0);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), lev, 0.0001);
}

test "currentLeverage with zero margin is inf" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 0);
    try std.testing.expect(std.math.isInf(currentLeverage(raw, 1500.0)));
}

test "OpenPositionData accessors" {
    const pos = types.OpenPositionData{
        .perp = types.ZERO_ADDRESS,
        .position_id = 42,
        .is_maker = false,
        .live_details = .{
            .margin = 100.0,
            .perp_delta = 1_500_000,
            .liq_margin_ratio = 50_000,
            .backstop_margin_ratio = 20_000,
        },
    };
    try std.testing.expectEqual(@as(u256, 42), getPositionId(pos));
    try std.testing.expectEqual(false, getPositionIsMaker(pos));
    try std.testing.expectEqual(@as(f64, 100.0), getPositionMargin(pos));
    try std.testing.expectEqual(@as(i256, 1_500_000), getPositionPerpDelta(pos));
}
