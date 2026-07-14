const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const PerpCityContext = sdk.context.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const chain_client = sdk.chain_client;
const revert = sdk.revert;
const perp_abi = sdk.abi.perp_abi;

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

// ---------------------------------------------------------------------------
// parseEthCallResponse -- pure JSON extraction (covers the EthChainClient path)
// ---------------------------------------------------------------------------

test "parseEthCallResponse maps a result hex string to ok bytes" {
    const alloc = std.testing.allocator;
    const out = try chain_client.parseEthCallResponse(alloc, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":\"0x1234abcd\"}");
    defer chain_client.freeCallOutcome(out, alloc);
    try std.testing.expect(out == .ok);
    try std.testing.expectEqualSlices(u8, &.{ 0x12, 0x34, 0xab, 0xcd }, out.ok);
}

test "parseEthCallResponse maps error.data to reverted bytes" {
    const alloc = std.testing.allocator;
    const sel = eth.keccak.selector("NotLiquidatable()");
    const json = try std.fmt.allocPrint(
        alloc,
        "{{\"error\":{{\"code\":3,\"message\":\"execution reverted\",\"data\":\"0x{x:0>2}{x:0>2}{x:0>2}{x:0>2}\"}}}}",
        .{ sel[0], sel[1], sel[2], sel[3] },
    );
    defer alloc.free(json);

    const out = try chain_client.parseEthCallResponse(alloc, json);
    defer chain_client.freeCallOutcome(out, alloc);
    try std.testing.expect(out == .reverted);
    // The captured bytes decode to the typed custom error.
    try std.testing.expectEqual(revert.Revert{ .contract_error = .not_liquidatable }, revert.decode(out.reverted));
}

test "parseEthCallResponse maps an error without data to an empty revert" {
    const alloc = std.testing.allocator;
    const out = try chain_client.parseEthCallResponse(alloc, "{\"error\":{\"code\":3,\"message\":\"execution reverted\"}}");
    defer chain_client.freeCallOutcome(out, alloc);
    try std.testing.expect(out == .reverted);
    try std.testing.expectEqual(@as(usize, 0), out.reverted.len);
}

test "parseEthCallResponse rejects a response that is neither result nor error" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.RpcError, chain_client.parseEthCallResponse(alloc, "{\"jsonrpc\":\"2.0\",\"id\":1}"));
}

// ---------------------------------------------------------------------------
// context.simulateCall -- ok / reverted(typed) / state-override passthrough
// ---------------------------------------------------------------------------

test "simulateCall returns ok return data on success" {
    const alloc = std.testing.allocator;
    var mock = MockChainClient.init(alloc);
    defer mock.deinit();

    const sel = perp_abi.liquidate_taker_selector;
    try mock.setResponse(sel, &.{ 0xde, 0xad });

    var ctx = PerpCityContext.initWithClient(alloc, mock.client(), testDeployments());
    defer ctx.deinit();

    const out = try ctx.simulateCall(addr(0xBE), &sel, addr(0xAA), null);
    defer out.deinit(alloc);
    try std.testing.expect(out == .ok);
    try std.testing.expectEqualSlices(u8, &.{ 0xde, 0xad }, out.ok);
    try std.testing.expect(!mock.last_callraw_had_overrides);
}

test "simulateCall captures and decodes a revert" {
    const alloc = std.testing.allocator;
    var mock = MockChainClient.init(alloc);
    defer mock.deinit();

    // The liquidate call reverts with NotLiquidatable().
    const sel = perp_abi.liquidate_taker_selector;
    const not_liq = eth.keccak.selector("NotLiquidatable()");
    try mock.setRevert(sel, &not_liq);

    var ctx = PerpCityContext.initWithClient(alloc, mock.client(), testDeployments());
    defer ctx.deinit();

    const out = try ctx.simulateCall(addr(0xBE), &sel, addr(0xAA), null);
    defer out.deinit(alloc);
    try std.testing.expect(out == .reverted);
    try std.testing.expectEqual(revert.Revert{ .contract_error = .not_liquidatable }, out.reverted.decoded);
    // A liquidation bot would skip this candidate.
    try std.testing.expect(revert.isSkip(out.reverted.decoded));
}

test "simulateCall forwards state overrides to the call" {
    const alloc = std.testing.allocator;
    var mock = MockChainClient.init(alloc);
    defer mock.deinit();

    const sel = perp_abi.liquidate_taker_selector;
    try mock.setResponse(sel, &.{0x01});

    var overrides = eth.state_overrides.StateOverrides.init(alloc);
    defer overrides.deinit();
    // Simulate against a hypothetical margin/balance for the position holder.
    try overrides.setBalance(addr(0xAA), 1_000_000);

    var ctx = PerpCityContext.initWithClient(alloc, mock.client(), testDeployments());
    defer ctx.deinit();

    const out = try ctx.simulateCall(addr(0xBE), &sel, addr(0xAA), &overrides);
    defer out.deinit(alloc);
    try std.testing.expect(out == .ok);
    try std.testing.expect(mock.last_callraw_had_overrides);
}
