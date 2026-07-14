const std = @import("std");
const sdk = @import("perpcity_sdk");

const types = sdk.types;
const PerpCityContext = sdk.context.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
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

test "managed write assigns pipeline nonce+gas and bump resends at the same nonce" {
    const alloc = std.testing.allocator;
    var mock = MockChainClient.init(alloc);
    defer mock.deinit();

    var ctx = PerpCityContext.initWithClient(alloc, mock.client(), testDeployments());
    defer ctx.deinit();

    // Start at on-chain nonce 5; stuck after 1s.
    try ctx.enableManagedWrites(5, .{}, .{ .stuck_timeout_ms = 1000 });

    const liq_sel = perp_abi.liquidate_taker_selector;
    const request = sdk.context.TxRequest{
        .to = addr(0xBE),
        .calldata = &liq_sel,
        .gas_limit = 600_000,
        .urgency = .critical, // time-critical liquidation -> aggressive fees
    };

    // No base fee yet -> the pipeline cannot resolve gas.
    try std.testing.expectError(error.GasPriceUnavailable, ctx.sendManaged(request, 1000));

    // Feed a base fee, then send: nonce 5, explicit gas, non-zero fees.
    ctx.refreshBaseFee(100 * std.math.pow(u64, 10, 9), 1000); // 100 gwei
    mock.next_hash = [_]u8{0xA1} ** 32;
    const r1 = try ctx.sendManaged(request, 1000);
    try std.testing.expectEqual(@as(u64, 5), r1.nonce);

    const p1 = mock.last_managed.?;
    try std.testing.expectEqual(@as(u64, 5), p1.nonce);
    try std.testing.expectEqual(@as(u64, 600_000), p1.gas_limit);
    try std.testing.expect(p1.max_priority_fee_per_gas > 0);
    try std.testing.expect(p1.max_fee_per_gas > 0);

    // Not stuck yet at t=1500; stuck by t=2001 (>= 1000ms after submission).
    {
        const not_yet = try ctx.stuckWrites(1500);
        defer alloc.free(not_yet);
        try std.testing.expectEqual(@as(usize, 0), not_yet.len);
    }
    const stuck = try ctx.stuckWrites(2001);
    defer alloc.free(stuck);
    try std.testing.expectEqual(@as(usize, 1), stuck.len);
    try std.testing.expectEqualSlices(u8, &r1.tx_hash, &stuck[0]);

    // Bump-resend at 2x: same nonce, fees exactly doubled.
    mock.next_hash = [_]u8{0xB2} ** 32;
    const h2 = try ctx.resendBumped(request, r1.tx_hash, 2);
    try std.testing.expectEqualSlices(u8, &([_]u8{0xB2} ** 32), &h2);

    const p2 = mock.last_managed.?;
    try std.testing.expectEqual(@as(u64, 5), p2.nonce); // replacement reuses the nonce
    try std.testing.expectEqual(p1.max_priority_fee_per_gas * 2, p2.max_priority_fee_per_gas);
    try std.testing.expectEqual(p1.max_fee_per_gas * 2, p2.max_fee_per_gas);

    // Confirm the original: it leaves the in-flight set (a second bump errors).
    ctx.confirmWrite(r1.tx_hash);
    try std.testing.expectError(error.TxNotInFlight, ctx.resendBumped(request, r1.tx_hash, 2));
}

test "managed write APIs error before enable and enable is not repeatable" {
    const alloc = std.testing.allocator;
    var mock = MockChainClient.init(alloc);
    defer mock.deinit();

    var ctx = PerpCityContext.initWithClient(alloc, mock.client(), testDeployments());
    defer ctx.deinit();

    const request = sdk.context.TxRequest{ .to = addr(0xBE), .calldata = &.{}, .gas_limit = 100_000 };
    try std.testing.expectError(error.ManagedWritesNotEnabled, ctx.sendManaged(request, 0));
    try std.testing.expectError(error.ManagedWritesNotEnabled, ctx.stuckWrites(0));

    try ctx.enableManagedWrites(0, .{}, .{});
    try std.testing.expectError(error.ManagedWritesAlreadyEnabled, ctx.enableManagedWrites(0, .{}, .{}));
}
