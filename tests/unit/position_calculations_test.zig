const std = @import("std");
const sdk = @import("perpcity_sdk");
const position = sdk.position;
const types = sdk.types;

fn makeRaw(perp_amt: i128, usd_amt: i128, margin: u128) types.PositionRawData {
    return .{
        .perp = types.ZERO_ADDRESS,
        .position_id = 1,
        .delta = position.packDelta(perp_amt, usd_amt),
        .margin = margin,
        .liq_margin_ratio = 50_000,
        .backstop_margin_ratio = 20_000,
        .last_cuml_funding_x96 = 0,
    };
}

// =============================================================================
// BalanceDelta pack/unpack
// =============================================================================

test "unpackDelta zero" {
    const d = position.unpackDelta(0);
    try std.testing.expectEqual(@as(i128, 0), d.amount0);
    try std.testing.expectEqual(@as(i128, 0), d.amount1);
}

test "packDelta/unpackDelta roundtrip" {
    const cases = [_]struct { a0: i128, a1: i128 }{
        .{ .a0 = 0, .a1 = 0 },
        .{ .a0 = 1, .a1 = -1 },
        .{ .a0 = 12_345, .a1 = -67_890 },
        .{ .a0 = std.math.maxInt(i128), .a1 = std.math.minInt(i128) },
        .{ .a0 = std.math.minInt(i128), .a1 = std.math.maxInt(i128) },
    };
    for (cases) |c| {
        const packed_v = position.packDelta(c.a0, c.a1);
        const d = position.unpackDelta(packed_v);
        try std.testing.expectEqual(c.a0, d.amount0);
        try std.testing.expectEqual(c.a1, d.amount1);
    }
}

// =============================================================================
// perpDelta / usdDelta
// =============================================================================

test "perpDelta returns amount0 (currency0 = perp)" {
    const raw = makeRaw(1_234_567, -987_654, 100_000_000);
    try std.testing.expectEqual(@as(i128, 1_234_567), position.perpDelta(raw));
}

test "usdDelta returns amount1 (currency1 = usd)" {
    const raw = makeRaw(1_234_567, -987_654, 100_000_000);
    try std.testing.expectEqual(@as(i128, -987_654), position.usdDelta(raw));
}

// =============================================================================
// positionSize
// =============================================================================

test "positionSize - 2.5 units long" {
    const raw = makeRaw(2_500_000, -3_750_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5), position.positionSize(raw), 0.0000001);
}

test "positionSize - short positions are negative" {
    const raw = makeRaw(-1_000_000, 1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, -1.0), position.positionSize(raw), 0.0000001);
}

test "positionSize - zero delta returns 0" {
    const raw = makeRaw(0, 0, 100_000_000);
    try std.testing.expectEqual(@as(f64, 0.0), position.positionSize(raw));
}

// =============================================================================
// positionValue
// =============================================================================

test "positionValue at mark" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 1600.0), position.positionValue(raw, 1600.0), 0.0001);
}

test "positionValue uses absolute size (short)" {
    const raw = makeRaw(-1_000_000, 1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 1600.0), position.positionValue(raw, 1600.0), 0.0001);
}

test "positionValue is zero for empty position" {
    const raw = makeRaw(0, 0, 100_000_000);
    try std.testing.expectEqual(@as(f64, 0.0), position.positionValue(raw, 1600.0));
}

// =============================================================================
// currentLeverage
// =============================================================================

test "currentLeverage with positive margin" {
    // 1 unit * 1500 mark = 1500 USD value; 100 USD margin -> 15x leverage
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 15.0), position.currentLeverage(raw, 1500.0), 0.0001);
}

test "currentLeverage with zero margin is inf" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 0);
    try std.testing.expect(std.math.isInf(position.currentLeverage(raw, 1500.0)));
}

test "currentLeverage is zero for empty position" {
    const raw = makeRaw(0, 0, 100_000_000);
    try std.testing.expectEqual(@as(f64, 0.0), position.currentLeverage(raw, 1500.0));
}

// =============================================================================
// marginHuman
// =============================================================================

test "marginHuman converts 1e6-scaled margin to USDC" {
    const raw = makeRaw(0, 0, 100_000_000); // 100 USDC
    try std.testing.expectEqual(@as(f64, 100.0), position.marginHuman(raw));
}

// =============================================================================
// entryPrice
// =============================================================================

test "entryPrice - |usd| / |perp|" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 1500.0), position.entryPrice(raw), 0.0001);
}

test "entryPrice - short position uses absolute values" {
    const raw = makeRaw(-1_000_000, 1_500_000_000, 100_000_000);
    try std.testing.expectApproxEqAbs(@as(f64, 1500.0), position.entryPrice(raw), 0.0001);
}

test "entryPrice - zero perp delta returns 0" {
    const raw = makeRaw(0, 0, 100_000_000);
    try std.testing.expectEqual(@as(f64, 0.0), position.entryPrice(raw));
}

// =============================================================================
// liquidationPrice
//
// size 1.0, entry 1500, margin 100 USDC, liq ratio 0.05.
// long:  (1500 - 100)/(1 - 0.05) = 1400/0.95 = 1473.6842
// short: (1500 + 100)/(1 + 0.05) = 1600/1.05 = 1523.8095
// =============================================================================

test "liquidationPrice - long liquidates below entry" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    const lp = position.liquidationPrice(raw, true, null).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1473.6842), lp, 0.001);
}

test "liquidationPrice - short liquidates above entry" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    const lp = position.liquidationPrice(raw, false, null).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1523.8095), lp, 0.001);
}

test "liquidationPrice - effective margin override" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 100_000_000);
    // effective margin 50: long (1500 - 50)/0.95 = 1526.3158; short (1500 + 50)/1.05 = 1476.1905
    try std.testing.expectApproxEqAbs(@as(f64, 1526.3158), position.liquidationPrice(raw, true, 50.0).?, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1476.1905), position.liquidationPrice(raw, false, 50.0).?, 0.001);
}

test "liquidationPrice - long price is clamped to zero" {
    // 10k USDC margin pushes the long liquidation price below zero
    const raw = makeRaw(1_000_000, -1_500_000_000, 10_000_000_000);
    try std.testing.expectEqual(@as(f64, 0.0), position.liquidationPrice(raw, true, null).?);
}

test "liquidationPrice - null when the position has no size" {
    const raw = makeRaw(0, 0, 100_000_000);
    try std.testing.expectEqual(@as(?f64, null), position.liquidationPrice(raw, true, null));
}

test "liquidationPrice - null when margin is non-positive" {
    const raw = makeRaw(1_000_000, -1_500_000_000, 0);
    try std.testing.expectEqual(@as(?f64, null), position.liquidationPrice(raw, true, null));
}

// =============================================================================
// pnlPercentage
// =============================================================================

test "pnlPercentage - profit relative to initial margin" {
    // pnl 10 + funding 2 = 12; initial margin = 100 - 12 = 88; 12/88*100
    try std.testing.expectApproxEqAbs(@as(f64, 13.636363), position.pnlPercentage(10.0, 2.0, 100.0), 0.0001);
}

test "pnlPercentage - loss is negative" {
    // pnl -10; initial margin = 100 - (-10) = 110; -10/110*100
    try std.testing.expectApproxEqAbs(@as(f64, -9.090909), position.pnlPercentage(-10.0, 0.0, 100.0), 0.0001);
}

test "pnlPercentage - non-positive initial margin returns 0" {
    try std.testing.expectEqual(@as(f64, 0.0), position.pnlPercentage(200.0, 0.0, 100.0));
}
