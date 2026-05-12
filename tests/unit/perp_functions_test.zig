const std = @import("std");
const sdk = @import("perpcity_sdk");
const perp = sdk.perp;
const types = sdk.types;

fn makeTestPerpData() types.PerpData {
    return .{
        .perp = types.ZERO_ADDRESS,
        .mark = 1500.0,
        .beacon = types.ZERO_ADDRESS,
        .taker_bounds = .{
            .init_margin_ratio = 0.1,
            .liq_margin_ratio = 0.05,
            .backstop_margin_ratio = 0.02,
            .max_leverage = 10.0,
        },
        .maker_bounds = .{
            .init_margin_ratio = 1.0,
            .liq_margin_ratio = 0.9,
            .backstop_margin_ratio = 0.8,
            .max_leverage = 1.0,
        },
        .fees = .{
            .creator_fee = 0.001,
            .insurance_fee = 0.001,
            .lp_fee = 0.003,
            .liquidation_fee = 0.01,
        },
    };
}

fn makeCustomPerpData(mark: f64) types.PerpData {
    var data = makeTestPerpData();
    data.mark = mark;
    return data;
}

test "getPerpMark - returns correct mark price 1500.0" {
    const p = makeTestPerpData();
    try std.testing.expectEqual(@as(f64, 1500.0), perp.getPerpMark(p));
}

test "getPerpMark - returns mark of 0.0 when set to 0" {
    const p = makeCustomPerpData(0.0);
    try std.testing.expectEqual(@as(f64, 0.0), perp.getPerpMark(p));
}

test "getPerpMark - returns large mark price" {
    const p = makeCustomPerpData(50_000.0);
    try std.testing.expectEqual(@as(f64, 50_000.0), perp.getPerpMark(p));
}

test "getPerpMark - returns fractional mark price" {
    const p = makeCustomPerpData(0.001);
    try std.testing.expectEqual(@as(f64, 0.001), perp.getPerpMark(p));
}

test "getPerpMark - different perps return different marks" {
    const p1 = makeCustomPerpData(100.0);
    const p2 = makeCustomPerpData(200.0);
    try std.testing.expect(perp.getPerpMark(p1) != perp.getPerpMark(p2));
}

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

test "getPerpTakerBounds - has expected ratios" {
    const p = makeTestPerpData();
    const b = perp.getPerpTakerBounds(p);
    try std.testing.expectEqual(@as(f64, 0.1), b.init_margin_ratio);
    try std.testing.expectEqual(@as(f64, 0.05), b.liq_margin_ratio);
    try std.testing.expectEqual(@as(f64, 0.02), b.backstop_margin_ratio);
    try std.testing.expectEqual(@as(f64, 10.0), b.max_leverage);
}

test "getPerpMakerBounds - has expected ratios" {
    const p = makeTestPerpData();
    const b = perp.getPerpMakerBounds(p);
    try std.testing.expectEqual(@as(f64, 1.0), b.init_margin_ratio);
    try std.testing.expectEqual(@as(f64, 0.9), b.liq_margin_ratio);
    try std.testing.expectEqual(@as(f64, 0.8), b.backstop_margin_ratio);
}

test "getPerpFees - returns correct fees struct" {
    const p = makeTestPerpData();
    const fees = perp.getPerpFees(p);
    try std.testing.expectEqual(@as(f64, 0.001), fees.creator_fee);
    try std.testing.expectEqual(@as(f64, 0.001), fees.insurance_fee);
    try std.testing.expectEqual(@as(f64, 0.003), fees.lp_fee);
    try std.testing.expectEqual(@as(f64, 0.01), fees.liquidation_fee);
}

test "getPerpFees - liquidation fee is largest" {
    const p = makeTestPerpData();
    const fees = perp.getPerpFees(p);
    try std.testing.expect(fees.liquidation_fee >= fees.creator_fee);
    try std.testing.expect(fees.liquidation_fee >= fees.insurance_fee);
    try std.testing.expect(fees.liquidation_fee >= fees.lp_fee);
}

test "getPerpAddress - returns perp field" {
    var p = makeTestPerpData();
    const addr: types.Address = [_]u8{0xCC} ** 20;
    p.perp = addr;
    try std.testing.expectEqual(addr, perp.getPerpAddress(p));
}
