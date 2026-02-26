const std = @import("std");
const sdk = @import("perpcity_sdk");
const user = sdk.user;
const types = sdk.types;

// =============================================================================
// Test helpers
// =============================================================================

fn makeTestUserData(balance: f64, positions: []const types.OpenPositionData) types.UserData {
    return .{
        .wallet_address = types.ZERO_ADDRESS,
        .usdc_balance = balance,
        .open_positions = positions,
    };
}

fn makeOpenPosition(pos_id: u256, is_long: ?bool, pnl: f64) types.OpenPositionData {
    return .{
        .perp_id = types.ZERO_BYTES32,
        .position_id = pos_id,
        .is_long = is_long,
        .is_maker = null,
        .live_details = .{
            .pnl = pnl,
            .funding_payment = 0.0,
            .effective_margin = 100.0,
            .is_liquidatable = false,
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

test "getUserUsdcBalance - returns negative balance (if applicable)" {
    const u_data = makeTestUserData(-50.0, &.{});
    try std.testing.expectEqual(@as(f64, -50.0), user.getUserUsdcBalance(u_data));
}

test "getUserUsdcBalance - balance is independent of positions" {
    const positions = [_]types.OpenPositionData{
        makeOpenPosition(1, true, 50.0),
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
        makeOpenPosition(1, true, 50.0),
    };
    const u_data = makeTestUserData(1000.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(usize, 1), positions.len);
    try std.testing.expectEqual(@as(u256, 1), positions[0].position_id);
}

test "getUserOpenPositions - returns multiple positions" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, true, 50.0),
        makeOpenPosition(2, false, -10.0),
        makeOpenPosition(3, null, 0.0),
    };
    const u_data = makeTestUserData(1000.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(usize, 3), positions.len);
}

test "getUserOpenPositions - position ids are preserved" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(10, true, 50.0),
        makeOpenPosition(20, false, -10.0),
    };
    const u_data = makeTestUserData(1000.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(u256, 10), positions[0].position_id);
    try std.testing.expectEqual(@as(u256, 20), positions[1].position_id);
}

test "getUserOpenPositions - position pnl values are preserved" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, true, 123.456),
    };
    const u_data = makeTestUserData(0.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(f64, 123.456), positions[0].live_details.pnl);
}

test "getUserOpenPositions - positions with is_long null" {
    const positions_arr = [_]types.OpenPositionData{
        makeOpenPosition(1, null, 0.0),
    };
    const u_data = makeTestUserData(0.0, &positions_arr);
    const positions = user.getUserOpenPositions(u_data);
    try std.testing.expectEqual(@as(?bool, null), positions[0].is_long);
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

    const user1 = types.UserData{
        .wallet_address = addr1,
        .usdc_balance = 0.0,
        .open_positions = &.{},
    };
    const user2 = types.UserData{
        .wallet_address = addr2,
        .usdc_balance = 0.0,
        .open_positions = &.{},
    };

    const a1 = user.getUserWalletAddress(user1);
    const a2 = user.getUserWalletAddress(user2);
    // At least one byte differs
    try std.testing.expect(!std.mem.eql(u8, &a1, &a2));
}

test "getUserWalletAddress - all bytes match" {
    var expected: types.Address = undefined;
    for (&expected, 0..) |*byte, i| {
        byte.* = @intCast(i);
    }
    const u_data = types.UserData{
        .wallet_address = expected,
        .usdc_balance = 0.0,
        .open_positions = &.{},
    };
    try std.testing.expectEqual(expected, user.getUserWalletAddress(u_data));
}
