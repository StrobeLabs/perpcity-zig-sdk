const types = @import("types.zig");

pub fn getUserUsdcBalance(user_data: types.UserData) f64 {
    return user_data.usdc_balance;
}

pub fn getUserOpenPositions(user_data: types.UserData) []const types.OpenPositionData {
    return user_data.open_positions;
}

pub fn getUserWalletAddress(user_data: types.UserData) types.Address {
    return user_data.wallet_address;
}

test "getUserUsdcBalance returns balance" {
    const std = @import("std");
    const user = types.UserData{
        .wallet_address = types.ZERO_ADDRESS,
        .usdc_balance = 1000.0,
        .open_positions = &.{},
    };
    try std.testing.expectEqual(@as(f64, 1000.0), getUserUsdcBalance(user));
}

test "getUserOpenPositions returns empty slice" {
    const std = @import("std");
    const user = types.UserData{
        .wallet_address = types.ZERO_ADDRESS,
        .usdc_balance = 0.0,
        .open_positions = &.{},
    };
    try std.testing.expectEqual(@as(usize, 0), getUserOpenPositions(user).len);
}
