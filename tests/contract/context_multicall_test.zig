const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const PerpCityContext = sdk.context.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const multicall = sdk.multicall;

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

test "encodeAggregate3 lays out selector, offset, length and tuple body" {
    const alloc = std.testing.allocator;
    const calls = [_]multicall.Call3{
        .{ .target = addr(0x11), .call_data = &.{ 0x70, 0xa0, 0x82, 0x31 }, .allow_failure = false },
    };
    const encoded = try multicall.encodeAggregate3(alloc, &calls);
    defer alloc.free(encoded);

    // selector(4) + array-offset(32) + length(32) + tuple-offset(32) + tuple
    // body(address 32 + bool 32 + bytes-offset 32 + bytes-len 32 + data 32) = 260.
    try std.testing.expectEqual(@as(usize, 260), encoded.len);
    try std.testing.expectEqualSlices(u8, &multicall.AGGREGATE3_SELECTOR, encoded[0..4]);
    try std.testing.expectEqual(@as(u8, 0x20), encoded[4 + 31]); // array offset
    try std.testing.expectEqual(@as(u8, 0x01), encoded[4 + 63]); // array length
    // Target address is left-padded into the tuple's first word (starts at 100).
    try std.testing.expectEqual(@as(u8, 0x11), encoded[112]);
    try std.testing.expectEqual(@as(u8, 0x11), encoded[131]);
}

test "encodeAggregate3 grows with a second call and empty calldata" {
    const alloc = std.testing.allocator;
    const one = [_]multicall.Call3{
        .{ .target = addr(0x11), .call_data = &.{ 0x70, 0xa0, 0x82, 0x31 }, .allow_failure = false },
    };
    const two = [_]multicall.Call3{
        one[0],
        .{ .target = addr(0x22), .call_data = &.{}, .allow_failure = true },
    };
    const e1 = try multicall.encodeAggregate3(alloc, &one);
    defer alloc.free(e1);
    const e2 = try multicall.encodeAggregate3(alloc, &two);
    defer alloc.free(e2);

    try std.testing.expect(e2.len > e1.len);
    try std.testing.expectEqual(@as(u8, 0x02), e2[4 + 63]); // length = 2
}

test "multicall3 sends aggregate3 through the seam and decodes results" {
    const alloc = std.testing.allocator;
    var mock = MockChainClient.init(alloc);
    defer mock.deinit();

    // Canned aggregate3 return for [(true, 0x00000064)]:
    //   word0 array-offset 0x20, word1 length 1, word2 tuple-offset 0x20,
    //   word3 success 1, word4 bytes-offset 0x40, word5 bytes-len 4, word6 data.
    var resp: [7 * 32]u8 = @splat(0);
    resp[31] = 0x20;
    resp[63] = 0x01;
    resp[95] = 0x20;
    resp[127] = 0x01;
    resp[159] = 0x40;
    resp[191] = 0x04;
    resp[195] = 0x64;
    try mock.setResponse(multicall.AGGREGATE3_SELECTOR, &resp);

    var ctx = PerpCityContext.initWithClient(alloc, mock.client(), testDeployments());
    defer ctx.deinit();

    const calls = [_]multicall.Call3{
        .{ .target = addr(0xBE), .call_data = &.{ 0x70, 0xa0, 0x82, 0x31 }, .allow_failure = true },
    };
    const results = try ctx.multicall3(&calls);
    defer multicall.freeResults(alloc, results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expect(results[0].success);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x00, 0x00, 0x64 }, results[0].return_data);
}
