const types = @import("types.zig");

pub fn getPerpMark(perp_data: types.PerpData) f64 {
    return perp_data.mark;
}

pub fn getPerpAddress(perp_data: types.PerpData) types.Address {
    return perp_data.perp;
}

pub fn getPerpBeacon(perp_data: types.PerpData) types.Address {
    return perp_data.beacon;
}

pub fn getPerpTakerBounds(perp_data: types.PerpData) types.Bounds {
    return perp_data.taker_bounds;
}

pub fn getPerpMakerBounds(perp_data: types.PerpData) types.Bounds {
    return perp_data.maker_bounds;
}

pub fn getPerpFees(perp_data: types.PerpData) types.Fees {
    return perp_data.fees;
}

test "perp accessors return the correct fields" {
    const std = @import("std");
    const data = types.PerpData{
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
    try std.testing.expectEqual(@as(f64, 1500.0), getPerpMark(data));
    try std.testing.expectEqual(@as(f64, 10.0), getPerpTakerBounds(data).max_leverage);
    try std.testing.expectEqual(@as(f64, 0.003), getPerpFees(data).lp_fee);
}
