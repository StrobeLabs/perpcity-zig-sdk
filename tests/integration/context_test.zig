const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// End-to-end test for the integration harness: spin up Anvil, deploy the mock
// stack, create a perp via the factory, and drive the SDK's v1.0.0 write and
// read paths against it. The mocks are compiled by solc from the v1.0.0 struct
// and event shapes, so a call only dispatches (and a log only decodes) when
// the SDK's hand-written signatures agree with the compiler's.

/// Wait for a write to be mined and require that it succeeded. The wrappers
/// that return only a tx hash do not wait, and a call whose selector the
/// contract does not recognise mines as a revert, so every write is checked.
fn mined(ctx: *sdk.context.PerpCityContext, tx_hash: types.Bytes32) !void {
    const receipt = (try ctx.client.getReceipt(ctx.allocator, tx_hash, 30)) orelse return error.ReceiptNotFound;
    try std.testing.expectEqual(@as(u8, 1), receipt.status);
}

test "v1.0.0 flow - create a perp, trade, liquidate, and read it all back" {
    if (skipIfAnvilUnavailable()) return error.SkipZigTest;

    // eth.zig's receipt-parsing path leaks small allocations, so use the C
    // allocator here rather than the leak-checking testing allocator.
    const allocator = std.heap.c_allocator;

    var harness: sdk.testing.setup.AnvilSetup = undefined;
    try harness.init(allocator, std.testing.io);
    defer harness.deinit();
    const ctx = &harness.context;
    const me = harness.deployerAddress();

    // --- createPerp: (owner, governor, modules, emaWindow, latency, salt, withdrawalConfig)
    const perp = try sdk.perp_factory.createPerp(ctx, .{
        .owner = me,
        .governor = me,
        .modules = harness.defaultModules(),
        .ema_window = 60,
        .latency = 3600,
        .salt = types.ZERO_BYTES32,
        .withdrawal_config = .{
            .capacity = 1_000_000_000,
            .refill_per_second = 1_000_000,
            .challenge_window = 86_400,
        },
    });

    const cfg = try ctx.getPerpConfig(perp);
    try std.testing.expectEqualSlices(u8, &harness.contracts.beacon, &cfg.modules.beacon);
    try std.testing.expectEqualSlices(u8, &harness.contracts.fees, &cfg.modules.fees);
    try std.testing.expectEqualSlices(u8, &harness.contracts.funding, &cfg.modules.funding);
    try std.testing.expectEqualSlices(u8, &harness.contracts.margin_ratios, &cfg.modules.margin_ratios);
    try std.testing.expectEqualSlices(u8, &harness.contracts.price_impact, &cfg.modules.price_impact);
    try std.testing.expectEqualSlices(u8, &harness.contracts.pricing, &cfg.modules.pricing);

    const controller = try ctx.getWithdrawalController(perp);
    try std.testing.expect(!std.mem.eql(u8, &controller, &types.ZERO_ADDRESS));

    // --- market reads: fees(liquidity, spots, emas), margin ratios, poolState
    const data = try ctx.getPerpData(perp);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), data.mark, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.001), data.fees.creator_fee, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0005), data.fees.insurance_fee, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.002), data.fees.lp_fee, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.005), data.fees.liquidation_fee, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0035), data.fees.max_swap_fee, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1), data.taker_bounds.init_margin_ratio, 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.05), data.taker_bounds.liq_margin_ratio, 1e-9);

    // --- beacon: index() returns (index, updatedAt)
    const obs = try ctx.getIndexObservation(cfg.modules.beacon);
    try std.testing.expectEqual(sdk.testing.mock_deployer.MOCK_BEACON_INITIAL_INDEX, obs.index);
    try std.testing.expect(obs.updated_at > 0);

    // --- openTaker: position id comes back from the indexed TakerOpened topic
    const taker = try sdk.perp_contract.openTaker(ctx, perp, .{
        .margin = 10.0,
        .perp_delta = 2_000_000,
        .amt1_limit = std.math.maxInt(u128),
    });
    try std.testing.expectEqual(@as(u256, 1), taker.position_id);
    try std.testing.expectEqualSlices(u8, &me, &(try ctx.getPositionOwner(perp, taker.position_id)));

    const raw = try ctx.getPositionRawData(perp, taker.position_id);
    try std.testing.expectEqual(@as(u128, 10_000_000), raw.margin);
    try std.testing.expectEqual(@as(i128, 2_000_000), sdk.position.perpDelta(raw));

    const preview = try taker.preview();
    try std.testing.expect(!preview.is_maker);
    try std.testing.expectEqual(@as(i256, 10_000_000), preview.equity);
    try std.testing.expect(preview.meets_initial_margin);
    try std.testing.expect(!preview.liquidatable);

    // --- adjustTaker: 7-field params incl. maxTotalFee / reduceOnly / deadline
    try mined(ctx, try taker.adjustTaker(.{
        .position_id = 0, // filled in by OpenPosition
        .margin_delta = 5_000_000,
        .perp_delta = 0,
        .amt1_limit = 0,
        .reduce_only = true,
    }));
    try std.testing.expectEqual(@as(u128, 15_000_000), (try ctx.getPositionRawData(perp, taker.position_id)).margin);

    // --- openMaker / moveMaker
    const maker = try sdk.perp_contract.openMaker(ctx, perp, .{
        .margin = 50.0,
        .price_lower = 0.5,
        .price_upper = 2.0,
        .liquidity = 1_000_000,
        .max_amt0_in = std.math.maxInt(u128),
        .max_amt1_in = std.math.maxInt(u128),
    });
    try std.testing.expectEqual(@as(u256, 2), maker.position_id);
    try std.testing.expect((try maker.preview()).is_maker);

    const before = try ctx.getMakerDetails(perp, maker.position_id);
    try std.testing.expectEqual(@as(u128, 1_000_000), before.liquidity);
    try std.testing.expect(before.tick_lower < 0 and before.tick_upper > 0);

    try mined(ctx, try maker.moveMaker(.{
        .position_id = 0,
        .tick_lower = -300,
        .tick_upper = 600,
        .liquidity = 750_000,
        .remove_amt0_min = 0,
        .remove_amt1_min = 0,
        .add_amt0_max = std.math.maxInt(u128),
        .add_amt1_max = std.math.maxInt(u128),
    }));
    const after = try ctx.getMakerDetails(perp, maker.position_id);
    try std.testing.expectEqual(@as(i32, -300), after.tick_lower);
    try std.testing.expectEqual(@as(i32, 600), after.tick_upper);
    try std.testing.expectEqual(@as(u128, 750_000), after.liquidity);

    // --- an expired deadline is rejected by the contract, and surfaces as an
    // error rather than a silently mined transaction
    try std.testing.expect(std.meta.isError(sdk.perp_contract.simulateBackstopTaker(ctx, perp, .{
        .position_id = taker.position_id,
        .margin_in = 1_000_000,
        .position_recipient = me,
        .deadline = 1,
    })));

    // --- backstopTaker reassigns the position (4-arg form with deadline)
    const rescuer: types.Address = @splat(0x5E);
    try mined(ctx, try taker.backstop(1_000_000, rescuer, types.NO_DEADLINE));
    try std.testing.expectEqualSlices(u8, &rescuer, &(try ctx.getPositionOwner(perp, taker.position_id)));

    // --- liquidations: 3-arg form; partial maker, then full taker
    try mined(ctx, try maker.liquidate(me, 250_000));
    try std.testing.expectEqual(@as(u128, 500_000), (try ctx.getMakerDetails(perp, maker.position_id)).liquidity);

    try mined(ctx, try taker.liquidate(me, 2_000_000));
    // A fully liquidated position has no owner, and previewPosition reverts.
    try std.testing.expectEqualSlices(u8, &types.ZERO_ADDRESS, &(try ctx.getPositionOwner(perp, taker.position_id)));
    try std.testing.expect(std.meta.isError(ctx.getPositionPreview(perp, taker.position_id)));

    // --- events: everything above, decoded from real logs
    const head = try ctx.eth_client.?.provider.getBlockNumber();
    const evs = try ctx.pollEvents(perp, 0, head);
    defer allocator.free(evs);

    var saw_taker_opened = false;
    var saw_maker_moved = false;
    var saw_maker_liquidated = false;
    var saw_taker_liquidated = false;
    var saw_taker_closed = false;
    var saw_backstop_reassign = false;
    for (evs) |ev| switch (ev) {
        .taker_opened => |e| {
            saw_taker_opened = true;
            try std.testing.expectEqual(@as(u256, 1), e.pos_id);
            try std.testing.expectEqualSlices(u8, &me, &e.owner);
            try std.testing.expectEqual(@as(u128, 10_000_000), e.margin);
            try std.testing.expectEqual(@as(i128, 2_000_000), sdk.position.unpackDelta(e.sr.delta).amount0);
        },
        .maker_moved => |e| {
            saw_maker_moved = true;
            try std.testing.expectEqual(@as(u256, 2), e.pos_id);
            try std.testing.expectEqual(@as(i24, -300), e.new_tick_lower);
            try std.testing.expectEqual(@as(i24, 600), e.new_tick_upper);
            try std.testing.expectEqual(@as(u128, 1_000_000), e.old_liquidity);
            try std.testing.expectEqual(@as(u128, 750_000), e.new_liquidity);
        },
        .maker_liquidated => |e| {
            saw_maker_liquidated = true;
            try std.testing.expectEqual(@as(u256, 2), e.pos_id);
            try std.testing.expectEqualSlices(u8, &me, &e.fee_recipient);
            try std.testing.expectEqual(@as(u128, 250_000), e.liquidity_amount);
        },
        .taker_liquidated => |e| {
            saw_taker_liquidated = true;
            try std.testing.expectEqual(@as(u256, 1), e.pos_id);
            try std.testing.expectEqual(@as(u128, 2_000_000), e.perp_amount);
        },
        .taker_closed => |e| {
            saw_taker_closed = true;
            try std.testing.expectEqualSlices(u8, &rescuer, &e.owner);
        },
        .position_owner_updated => |e| {
            if (e.pos_id == 1 and std.mem.eql(u8, &e.old_owner, &me) and std.mem.eql(u8, &e.new_owner, &rescuer)) {
                saw_backstop_reassign = true;
            }
        },
        else => {},
    };
    try std.testing.expect(saw_taker_opened);
    try std.testing.expect(saw_maker_moved);
    try std.testing.expect(saw_maker_liquidated);
    try std.testing.expect(saw_taker_liquidated);
    try std.testing.expect(saw_taker_closed);
    try std.testing.expect(saw_backstop_reassign);

    // --- discovery: the deployer still owns the maker; the liquidated taker
    // (and the backstopped-away ownership) are excluded
    const mine = try ctx.discoverOwnedPositions(perp, me, 0, head);
    defer allocator.free(mine);
    try std.testing.expectEqualSlices(u256, &[_]u256{2}, mine);
}

