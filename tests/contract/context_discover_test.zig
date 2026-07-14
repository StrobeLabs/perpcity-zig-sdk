const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const PerpCityContext = sdk.context.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const events = sdk.events;
const perp_abi = sdk.abi.perp_abi;

const AbiValue = eth.abi_encode.AbiValue;
const Log = eth.receipt.Log;

// ---------------------------------------------------------------------------
// Helpers (mirror the other contract/*_test.zig files)
// ---------------------------------------------------------------------------

fn addr(b: u8) types.Address {
    return [_]u8{b} ** 20;
}

fn testDeployments() types.PerpCityDeployments {
    return .{
        .perp_factory = addr(0x11),
        .module_registry = addr(0x22),
        .protocol_fee_manager = addr(0x33),
        .usdc = addr(0x44),
    };
}

fn enc(values: []const AbiValue) ![]u8 {
    return eth.abi_encode.encodeValues(std.testing.allocator, values);
}

/// A log emitted by perp `0xBE` with the given topics and data (borrowed;
/// `setLogs` deep-copies).
fn mkLog(topics: []const [32]u8, data: []const u8) Log {
    return .{
        .address = addr(0xBE),
        .topics = topics,
        .data = data,
        .block_number = 100,
        .transaction_hash = null,
        .transaction_index = null,
        .log_index = null,
        .block_hash = null,
        .removed = false,
    };
}

/// Register the on-chain `ownerOf(id) -> owner` answer for a specific id via the
/// mock's calldata table (so different ids resolve to different owners).
fn setOwnerOf(mock: *MockChainClient, id: u256, owner: types.Address) !void {
    const alloc = std.testing.allocator;
    const calldata = try eth.abi_encode.encodeFunctionCall(alloc, perp_abi.owner_of_selector, &.{.{ .uint256 = id }});
    defer alloc.free(calldata);
    const ret = try enc(&.{.{ .address = owner }});
    defer alloc.free(ret);
    try mock.setResponseCalldata(calldata, ret);
}

// TakerOpened data = posId + inline SwapResult(7 static fields).
fn takerOpenedData(pos_id: u256) ![]u8 {
    return enc(&.{
        .{ .uint256 = pos_id },
        .{ .int256 = 0 },
        .{ .uint256 = 0 },
        .{ .int256 = 0 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
    });
}

// MakerAdjusted data = posId + funding + longUtilFees + shortUtilFees + lpFees.
fn makerAdjustedData(pos_id: u256) ![]u8 {
    return enc(&.{
        .{ .uint256 = pos_id }, .{ .int256 = 0 }, .{ .uint256 = 0 }, .{ .uint256 = 0 }, .{ .uint256 = 0 },
    });
}

// ---------------------------------------------------------------------------
// discoverOwnedPositions -- pollEvents (candidate ids) + batched ownerOf filter
// ---------------------------------------------------------------------------

test "discoverOwnedPositions returns only live positions owned by the target, deduped" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const to1 = [_][32]u8{events.Topics.TAKER_OPENED};
    const mo2 = [_][32]u8{events.Topics.MAKER_OPENED};
    const to3 = [_][32]u8{events.Topics.TAKER_OPENED};
    const ma1 = [_][32]u8{events.Topics.MAKER_ADJUSTED};

    // Position 1 (taker) opened then adjusted -> must be deduped to one id.
    const d_to1 = try takerOpenedData(1);
    defer allocator.free(d_to1);
    const d_mo2 = try enc(&.{.{ .uint256 = 2 }}); // MakerOpened(posId)
    defer allocator.free(d_mo2);
    const d_to3 = try takerOpenedData(3);
    defer allocator.free(d_to3);
    const d_ma1 = try makerAdjustedData(1);
    defer allocator.free(d_ma1);

    const logs = [_]Log{
        mkLog(&to1, d_to1),
        mkLog(&mo2, d_mo2),
        mkLog(&to3, d_to3),
        mkLog(&ma1, d_ma1),
    };
    try mock.setLogs(&logs);

    const owner_a = addr(0xA1);
    const owner_b = addr(0xB2);
    // id 1 -> A, id 2 -> B, id 3 -> unregistered (ownerOf reverts == closed).
    try setOwnerOf(&mock, 1, owner_a);
    try setOwnerOf(&mock, 2, owner_b);

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    // Owner A holds only position 1 (seen twice in events, returned once).
    const a_positions = try ctx.discoverOwnedPositions(addr(0xBE), owner_a, 0, 200);
    defer allocator.free(a_positions);
    try std.testing.expectEqualSlices(u256, &[_]u256{1}, a_positions);

    // Owner B holds only position 2.
    const b_positions = try ctx.discoverOwnedPositions(addr(0xBE), owner_b, 0, 200);
    defer allocator.free(b_positions);
    try std.testing.expectEqualSlices(u256, &[_]u256{2}, b_positions);

    // A third party holds nothing; the reverted id 3 never leaks in either.
    const c_positions = try ctx.discoverOwnedPositions(addr(0xBE), addr(0xCC), 0, 200);
    defer allocator.free(c_positions);
    try std.testing.expectEqual(@as(usize, 0), c_positions.len);
}

test "positionId reads the id for position events and null for market-wide events" {
    const positionId = sdk.event_decode.positionId;
    try std.testing.expectEqual(
        @as(?u256, 7),
        positionId(.{ .taker_opened = .{ .pos_id = 7, .sr = std.mem.zeroes(events.SwapResult) } }),
    );
    try std.testing.expectEqual(@as(?u256, 9), positionId(.{ .maker_opened = .{ .pos_id = 9 } }));
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
