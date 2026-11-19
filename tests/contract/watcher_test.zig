const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const events = sdk.events;
const event_decode = sdk.event_decode;
const watcher = sdk.watcher;

const fx = @import("event_fixtures.zig");
const Log = fx.Log;
const enc = fx.enc;
const mkLog = fx.mkLog;

// The watcher's per-block decode step. Shared with pollEvents; tested directly
// here since the watcher's WebSocket loop is integration-only.
test "decodeLogs decodes recognized logs and skips unknown topics" {
    const allocator = std.testing.allocator;

    // TakerOpened: indexed (posId, owner); margin + SwapResult + checkpoint in data.
    const to_topics = fx.positionTopics(events.Topics.TAKER_OPENED, 7, fx.addr(0xA1));
    const unknown_topics = [_][32]u8{@as([32]u8, @splat(0xFF))};

    const to_data = try fx.takerOpenedData();
    defer allocator.free(to_data);
    const unknown_data = try enc(&.{.{ .uint256 = 1 }});
    defer allocator.free(unknown_data);

    const logs = [_]Log{
        mkLog(&to_topics, to_data),
        mkLog(&unknown_topics, unknown_data),
        mkLog(&to_topics, to_data),
    };

    const decoded = try event_decode.decodeLogs(allocator, &logs);
    defer allocator.free(decoded);

    // The unknown-topic log is skipped; the two TakerOpened logs decode.
    try std.testing.expectEqual(@as(usize, 2), decoded.len);
    try std.testing.expectEqual(@as(u256, 7), decoded[0].taker_opened.pos_id);
    try std.testing.expectEqual(@as(u256, 7), decoded[1].taker_opened.pos_id);
}

test "decodeLogs returns an empty slice for no logs" {
    const allocator = std.testing.allocator;
    const decoded = try event_decode.decodeLogs(allocator, &.{});
    defer allocator.free(decoded);
    try std.testing.expectEqual(@as(usize, 0), decoded.len);
}

// PerpEventWatcher's constructor opens live WS/HTTP connections, so it is
// exercised by integration, not CI. Assert its exact signature here so a change
// to parameter order/types or the return payload breaks the build.
test "PerpEventWatcher.connect / pollNext have the intended signatures" {
    const connect_info = @typeInfo(@TypeOf(watcher.PerpEventWatcher.connect)).@"fn";
    try std.testing.expectEqual(@as(usize, 5), connect_info.param_types.len);
    try std.testing.expect(connect_info.param_types[0].? == std.mem.Allocator);
    try std.testing.expect(connect_info.param_types[1].? == []const u8); // ws_url
    try std.testing.expect(connect_info.param_types[2].? == []const u8); // rpc_url
    try std.testing.expect(connect_info.param_types[3].? == types.Address);
    try std.testing.expect(connect_info.param_types[4].? == watcher.WatchOpts);
    try std.testing.expect(@typeInfo(connect_info.return_type.?).error_union.payload == *watcher.PerpEventWatcher);

    const poll_info = @typeInfo(@TypeOf(watcher.PerpEventWatcher.pollNext)).@"fn";
    try std.testing.expectEqual(@as(usize, 2), poll_info.param_types.len);
    try std.testing.expect(poll_info.param_types[0].? == *watcher.PerpEventWatcher);
    try std.testing.expect(poll_info.param_types[1].? == std.mem.Allocator);
    try std.testing.expect(@typeInfo(poll_info.return_type.?).error_union.payload == []event_decode.DecodedEvent);
}
