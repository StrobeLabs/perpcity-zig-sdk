const std = @import("std");
const sdk = @import("perpcity_sdk");
const user = sdk.user;
const types = sdk.types;

fn makeTestUserData(balance: f64, positions: []const types.OpenPositionData) types.UserData {
    return .{
        .wallet_address = types.ZERO_ADDRESS,
        .usdc_balance = balance,
        .open_positions = positions,
    };
}

fn makeOpenPosition(pos_id: u256, is_maker: bool, perp_delta: i256) types.OpenPositionData {
    return .{
        .perp = types.ZERO_ADDRESS,
        .position_id = pos_id,
        .is_maker = is_maker,
        .live_details = .{
            .margin = 100.0,
            .perp_delta = perp_delta,
            .liq_margin_ratio = 50_000,
            .backstop_margin_ratio = 20_000,
        },
    };
}

// =============================================================================
// getUserUsdcBalance
// =============================================================================

test "getUserUsdcBalance - returns correct balance 1000.0" {
    const u_data = makeTestUserData(1000.0, &.{});
    try std.testing.expectEqual(@as(f64, 1000.0), user.getUserUsdcBalance(u_data));
}

test "getUserUsdcBalance - returns zero balance" {
    const u_data = makeTestUserData(0.0, &.{});
    try std.testing.expectEqual(@as(f64, 0.0), user.getUserUsdcBalance(u_data));
}

test "getUserUsdcBalance - returns large balance" {
    const u_data = makeTestUserData(1_000_000.0, &.{});
    try std.testing.expectEqual(@as(f64, 1_000_000.0), user.getUserUsdcBalance(u_data));
}

test "getUserUsdcBalance - returns fractional balance" {
    const u_data = makeTestUserData(0.5, &.{});
    try std.testing.expectEqual(@as(f64, 0.5), user.getUserUsdcBalance(u_data));
}

test "getUserUsdcBalance - returns negative balance" {
    const u_data = makeTestUserData(-50.0, &.{});
    try std.testing.expectEqual(@as(f64, -50.0), user.getUserUsdcBalance(u_data));
}

test "getUserUsdcBalance - balance is independent of positions" {
    const positions = [_]types.OpenPositionData{
        makeOpenPosition(1, false, 1_500_000),
    };
    const u_data = makeTestUserData(1000.0, &positions);
    try std.testing.expectEqual(@as(f64, 1000.0), user.getUserUsdcBalance(u_data));
}

// =============================================================================
// getUserOpenPositions
// =============================================================================

test "getUserOpenPositions - returns empty slice when no positions" {
    const u_data = makeTestUserData(1000.0, &.{});
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(usize, 0), positions.len);
}

test "getUserOpenPositions - returns single position" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, false, 1_500_000),
    };
    const u_data = makeTestUserData(1000.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(usize, 1), positions.len);
    try std.testing.expectEqual(@as(u256, 1), positions[0].position_id);
}

test "getUserOpenPositions - returns multiple positions" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, false, 1_500_000),
        makeOpenPosition(2, false, -1_000_000),
        makeOpenPosition(3, true, 0),
    };
    const u_data = makeTestUserData(1000.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(usize, 3), positions.len);
}

test "getUserOpenPositions - position ids are preserved" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(10, false, 1_500_000),
        makeOpenPosition(20, false, -1_000_000),
    };
    const u_data = makeTestUserData(1000.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(u256, 10), positions[0].position_id);
    try std.testing.expectEqual(@as(u256, 20), positions[1].position_id);
}

test "getUserOpenPositions - perp_delta is preserved" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, false, 1_234_567),
    };
    const u_data = makeTestUserData(0.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(i256, 1_234_567), positions[0].live_details.perp_delta);
}

test "getUserOpenPositions - is_maker bool is preserved" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, true, 0),
    };
    const u_data = makeTestUserData(0.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(true, positions[0].is_maker);
}

// =============================================================================
// getUserWalletAddress
// =============================================================================

test "getUserWalletAddress - returns zero address" {
    const u_data = makeTestUserData(0.0, &.{});
    try std.testing.expectEqual(types.ZERO_ADDRESS, user.getUserWalletAddress(u_data));
}

test "getUserWalletAddress - returns custom address" {
    var custom_addr: types.Address = [_]u8{0} ** 20;
    custom_addr[0] = 0xDE;
    custom_addr[1] = 0xAD;
    custom_addr[18] = 0xBE;
    custom_addr[19] = 0xEF;
    const u_data = types.UserData{
        .wallet_address = custom_addr,
        .usdc_balance = 500.0,
        .open_positions = &.{},
    };
    const addr = user.getUserWalletAddress(u_data);
    try std.testing.expectEqual(@as(u8, 0xDE), addr[0]);
    try std.testing.expectEqual(@as(u8, 0xAD), addr[1]);
    try std.testing.expectEqual(@as(u8, 0xBE), addr[18]);
    try std.testing.expectEqual(@as(u8, 0xEF), addr[19]);
}

test "getUserWalletAddress - different users have different addresses" {
    var addr1: types.Address = [_]u8{0} ** 20;
    addr1[0] = 0x01;
    var addr2: types.Address = [_]u8{0} ** 20;
    addr2[0] = 0x02;

    const user_a = types.UserData{
        .wallet_address = addr1,
        .usdc_balance = 0.0,
        .open_positions = &.{},
    };
    const user_b = types.UserData{
        .wallet_address = addr2,
        .usdc_balance = 0.0,
        .open_positions = &.{},
    };

    const a1 = user.getUserWalletAddress(user_a);
    const a2 = user.getUserWalletAddress(user_b);
    try std.testing.expect(!std.mem.eql(u8, &a1, &a2));
}
