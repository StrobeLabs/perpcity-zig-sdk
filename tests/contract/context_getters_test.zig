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

/// ABI-encode `values` as the raw return tuple and register them for `selector`.
fn setReturn(mock: *MockChainClient, selector: [4]u8, values: []const AbiValue) !void {
    const bytes = try eth.abi_encode.encodeValues(std.testing.allocator, values);
    defer std.testing.allocator.free(bytes);
    try mock.setResponse(selector, bytes);
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

    // Rates: (int88 fundingPerDay, uint64 longUtil, uint64 shortUtil, uint40 lastTouch).
    // fundingPerDay = 5e16 (scaled 1e18/day) -> 0.05/day -> 5.0 percent/day.
    const raw: i256 = 50_000_000_000_000_000;
    try setReturn(&mock, perp_abi.rates_selector, &.{
        .{ .int256 = raw },
        .{ .uint256 = 1_000 },
        .{ .uint256 = 2_000 },
        .{ .uint256 = 1_700_000_000 },
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
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const fr = try ctx.getFundingRate(addr(0xBE));
    try expectApprox(-3.0, fr.rate_per_day);
    try expectApprox(-3.0 / 1440.0, fr.rate_per_minute);
    try std.testing.expectEqual(raw, fr.funding_per_day_raw);
}

// ---------------------------------------------------------------------------
// getMakerDetails -- makerDetails(uint256)
// ---------------------------------------------------------------------------

test "getMakerDetails decodes the tick range and liquidity, ignoring trailing fields" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // Faithful v0.1.0 Maker return: all fields are static, so the struct is
    // encoded inline as a flat sequence of leaf words. Encode the full struct so
    // the decoder must correctly stop after the leading three fields.
    //   int24 tickLower, int24 tickUpper, uint128 liquidity,
    //   uint256 lastLongUtilEarningsX96, uint256 lastShortUtilEarningsX96,
    //   Capacity(uint128 long, uint128 short),
    //   MakerFunding(int256 belowX96, int256 withinX96, int256 divSqrtPriceWithinX96)
    try setReturn(&mock, perp_abi.maker_details_selector, &.{
        .{ .int256 = -60 }, // tickLower (signed)
        .{ .int256 = 120 }, // tickUpper
        .{ .uint256 = 1_000_000 }, // liquidity
        .{ .uint256 = 111 }, // lastLongUtilEarningsX96 (ignored)
        .{ .uint256 = 222 }, // lastShortUtilEarningsX96 (ignored)
        .{ .uint256 = 333 }, // capacity.long (ignored)
        .{ .uint256 = 444 }, // capacity.short (ignored)
        .{ .int256 = -555 }, // lastCumlFunding.belowX96 (ignored)
        .{ .int256 = 666 }, // lastCumlFunding.withinX96 (ignored)
        .{ .int256 = -777 }, // lastCumlFunding.divSqrtPriceWithinX96 (ignored)
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const md = try ctx.getMakerDetails(addr(0xBE), 7);
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &md.perp);
    try std.testing.expectEqual(@as(u256, 7), md.position_id);
    try std.testing.expectEqual(@as(i32, -60), md.tick_lower);
    try std.testing.expectEqual(@as(i32, 120), md.tick_upper);
    try std.testing.expectEqual(@as(u128, 1_000_000), md.liquidity);
}

// ---------------------------------------------------------------------------
// getTakerDetails -- takerDetails(uint256)
// ---------------------------------------------------------------------------

test "getTakerDetails decodes the two util-payment checkpoints" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const long_x96: u256 = 123_456_789;
    const short_x96: u256 = 987_654_321;
    try setReturn(&mock, perp_abi.taker_details_selector, &.{
        .{ .uint256 = long_x96 },
        .{ .uint256 = short_x96 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const td = try ctx.getTakerDetails(addr(0xBE), 99);
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &td.perp);
    try std.testing.expectEqual(@as(u256, 99), td.position_id);
    try std.testing.expectEqual(long_x96, td.last_long_util_payments_x96);
    try std.testing.expectEqual(short_x96, td.last_short_util_payments_x96);
}

// ---------------------------------------------------------------------------
// getPositionOwner / getPositionBalance -- ERC721 ownerOf(uint256) / balanceOf(address)
// ---------------------------------------------------------------------------

test "getPositionOwner decodes the ERC721 owner of a live position" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const owner = addr(0xA1);
    try setReturn(&mock, perp_abi.owner_of_selector, &.{.{ .address = owner }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const got = try ctx.getPositionOwner(addr(0xBE), 42);
    try std.testing.expectEqualSlices(u8, &owner, &got);
}

test "getPositionOwner surfaces the revert for a closed/nonexistent position" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // No ownerOf response registered: the mock stands in for a reverting call,
    // as Solady ERC721 ownerOf reverts for a never-minted or burned token.
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(error.NoMockResponse, ctx.getPositionOwner(addr(0xBE), 999));
}

test "getPositionBalance decodes the ERC721 position count for an owner" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.balance_of_selector, &.{.{ .uint256 = 3 }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const n = try ctx.getPositionBalance(addr(0xBE), addr(0xA1));
    try std.testing.expectEqual(@as(u256, 3), n);
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
// getIndexValue -- beacon index()
// ---------------------------------------------------------------------------

test "getIndexValue decodes a single uint256 from the beacon" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const index_val: u256 = 79_228_162_514_264_337_593_543_950_336; // ~Q96
    try setReturn(&mock, beacon_abi.index_selector, &.{.{ .uint256 = index_val }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const idx = try ctx.getIndexValue(addr(0xB0));
    try std.testing.expectEqual(index_val, idx);
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
