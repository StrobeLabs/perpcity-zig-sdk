const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// Smoke test for the integration harness: spin up Anvil, deploy the v0.1.0
// mock stack, create a perp via the factory, and read its `modules()` back.
// All other tests in this module are placeholders pending future work.

test "getPerpConfig - returns valid Modules tuple for the deployed perp" {
    if (skipIfAnvilUnavailable()) return error.SkipZigTest;

    // eth.zig 0.3.0's keccak FFI requires 8-byte aligned buffers, and its
    // receipt-parsing path leaks small allocations. Use the C allocator
    // (8-byte aligned via malloc) so keccak doesn't segfault on aarch64, and
    // accept that we won't catch eth.zig-internal leaks here.
    const allocator = std.heap.c_allocator;

    var harness: sdk.testing.setup.AnvilSetup = undefined;
    try harness.init(allocator);
    defer harness.deinit();

    const perp = try sdk.perp_factory.createPerp(&harness.context, .{
        .owner = harness.deployerAddress(),
        .name = "ETH-PERP",
        .symbol = "ETHP",
        .token_uri = "",
        .modules = harness.defaultModules(),
        .ema_window = 60,
        .salt = types.ZERO_BYTES32,
    });

    const cfg = try harness.context.getPerpConfig(perp);
    try std.testing.expect(!std.mem.eql(u8, &cfg.modules.beacon, &types.ZERO_ADDRESS));
    try std.testing.expect(!std.mem.eql(u8, &cfg.modules.fees, &types.ZERO_ADDRESS));
    try std.testing.expect(!std.mem.eql(u8, &cfg.modules.funding, &types.ZERO_ADDRESS));
    try std.testing.expect(!std.mem.eql(u8, &cfg.modules.margin_ratios, &types.ZERO_ADDRESS));
    try std.testing.expect(!std.mem.eql(u8, &cfg.modules.price_impact, &types.ZERO_ADDRESS));
    try std.testing.expect(!std.mem.eql(u8, &cfg.modules.pricing, &types.ZERO_ADDRESS));
}

/// Returns true when the runtime environment isn't capable of starting Anvil
/// (binary missing, or its mock artifacts haven't been built). Lets a developer
/// `zig build integration-test` without Anvil installed and have the test skip
/// rather than hard-fail.
fn skipIfAnvilUnavailable() bool {
    // Anvil on PATH?
    var which = std.process.Child.init(&.{ "anvil", "--version" }, std.testing.allocator);
    which.stdout_behavior = .Ignore;
    which.stderr_behavior = .Ignore;
    which.spawn() catch return true;
    _ = which.wait() catch return true;

    // Mock artifacts present?
    std.fs.cwd().access(
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
