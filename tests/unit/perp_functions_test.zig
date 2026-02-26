const std = @import("std");
const sdk = @import("perpcity_sdk");
const perp = sdk.perp;
const types = sdk.types;

// =============================================================================
// Test helpers
// =============================================================================

fn makeTestPerpData() types.PerpData {
    return .{
        .id = types.ZERO_BYTES32,
        .tick_spacing = 60,
        .mark = 1500.0,
        .beacon = types.ZERO_ADDRESS,
        .bounds = .{
            .min_margin = 10.0,
            .min_taker_leverage = 1.0,
            .max_taker_leverage = 50.0,
            .liquidation_taker_ratio = 0.05,
        },
        .fees = .{
            .creator_fee = 0.001,
            .insurance_fee = 0.001,
            .lp_fee = 0.003,
            .liquidation_fee = 0.01,
        },
    };
}

fn makeCustomPerpData(mark: f64, tick_spacing: i24) types.PerpData {
    return .{
        .id = types.ZERO_BYTES32,
        .tick_spacing = tick_spacing,
        .mark = mark,
        .beacon = types.ZERO_ADDRESS,
        .bounds = .{
            .min_margin = 5.0,
            .min_taker_leverage = 2.0,
            .max_taker_leverage = 100.0,
            .liquidation_taker_ratio = 0.02,
        },
        .fees = .{
            .creator_fee = 0.0005,
            .insurance_fee = 0.0005,
            .lp_fee = 0.001,
            .liquidation_fee = 0.005,
        },
    };
}

// =============================================================================
// getPerpMark
// =============================================================================

test "getPerpMark - returns correct mark price 1500.0" {
    const p = makeTestPerpData();
    try std.testing.expectEqual(@as(f64, 1500.0), perp.getPerpMark(p));
}

test "getPerpMark - returns mark of 0.0 when set to 0" {
    var p = makeTestPerpData();
    p.mark = 0.0;
    try std.testing.expectEqual(@as(f64, 0.0), perp.getPerpMark(p));
}

test "getPerpMark - returns large mark price" {
    const p = makeCustomPerpData(50000.0, 1);
    try std.testing.expectEqual(@as(f64, 50000.0), perp.getPerpMark(p));
}

test "getPerpMark - returns fractional mark price" {
    const p = makeCustomPerpData(0.001, 10);
    try std.testing.expectEqual(@as(f64, 0.001), perp.getPerpMark(p));
}

test "getPerpMark - different perps return different marks" {
    const p1 = makeCustomPerpData(100.0, 60);
    const p2 = makeCustomPerpData(200.0, 60);
    try std.testing.expect(perp.getPerpMark(p1) != perp.getPerpMark(p2));
}

// =============================================================================
// getPerpBeacon
// =============================================================================

test "getPerpBeacon - returns correct beacon address" {
    const p = makeTestPerpData();
    try std.testing.expectEqual(types.ZERO_ADDRESS, perp.getPerpBeacon(p));
}

test "getPerpBeacon - returns custom beacon address" {
    var p = makeTestPerpData();
    var custom_beacon: types.Address = [_]u8{0} ** 20;
    custom_beacon[0] = 0xAB;
    custom_beacon[19] = 0xCD;
    p.beacon = custom_beacon;
    try std.testing.expectEqual(custom_beacon, perp.getPerpBeacon(p));
}

// =============================================================================
// getPerpBounds
// =============================================================================

test "getPerpBounds - returns correct bounds struct" {
    const p = makeTestPerpData();
    const bounds = perp.getPerpBounds(p);
    try std.testing.expectEqual(@as(f64, 10.0), bounds.min_margin);
    try std.testing.expectEqual(@as(f64, 1.0), bounds.min_taker_leverage);
    try std.testing.expectEqual(@as(f64, 50.0), bounds.max_taker_leverage);
    try std.testing.expectEqual(@as(f64, 0.05), bounds.liquidation_taker_ratio);
}

