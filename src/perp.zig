const types = @import("types.zig");

pub fn getPerpMark(perp_data: types.PerpData) f64 {
    return perp_data.mark;
}

pub fn getPerpBeacon(perp_data: types.PerpData) types.Address {
    return perp_data.beacon;
}

pub fn getPerpBounds(perp_data: types.PerpData) types.Bounds {
    return perp_data.bounds;
}

pub fn getPerpFees(perp_data: types.PerpData) types.Fees {
    return perp_data.fees;
}

pub fn getPerpTickSpacing(perp_data: types.PerpData) i24 {
    return perp_data.tick_spacing;
}

test "getPerpMark returns mark price" {
    const std = @import("std");
    const perp = types.PerpData{
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
    try std.testing.expectEqual(@as(f64, 1500.0), getPerpMark(perp));
    try std.testing.expectEqual(@as(i24, 60), getPerpTickSpacing(perp));
}
