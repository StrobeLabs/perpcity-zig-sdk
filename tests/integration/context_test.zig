const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// All tests in this module are placeholders. They skip via `error.SkipZigTest`
// because they require a live Anvil node with the v0.1.0 mock stack deployed.

test "getPerpConfig - returns valid Modules tuple for the deployed perp" {
    // Verify that getPerpConfig reads `Perp.modules()` and returns the six
    // module addresses configured at factory deployment time.
    //
    //   var harness = try sdk.testing.setup.AnvilSetup.init(allocator, io);
    //   defer harness.deinit();
    //   const perp = try sdk.perp_factory.createPerp(&harness.context, params);
    //   const cfg = try harness.context.getPerpConfig(perp);
    //   try std.testing.expect(!std.mem.eql(u8, &cfg.modules.beacon, &types.ZERO_ADDRESS));
    //   try std.testing.expect(!std.mem.eql(u8, &cfg.modules.fees, &types.ZERO_ADDRESS));
    return error.SkipZigTest;
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