/// Returns true when the runtime environment isn't capable of starting Anvil
/// (binary missing, or its mock artifacts haven't been built). Lets a developer
/// `zig build integration-test` without Anvil installed and have the test skip
/// rather than hard-fail.
fn skipIfAnvilUnavailable() bool {
    const io = std.testing.io;

    // Anvil on PATH?
    var which = std.process.spawn(io, .{
        .argv = &.{ "anvil", "--version" },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return true;
    _ = which.wait(io) catch return true;

    // Mock artifacts present?
    std.Io.Dir.cwd().access(
        io,
        "tests/contracts/out/MockPerpFactory.sol/MockPerpFactory.json",
        .{},
    ) catch return true;

    return false;
}

test "getPerpConfig - caches results so second call is faster" {
    // First call hits chain, second call hits the cache.
    return error.SkipZigTest;
}

test "getPerpData - returns mark price approximately 1.0" {
    // Mock beacon initializes the perp with sqrtPriceX96 = 1<<96, so mark
    // should be close to 1.0.
    return error.SkipZigTest;
}

test "getPerpData - returns correct fee values from MockFees" {
    // MOCK_FEES_ARGS expectations:
    //   creator_fee  = 0.001  (1000 / 1e6)
    //   insurance_fee = 0.0005 (500 / 1e6)
    //   lp_fee       = 0.002  (2000 / 1e6)
    //   liquidation_fee = 0.005 (5000 / 1e6)
    return error.SkipZigTest;
}

test "getPerpData - taker bounds match MockMarginRatios" {
    // MOCK_MARGIN_RATIOS_ARGS expectations:
    //   init_taker = 0.1, liq_taker = 0.05, backstop_taker = 0.02
    return error.SkipZigTest;
}

test "getUserData - returns 1M USDC balance for the test account" {
    // After minting MINT_AMOUNT, fetchUsdcBalance must report 1e6 USDC.
    return error.SkipZigTest;
}

test "getPositionRawData - returns seeded position data" {
    // Open a taker on the mock perp, then read positions(pos_id). delta
    // should pack the params.perp_delta into amount0; margin should equal
    // the supplied margin.
    return error.SkipZigTest;
}

test "getOpenInterest / getCapacity - decode openInterest() and capacity()" {
    // Wire MockPerp.setOpenInterest/setCapacity, then verify the SDK reads
    // back the same (long, short) tuple.
    return error.SkipZigTest;
}

comptime {
    _ = &types.ZERO_ADDRESS;
}
