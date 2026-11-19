const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// All tests in this module are placeholders. They skip via `error.SkipZigTest`
// because they require a live Anvil node with the mock stack deployed.

test "createPerp via factory returns a new perp address" {
    // Covered end-to-end by the v1.0.0 flow test in context_test.zig.
    return error.SkipZigTest;
}

test "openTaker - long position has positive perp_delta" {
    // Calling openTaker with a positive perp_delta should mint a position
    // whose `positions(...)` returns a delta with amount0 > 0.
    //
    //   const pos = try sdk.perp_contract.openTaker(&ctx, perp, .{
    //       .margin = 10.0,
    //       .perp_delta = 1_000_000,
    //       .amt1_limit = 0,
    //   });
    //   try std.testing.expect(pos.position_id > 0);
    //   try std.testing.expectEqual(false, pos.is_maker);
    return error.SkipZigTest;
}

test "openTaker - short position has negative perp_delta" {
    // Same flow but with negative `perp_delta`.
    return error.SkipZigTest;
}

test "openTaker - rejects zero margin" {
    // Should return error.MarginMustBePositive without submitting a tx.
    return error.SkipZigTest;
}

test "openTaker - rejects zero perp_delta" {
    // Should return error.PerpDeltaMustBeNonZero.
    return error.SkipZigTest;
}

test "openMaker - valid range opens a maker position" {
    // openMaker should succeed for a price range [price_lower, price_upper]
    // with positive liquidity. The returned OpenPosition.is_maker is true.
    return error.SkipZigTest;
}

test "openMaker - rejects inverted prices" {
    // price_lower >= price_upper should return error.InvalidPriceRange.
    return error.SkipZigTest;
}

test "adjustTaker - increases margin" {
    // adjustTaker with a positive margin_delta should succeed and the
    // resulting margin should be the previous margin + delta.
    return error.SkipZigTest;
}

test "liquidateMaker / backstopMaker - dispatch from OpenPosition" {
    // OpenPosition.liquidate routes through the maker or taker variant based
    // on is_maker. OpenPosition.backstop routes the same way.
    return error.SkipZigTest;
}

test "opened taker has a valid tx_hash" {
    // The returned OpenPosition.tx_hash is non-null and non-zero.
    return error.SkipZigTest;
}

comptime {
    _ = &types.ZERO_BYTES32;
}