test "getPerpBounds - returns custom bounds" {
    const p = makeCustomPerpData(100.0, 60);
    const bounds = perp.getPerpBounds(p);
    try std.testing.expectEqual(@as(f64, 5.0), bounds.min_margin);
    try std.testing.expectEqual(@as(f64, 2.0), bounds.min_taker_leverage);
    try std.testing.expectEqual(@as(f64, 100.0), bounds.max_taker_leverage);
    try std.testing.expectEqual(@as(f64, 0.02), bounds.liquidation_taker_ratio);
}

test "getPerpBounds - min_margin is accessible" {
    const p = makeTestPerpData();
    try std.testing.expect(perp.getPerpBounds(p).min_margin > 0);
}

test "getPerpBounds - max_taker_leverage is greater than min_taker_leverage" {
    const p = makeTestPerpData();
    const bounds = perp.getPerpBounds(p);
    try std.testing.expect(bounds.max_taker_leverage > bounds.min_taker_leverage);
}

// =============================================================================
// getPerpFees
// =============================================================================

test "getPerpFees - returns correct fees struct" {
    const p = makeTestPerpData();
    const fees = perp.getPerpFees(p);
    try std.testing.expectEqual(@as(f64, 0.001), fees.creator_fee);
    try std.testing.expectEqual(@as(f64, 0.001), fees.insurance_fee);
    try std.testing.expectEqual(@as(f64, 0.003), fees.lp_fee);
    try std.testing.expectEqual(@as(f64, 0.01), fees.liquidation_fee);
}

test "getPerpFees - returns custom fees" {
    const p = makeCustomPerpData(100.0, 60);
    const fees = perp.getPerpFees(p);
    try std.testing.expectEqual(@as(f64, 0.0005), fees.creator_fee);
    try std.testing.expectEqual(@as(f64, 0.0005), fees.insurance_fee);
    try std.testing.expectEqual(@as(f64, 0.001), fees.lp_fee);
    try std.testing.expectEqual(@as(f64, 0.005), fees.liquidation_fee);
}

test "getPerpFees - all fees are non-negative" {
    const p = makeTestPerpData();
    const fees = perp.getPerpFees(p);
    try std.testing.expect(fees.creator_fee >= 0.0);
    try std.testing.expect(fees.insurance_fee >= 0.0);
    try std.testing.expect(fees.lp_fee >= 0.0);
    try std.testing.expect(fees.liquidation_fee >= 0.0);
}

test "getPerpFees - liquidation fee is largest" {
    const p = makeTestPerpData();
    const fees = perp.getPerpFees(p);
    try std.testing.expect(fees.liquidation_fee >= fees.creator_fee);
    try std.testing.expect(fees.liquidation_fee >= fees.insurance_fee);
    try std.testing.expect(fees.liquidation_fee >= fees.lp_fee);
}

// =============================================================================
// getPerpTickSpacing
// =============================================================================

test "getPerpTickSpacing - returns correct tick spacing 60" {
    const p = makeTestPerpData();
    try std.testing.expectEqual(@as(i24, 60), perp.getPerpTickSpacing(p));
}

test "getPerpTickSpacing - returns tick spacing 1" {
    const p = makeCustomPerpData(100.0, 1);
    try std.testing.expectEqual(@as(i24, 1), perp.getPerpTickSpacing(p));
}

test "getPerpTickSpacing - returns tick spacing 10" {
    const p = makeCustomPerpData(100.0, 10);
    try std.testing.expectEqual(@as(i24, 10), perp.getPerpTickSpacing(p));
}

test "getPerpTickSpacing - returns tick spacing 200" {
    const p = makeCustomPerpData(100.0, 200);
    try std.testing.expectEqual(@as(i24, 200), perp.getPerpTickSpacing(p));
}

test "getPerpTickSpacing - different perps can have different tick spacings" {
    const p1 = makeCustomPerpData(100.0, 10);
    const p2 = makeCustomPerpData(100.0, 60);
    try std.testing.expect(perp.getPerpTickSpacing(p1) != perp.getPerpTickSpacing(p2));
}
