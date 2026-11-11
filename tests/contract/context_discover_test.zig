const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const PerpCityContext = sdk.context.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const events = sdk.events;
const perp_abi = sdk.abi.perp_abi;

const Log = eth.receipt.Log;

// ---------------------------------------------------------------------------
// Helpers (mirror the other contract/*_test.zig files)
// ---------------------------------------------------------------------------

fn addr(b: u8) types.Address {
    return @as([20]u8, @splat(b));
}

fn testDeployments() types.PerpCityDeployments {
    return .{
        .perp_factory = addr(0x11),
        .module_registry = addr(0x22),
        .protocol_fee_manager = addr(0x33),
        .usdc = addr(0x44),
    };
}

const fx = @import("event_fixtures.zig");
const mkLog = fx.mkLog;

/// Register the on-chain `positionOwner(id) -> owner` answer for a specific id
/// via the mock's calldata table (so different ids resolve to different owners).
fn setPositionOwner(mock: *MockChainClient, id: u256, owner: types.Address) !void {
    const alloc = std.testing.allocator;
    const calldata = try eth.abi_encode.encodeFunctionCall(alloc, perp_abi.position_owner_selector, &.{.{ .uint256 = id }});
    defer alloc.free(calldata);
    const ret = try fx.enc(&.{.{ .address = owner }});
    defer alloc.free(ret);
    try mock.setResponseCalldata(calldata, ret);
}

// ---------------------------------------------------------------------------
// discoverOwnedPositions -- pollEvents (candidate ids) + batched positionOwner filter
// ---------------------------------------------------------------------------

test "discoverOwnedPositions returns only live positions owned by the target, deduped" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const owner_a = addr(0xA1);
    const owner_b = addr(0xB2);

    // The ids live in topics[1]. The owner topic records who held the position
    // when the event fired, which is NOT what discovery trusts: position 3 was
    // opened by A and has since been liquidated.
    const to1 = fx.positionTopics(events.Topics.TAKER_OPENED, 1, owner_a);
    const mo2 = fx.positionTopics(events.Topics.MAKER_OPENED, 2, owner_b);
    const to3 = fx.positionTopics(events.Topics.TAKER_OPENED, 3, owner_a);
    const ma1 = fx.positionTopics(events.Topics.MAKER_ADJUSTED, 1, owner_a);
    const tl3 = fx.positionTopics(events.Topics.TAKER_LIQUIDATED, 3, addr(0x4B));

    const d_to = try fx.takerOpenedData();
    defer allocator.free(d_to);
    const d_mo = try fx.makerOpenedData();
    defer allocator.free(d_mo);
    const d_ma = try fx.makerLifecycleData();
    defer allocator.free(d_ma);
    const d_tl = try fx.enc(&.{ .{ .uint256 = 1 }, .{ .uint256 = 0 } });
    defer allocator.free(d_tl);

    // Position 1 appears twice (opened then adjusted) -> deduped to one id.
    const logs = [_]Log{
        mkLog(&to1, d_to),
        mkLog(&mo2, d_mo),
        mkLog(&to3, d_to),
        mkLog(&ma1, d_ma),
        mkLog(&tl3, d_tl),
    };
    try mock.setLogs(&logs);

    // id 1 -> A, id 2 -> B, id 3 -> zero (cleared by the liquidation).
    try setPositionOwner(&mock, 1, owner_a);
    try setPositionOwner(&mock, 2, owner_b);
    try setPositionOwner(&mock, 3, types.ZERO_ADDRESS);

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    // Owner A holds only position 1 (seen twice in events, returned once); the
    // liquidated position 3 that A opened is excluded.
    const a_positions = try ctx.discoverOwnedPositions(addr(0xBE), owner_a, 0, 200);
    defer allocator.free(a_positions);
    try std.testing.expectEqualSlices(u256, &[_]u256{1}, a_positions);

    // Owner B holds only position 2.
    const b_positions = try ctx.discoverOwnedPositions(addr(0xBE), owner_b, 0, 200);
    defer allocator.free(b_positions);
    try std.testing.expectEqualSlices(u256, &[_]u256{2}, b_positions);

    // A third party holds nothing.
    const c_positions = try ctx.discoverOwnedPositions(addr(0xBE), addr(0xCC), 0, 200);
    defer allocator.free(c_positions);
    try std.testing.expectEqual(@as(usize, 0), c_positions.len);

    // The zero address owns nothing: it must not match the cleared position 3.
    const zero_positions = try ctx.discoverOwnedPositions(addr(0xBE), types.ZERO_ADDRESS, 0, 200);
    defer allocator.free(zero_positions);
    try std.testing.expectEqual(@as(usize, 0), zero_positions.len);
}

test "discoverOwnedPositions follows a backstop to the position's new owner" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const opener = addr(0xA1);
    const backstopper = addr(0xB2);

    // Opened by `opener`, then reassigned: PositionOwnerUpdated carries all
    // three parameters in topics and no data.
    const to = fx.positionTopics(events.Topics.TAKER_OPENED, 9, opener);
    const ou = [_][32]u8{
        events.Topics.POSITION_OWNER_UPDATED,
        fx.topicU256(9),
        fx.topicAddr(opener),
        fx.topicAddr(backstopper),
    };
    const d_to = try fx.takerOpenedData();
    defer allocator.free(d_to);
    try mock.setLogs(&[_]Log{ mkLog(&to, d_to), mkLog(&ou, &.{}) });
    try setPositionOwner(&mock, 9, backstopper);

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const mine = try ctx.discoverOwnedPositions(addr(0xBE), backstopper, 0, 200);
    defer allocator.free(mine);
    try std.testing.expectEqualSlices(u256, &[_]u256{9}, mine);

    const theirs = try ctx.discoverOwnedPositions(addr(0xBE), opener, 0, 200);
    defer allocator.free(theirs);
    try std.testing.expectEqual(@as(usize, 0), theirs.len);
}

test "positionId reads the id for position events and null for market-wide events" {
    const positionId = sdk.event_decode.positionId;
    try std.testing.expectEqual(
        @as(?u256, 7),
        positionId(.{ .taker_opened = std.mem.zeroInit(events.TakerOpenedEvent, .{ .pos_id = 7 }) }),
    );
    try std.testing.expectEqual(
        @as(?u256, 9),
        positionId(.{ .maker_opened = std.mem.zeroInit(events.MakerOpenedEvent, .{ .pos_id = 9 }) }),
    );
    try std.testing.expectEqual(
        @as(?u256, 11),
        positionId(.{ .taker_liquidated = std.mem.zeroInit(events.TakerLiquidatedEvent, .{ .pos_id = 11 }) }),
    );
    try std.testing.expectEqual(
        @as(?u256, 12),
        positionId(.{ .position_owner_updated = std.mem.zeroInit(events.PositionOwnerUpdatedEvent, .{ .pos_id = 12 }) }),
    );
    try std.testing.expectEqual(@as(?u256, null), positionId(.{ .index_updated = .{ .index = 1 } }));
    try std.testing.expectEqual(@as(?u256, null), positionId(.new_block));
}

test "discoverOwnedPositions returns an empty slice when the perp has no events" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const positions = try ctx.discoverOwnedPositions(addr(0xBE), addr(0xA1), 0, 10);
    defer allocator.free(positions);
    try std.testing.expectEqual(@as(usize, 0), positions.len);
}
