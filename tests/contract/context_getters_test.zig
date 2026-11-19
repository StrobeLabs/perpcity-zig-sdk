const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;

const perp_abi = sdk.abi.perp_abi;
const beacon_abi = sdk.abi.beacon_abi;

const AbiValue = eth.abi_encode.AbiValue;

// ---------------------------------------------------------------------------
// Helpers (mirror contract/context_read_test.zig)
// ---------------------------------------------------------------------------

fn addr(b: u8) types.Address {
    return @as([20]u8, @splat(b));
}

fn testDeployments() types.PerpCityDeployments {
    return .{
        .perp_factory = addr(0x11),
        .module_registry = addr(0x22),
        .protocol_fee_manager = addr(0x33),
        .usdc = addr(0x44),
    };
}

/// ABI-encode `values` as the raw return tuple and register them for `selector`.
fn setReturn(mock: *MockChainClient, selector: [4]u8, values: []const AbiValue) !void {
    const bytes = try eth.abi_encode.encodeValues(std.testing.allocator, values);
    defer std.testing.allocator.free(bytes);
    try mock.setResponse(selector, bytes);
}

/// Register `return_values` for the exact call `selector(args)`, so the mock can
/// answer the same function differently per argument set.
fn setReturnCalldata(
    mock: *MockChainClient,
    selector: [4]u8,
    args: []const AbiValue,
    return_values: []const AbiValue,
) !void {
    const alloc = std.testing.allocator;
    const calldata = try eth.abi_encode.encodeFunctionCall(alloc, selector, args);
    defer alloc.free(calldata);
    const bytes = try eth.abi_encode.encodeValues(alloc, return_values);
    defer alloc.free(bytes);
    try mock.setResponseCalldata(calldata, bytes);
}

fn expectApprox(expected: f64, actual: f64) !void {
    try std.testing.expect(@abs(expected - actual) < 1e-6);
}

// ---------------------------------------------------------------------------
// getFundingRate -- rates()
// ---------------------------------------------------------------------------

