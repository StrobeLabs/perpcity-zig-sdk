const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// =============================================================================
// PerpCityContext.getPerpConfig
// =============================================================================

test "getPerpConfig - returns valid config with correct module addresses" {
    // Verify that getPerpConfig fetches the on-chain PerpConfig for a given
    // perp ID, and that the returned config contains the expected module
    // addresses (fees, margin_ratios, lockup_period, sqrt_price_impact_limit).
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const perp_id = test_perp_id;
    // const config = try ctx.getPerpConfig(perp_id);
    //
    // try std.testing.expect(!std.mem.eql(u8, &config.vault, &types.ZERO_ADDRESS));
    // try std.testing.expect(!std.mem.eql(u8, &config.beacon, &types.ZERO_ADDRESS));
    // try std.testing.expect(!std.mem.eql(u8, &config.fees, &types.ZERO_ADDRESS));
    // try std.testing.expect(!std.mem.eql(u8, &config.margin_ratios, &types.ZERO_ADDRESS));
    // try std.testing.expect(!std.mem.eql(u8, &config.lockup_period, &types.ZERO_ADDRESS));
    // try std.testing.expect(!std.mem.eql(u8, &config.sqrt_price_impact_limit, &types.ZERO_ADDRESS));
    return error.SkipZigTest;
}

test "getPerpConfig - caches results so second call is faster" {
    // Verify that the config cache works correctly: the first call fetches
    // from chain and populates the cache; the second call returns the cached
    // value without an RPC round-trip.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const perp_id = test_perp_id;
    //
    // const timer = try std.time.Timer.start();
    // const config1 = try ctx.getPerpConfig(perp_id);
    // const first_duration = timer.read();
    //
    // timer.reset();
    // const config2 = try ctx.getPerpConfig(perp_id);
    // const second_duration = timer.read();
    //
    // // Cached call should be significantly faster (no RPC)
    // try std.testing.expect(second_duration < first_duration);
    // try std.testing.expectEqual(config1.key.fee, config2.key.fee);
    // try std.testing.expectEqual(config1.key.tick_spacing, config2.key.tick_spacing);
    return error.SkipZigTest;
}

// =============================================================================
// PerpCityContext.getPerpData
// =============================================================================

test "getPerpData - returns mark price approximately 1.0" {
    // Verify that the mark price returned by getPerpData is approximately 1.0
    // for the test perp that was seeded with a starting price of 1.0.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const perp_data = try ctx.getPerpData(test_perp_id);
    //
    // // Mark price should be close to 1.0 (the starting price)
    // try std.testing.expectApproxEqAbs(@as(f64, 1.0), perp_data.mark, 0.01);
    return error.SkipZigTest;
}

test "getPerpData - returns correct fee values" {
    // Verify that getPerpData returns the fee configuration that matches
    // the mock contract deployment:
    //   creator_fee  = 0.001 (0.1%)
    //   insurance_fee = 0.0005 (0.05%)
    //   lp_fee       = 0.002 (0.2%)
    //   liquidation_fee = 0.005 (0.5%)
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const perp_data = try ctx.getPerpData(test_perp_id);
    //
    // try std.testing.expectApproxEqAbs(@as(f64, 0.001), perp_data.fees.creator_fee, 0.0001);
    // try std.testing.expectApproxEqAbs(@as(f64, 0.0005), perp_data.fees.insurance_fee, 0.0001);
    // try std.testing.expectApproxEqAbs(@as(f64, 0.002), perp_data.fees.lp_fee, 0.0001);
    // try std.testing.expectApproxEqAbs(@as(f64, 0.005), perp_data.fees.liquidation_fee, 0.0001);
    return error.SkipZigTest;
}

test "getPerpData - returns correct leverage bounds" {
    // Verify that the bounds returned by getPerpData have sensible values:
    //   min_taker_leverage > 0
    //   max_taker_leverage > min_taker_leverage
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const perp_data = try ctx.getPerpData(test_perp_id);
    //
    // try std.testing.expect(perp_data.bounds.min_taker_leverage > 0.0);
    // try std.testing.expect(perp_data.bounds.max_taker_leverage > perp_data.bounds.min_taker_leverage);
    // try std.testing.expect(perp_data.bounds.min_margin > 0.0);
    // try std.testing.expect(perp_data.bounds.liquidation_taker_ratio > 0.0);
    return error.SkipZigTest;
}

// =============================================================================
// PerpCityContext.getUserData
// =============================================================================

test "getUserData - returns 1M USDC balance for test account" {
    // Verify that the test account (which was seeded with 1,000,000 USDC
    // by the Anvil setup script) reports the correct balance.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const user_data = try ctx.getUserData(test_wallet_address, &.{});
    // defer std.testing.allocator.free(user_data.open_positions);
    //
    // try std.testing.expectApproxEqAbs(@as(f64, 1_000_000.0), user_data.usdc_balance, 0.01);
    return error.SkipZigTest;
}

test "getUserData - returns empty positions for new account" {
    // Verify that a freshly seeded test account with no open positions
    // returns an empty open_positions slice.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const user_data = try ctx.getUserData(test_wallet_address, &.{});
    // defer std.testing.allocator.free(user_data.open_positions);
    //
    // try std.testing.expectEqual(@as(usize, 0), user_data.open_positions.len);
    // try std.testing.expect(std.mem.eql(u8, &user_data.wallet_address, &test_wallet_address));
    return error.SkipZigTest;
}

// =============================================================================
// PerpCityContext.getPositionRawData
// =============================================================================

test "getPositionRawData - returns seeded position data" {
    // Verify that getPositionRawData correctly reads raw on-chain position
    // data for a position that was opened during test setup. The returned
    // PositionRawData should have non-zero margin and entry deltas.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // // First open a position to get a valid position ID
    // const position = try sdk.perp_manager.openTakerPosition(&ctx, test_perp_id, .{
    //     .is_long = true,
    //     .margin = 10.0,
    //     .leverage = 2.0,
    //     .unspecified_amount_limit = 0,
    // });
    //
    // const raw = try ctx.getPositionRawData(position.position_id);
    //
    // try std.testing.expect(raw.margin > 0.0);
    // try std.testing.expect(raw.entry_perp_delta != 0);
    // try std.testing.expect(raw.entry_usd_delta != 0);
    // try std.testing.expect(raw.position_id == position.position_id);
    return error.SkipZigTest;
}

// =============================================================================
// PerpCityContext.getOpenPositionData
// =============================================================================

test "getOpenPositionData - returns live details with pnl, funding, and margin" {
    // Verify that getOpenPositionData returns meaningful live details for
    // an existing position: PnL should be a finite number, funding_payment
    // should be finite, and effective_margin should be positive.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // // Open a position first
    // const position = try sdk.perp_manager.openTakerPosition(&ctx, test_perp_id, .{
    //     .is_long = true,
    //     .margin = 10.0,
    //     .leverage = 2.0,
    //     .unspecified_amount_limit = 0,
    // });
    //
    // const open_data = try ctx.getOpenPositionData(
    //     test_perp_id,
    //     position.position_id,
    //     true,
    //     false,
    // );
    //
    // try std.testing.expect(!std.math.isNan(open_data.live_details.pnl));
    // try std.testing.expect(!std.math.isNan(open_data.live_details.funding_payment));
    // try std.testing.expect(open_data.live_details.effective_margin > 0.0);
    // try std.testing.expectEqual(true, open_data.is_long.?);
    // try std.testing.expectEqual(false, open_data.is_maker.?);
    return error.SkipZigTest;
}