test "getFundingRate decodes a positive fundingPerDay into percent rates" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // Rates: (int88 fundingPerDay, uint64 longUtil, uint64 shortUtil, uint40 lastTouch,
    // uint256 lastMark).
    // fundingPerDay = 5e16 (scaled 1e18/day) -> 0.05/day -> 5.0 percent/day.
    const raw: i256 = 50_000_000_000_000_000;
    try setReturn(&mock, perp_abi.rates_selector, &.{
        .{ .int256 = raw },
        .{ .uint256 = 1_000 },
        .{ .uint256 = 2_000 },
        .{ .uint256 = 1_700_000_000 },
        .{ .uint256 = 3 << 96 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const fr = try ctx.getFundingRate(addr(0xBE));
    try expectApprox(5.0, fr.rate_per_day);
    try expectApprox(5.0 / 1440.0, fr.rate_per_minute);
    try std.testing.expectEqual(raw, fr.funding_per_day_raw);
}

test "getFundingRate decodes a negative fundingPerDay" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // fundingPerDay = -3e16 -> -0.03/day -> -3.0 percent/day.
    const raw: i256 = -30_000_000_000_000_000;
    try setReturn(&mock, perp_abi.rates_selector, &.{
        .{ .int256 = raw },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const fr = try ctx.getFundingRate(addr(0xBE));
    try expectApprox(-3.0, fr.rate_per_day);
    try expectApprox(-3.0 / 1440.0, fr.rate_per_minute);
    try std.testing.expectEqual(raw, fr.funding_per_day_raw);
}

// ---------------------------------------------------------------------------
// getRates -- rates()
// ---------------------------------------------------------------------------

test "getRates decodes the full Rates struct including the cached mark" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const mark: u256 = 5 << 96;
    try setReturn(&mock, perp_abi.rates_selector, &.{
        .{ .int256 = -7 },
        .{ .uint256 = 1_000 },
        .{ .uint256 = 2_000 },
        .{ .uint256 = 1_700_000_000 },
        .{ .uint256 = mark },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const r = try ctx.getRates(addr(0xBE));
    try std.testing.expectEqual(@as(i256, -7), r.funding_per_day);
    try std.testing.expectEqual(@as(u64, 1_000), r.long_util_fee_per_day);
    try std.testing.expectEqual(@as(u64, 2_000), r.short_util_fee_per_day);
    try std.testing.expectEqual(@as(u64, 1_700_000_000), r.last_touch);
    try std.testing.expectEqual(mark, r.last_mark);
}

// ---------------------------------------------------------------------------
// getMakerDetails -- makerDetails(uint256)
// ---------------------------------------------------------------------------

test "getMakerDetails decodes the whole Maker struct" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // struct Maker is fully static, so it is encoded inline as leaf words:
    //   int24 tickLower, int24 tickUpper, uint128 liquidity,
    //   uint256 lastLpFeeGrowthInsideX128,
    //   MakerFunding(int256 belowX96, int256 withinInventoryX192),
    //   int256 lastFundingCorrectionX128
    try setReturn(&mock, perp_abi.maker_details_selector, &.{
        .{ .int256 = -60 }, // tickLower (signed)
        .{ .int256 = 120 }, // tickUpper
        .{ .uint256 = 1_000_000 }, // liquidity
        .{ .uint256 = 111 }, // lastLpFeeGrowthInsideX128
        .{ .int256 = -555 }, // lastCumlFunding.belowX96
        .{ .int256 = 666 }, // lastCumlFunding.withinInventoryX192
        .{ .int256 = -777 }, // lastFundingCorrectionX128
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const md = try ctx.getMakerDetails(addr(0xBE), 7);
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &md.perp);
    try std.testing.expectEqual(@as(u256, 7), md.position_id);
    try std.testing.expectEqual(@as(i32, -60), md.tick_lower);
    try std.testing.expectEqual(@as(i32, 120), md.tick_upper);
    try std.testing.expectEqual(@as(u128, 1_000_000), md.liquidity);
    try std.testing.expectEqual(@as(u256, 111), md.last_lp_fee_growth_inside_x128);
    try std.testing.expectEqual(@as(i256, -555), md.last_cuml_funding.below_x96);
    try std.testing.expectEqual(@as(i256, 666), md.last_cuml_funding.within_inventory_x192);
    try std.testing.expectEqual(@as(i256, -777), md.last_funding_correction_x128);
}

// ---------------------------------------------------------------------------
// getTakerDetails -- takerDetails(uint256)
// ---------------------------------------------------------------------------

test "getTakerDetails decodes the two util-payment checkpoints" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const total_x96: u256 = 123_456_789;
    const reserve_x96: u256 = 987_654_321;
    try setReturn(&mock, perp_abi.taker_details_selector, &.{
        .{ .uint256 = total_x96 },
        .{ .uint256 = reserve_x96 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const td = try ctx.getTakerDetails(addr(0xBE), 99);
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &td.perp);
    try std.testing.expectEqual(@as(u256, 99), td.position_id);
    try std.testing.expectEqual(total_x96, td.last_util_payments_x96);
    try std.testing.expectEqual(reserve_x96, td.last_reserve_util_payments_x96);
}

// ---------------------------------------------------------------------------
// getPositionOwner -- positionOwner(uint256)
// ---------------------------------------------------------------------------

test "getPositionOwner decodes the recorded owner of a live position" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const owner = addr(0xA1);
    try setReturn(&mock, perp_abi.position_owner_selector, &.{.{ .address = owner }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const got = try ctx.getPositionOwner(addr(0xBE), 42);
    try std.testing.expectEqualSlices(u8, &owner, &got);
}

test "getPositionOwner returns the zero address for a closed or never-opened id" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // positionOwner is a plain mapping getter: an inactive id reads as zero
    // rather than reverting.
    try setReturn(&mock, perp_abi.position_owner_selector, &.{.{ .address = types.ZERO_ADDRESS }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const got = try ctx.getPositionOwner(addr(0xBE), 999);
    try std.testing.expectEqualSlices(u8, &types.ZERO_ADDRESS, &got);
}

test "getPositionOwner returns distinct owners per pos_id via calldata-keyed responses" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // Same positionOwner(uint256) selector, different args -> different owners.
    // The calldata table lets the mock distinguish the two calls.
    const owner_a = addr(0xA1);
    const owner_b = addr(0xB2);
    try setReturnCalldata(&mock, perp_abi.position_owner_selector, &.{.{ .uint256 = 1 }}, &.{.{ .address = owner_a }});
    try setReturnCalldata(&mock, perp_abi.position_owner_selector, &.{.{ .uint256 = 2 }}, &.{.{ .address = owner_b }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const got_a = try ctx.getPositionOwner(addr(0xBE), 1);
    const got_b = try ctx.getPositionOwner(addr(0xBE), 2);
    try std.testing.expectEqualSlices(u8, &owner_a, &got_a);
    try std.testing.expectEqualSlices(u8, &owner_b, &got_b);
}

// ---------------------------------------------------------------------------
// getPositionPreview -- previewPosition(uint256)
// ---------------------------------------------------------------------------

test "getPositionPreview decodes every PositionPreview field in order" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // Distinct values per field so a transposed index fails; the three risk
    // flags are deliberately not all equal.
    try setReturn(&mock, perp_abi.preview_position_selector, &.{
        .{ .boolean = true }, // isMaker
        .{ .uint256 = 101 }, // markPrice
        .{ .int256 = -102 }, // settledMargin
        .{ .uint256 = 103 }, // pendingLpFees
        .{ .int256 = -104 }, // pendingFunding
        .{ .uint256 = 105 }, // pendingUtil
        .{ .uint256 = 106 }, // pendingReserveUtil
        .{ .uint256 = 107 }, // value
        .{ .int256 = -108 }, // unrealizedPnl
        .{ .int256 = -109 }, // equity
        .{ .boolean = false }, // meetsInitialMargin
        .{ .boolean = true }, // liquidatable
        .{ .boolean = false }, // backstoppable
        .{ .uint256 = 113 }, // nominalLiqFee
        .{ .uint256 = 114 }, // payableLiqFee
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const pv = try ctx.getPositionPreview(addr(0xBE), 17);
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &pv.perp);
    try std.testing.expectEqual(@as(u256, 17), pv.position_id);
    try std.testing.expectEqual(true, pv.is_maker);
    try std.testing.expectEqual(@as(u256, 101), pv.mark_price);
    try std.testing.expectEqual(@as(i256, -102), pv.settled_margin);
    try std.testing.expectEqual(@as(u256, 103), pv.pending_lp_fees);
    try std.testing.expectEqual(@as(i256, -104), pv.pending_funding);
    try std.testing.expectEqual(@as(u256, 105), pv.pending_util);
    try std.testing.expectEqual(@as(u256, 106), pv.pending_reserve_util);
    try std.testing.expectEqual(@as(u256, 107), pv.value);
    try std.testing.expectEqual(@as(i256, -108), pv.unrealized_pnl);
    try std.testing.expectEqual(@as(i256, -109), pv.equity);
    try std.testing.expectEqual(false, pv.meets_initial_margin);
    try std.testing.expectEqual(true, pv.liquidatable);
    try std.testing.expectEqual(false, pv.backstoppable);
    try std.testing.expectEqual(@as(u256, 113), pv.nominal_liq_fee);
    try std.testing.expectEqual(@as(u256, 114), pv.payable_liq_fee);
}

test "getPositionPreview surfaces the revert for an inactive position" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // No response registered: the mock stands in for the PositionDoesNotExist
    // revert previewPosition raises for an inactive id.
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(error.NoMockResponse, ctx.getPositionPreview(addr(0xBE), 999));
}

// ---------------------------------------------------------------------------
// getPhysicalCloseCapacity / getTvlState / getWithdrawalController
// ---------------------------------------------------------------------------

test "getPhysicalCloseCapacity decodes (longClose, shortClose)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.physical_close_capacity_selector, &.{
        .{ .uint256 = 8_000 },
        .{ .uint256 = 9_000 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const cap = try ctx.getPhysicalCloseCapacity(addr(0xBE));
    try std.testing.expectEqual(@as(u128, 8_000), cap.long_close);
    try std.testing.expectEqual(@as(u128, 9_000), cap.short_close);
}

test "getTvlState reads accountedTvl and tvlCap" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.accounted_tvl_selector, &.{.{ .uint256 = 750_000_000 }});
    try setReturn(&mock, perp_abi.tvl_cap_selector, &.{.{ .uint256 = 1_000_000_000 }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const tvl = try ctx.getTvlState(addr(0xBE));
    try std.testing.expectEqual(@as(u256, 750_000_000), tvl.tvl);
    try std.testing.expectEqual(@as(u256, 1_000_000_000), tvl.cap);
}

test "getWithdrawalController decodes the controller address" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.withdrawal_controller_selector, &.{.{ .address = addr(0xC7) }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const got = try ctx.getWithdrawalController(addr(0xBE));
    try std.testing.expectEqualSlices(u8, &addr(0xC7), &got);
}

test "withdrawal_controller.getClaim decodes a pending claim" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // claims(uint256): (originalAmount, currentAmount, recipient, createdAt, status, paused).
    try setReturn(&mock, sdk.abi.withdrawal_controller_abi.claims_selector, &.{
        .{ .uint256 = 5_000_000 },
        .{ .uint256 = 4_000_000 },
        .{ .address = addr(0x9A) },
        .{ .uint256 = 1_700_000_123 },
        .{ .uint256 = 1 },
        .{ .boolean = true },
    });
    try setReturn(&mock, sdk.abi.withdrawal_controller_abi.challenge_window_selector, &.{.{ .uint256 = 86_400 }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const claim = try sdk.withdrawal_controller.getClaim(&ctx, addr(0xC7), 3);
    try std.testing.expectEqual(@as(u128, 5_000_000), claim.original_amount);
    try std.testing.expectEqual(@as(u128, 4_000_000), claim.current_amount);
    try std.testing.expectEqualSlices(u8, &addr(0x9A), &claim.recipient);
    try std.testing.expectEqual(@as(u64, 1_700_000_123), claim.created_at);
    try std.testing.expectEqual(@backingInt(sdk.abi.withdrawal_controller_abi.ClaimStatus.pending), claim.status);
    try std.testing.expectEqual(true, claim.paused);

    try std.testing.expectEqual(@as(u64, 86_400), try sdk.withdrawal_controller.getChallengeWindow(&ctx, addr(0xC7)));
}

// ---------------------------------------------------------------------------
// getSolvencyState -- solvencyState()
// ---------------------------------------------------------------------------

test "getSolvencyState decodes (badDebt, totalMargin)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.solvency_state_selector, &.{
        .{ .uint256 = 4_200 },
        .{ .uint256 = 10_000_000 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const ss = try ctx.getSolvencyState(addr(0xBE));
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &ss.perp);
    try std.testing.expectEqual(@as(u128, 4_200), ss.bad_debt);
    try std.testing.expectEqual(@as(u128, 10_000_000), ss.total_margin);
}

// ---------------------------------------------------------------------------
// getFeeFund -- feeFund()
// ---------------------------------------------------------------------------

test "getFeeFund decodes (insurance, creatorFees, protocolFees) and widens uint80" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // insurance exceeds u64 to prove the u128 widening (uint80 range).
    const insurance: u128 = 1_000_000_000_000_000_000_000; // 1e21
    try setReturn(&mock, perp_abi.fee_fund_selector, &.{
        .{ .uint256 = insurance },
        .{ .uint256 = 2_000_000 },
        .{ .uint256 = 3_000_000 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const ff = try ctx.getFeeFund(addr(0xBE));
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &ff.perp);
    try std.testing.expectEqual(insurance, ff.insurance);
    try std.testing.expectEqual(@as(u128, 2_000_000), ff.creator_fees);
    try std.testing.expectEqual(@as(u128, 3_000_000), ff.protocol_fees);
}

// ---------------------------------------------------------------------------
// getIndexObservation / getIndexValue -- beacon index()
// ---------------------------------------------------------------------------

test "getIndexObservation decodes (index, updatedAt) from the beacon" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const index_val: u256 = 79_228_162_514_264_337_593_543_950_336; // Q96
    try setReturn(&mock, beacon_abi.index_selector, &.{
        .{ .uint256 = index_val },
        .{ .uint256 = 1_700_000_456 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const obs = try ctx.getIndexObservation(addr(0xB0));
    try std.testing.expectEqual(index_val, obs.index);
    try std.testing.expectEqual(@as(u64, 1_700_000_456), obs.updated_at);

    // getIndexValue is the index half of the same read.
    try std.testing.expectEqual(index_val, try ctx.getIndexValue(addr(0xB0)));
}

// ---------------------------------------------------------------------------
// getIndexTWAP -- beacon twAvg(uint32)
// ---------------------------------------------------------------------------

test "getIndexTWAP decodes a single uint256 for a given window" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const twap_val: u256 = 12_345_678_900_000;
    try setReturn(&mock, beacon_abi.tw_avg_selector, &.{.{ .uint256 = twap_val }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const twap = try ctx.getIndexTWAP(addr(0xB0), 3600);
    try std.testing.expectEqual(twap_val, twap);
}
