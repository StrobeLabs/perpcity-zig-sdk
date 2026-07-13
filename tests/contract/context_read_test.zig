const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const chain_client = sdk.chain_client;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const PerpPositionId = context_mod.PerpPositionId;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const perp_contract = sdk.perp_contract;
const perp_factory = sdk.perp_factory;

const perp_abi = sdk.abi.perp_abi;
const fees_abi = sdk.abi.fees_abi;
const margin_ratios_abi = sdk.abi.margin_ratios_abi;
const erc20_abi = sdk.abi.erc20_abi;
const perp_factory_abi = sdk.abi.perp_factory_abi;

const AbiValue = eth.abi_encode.AbiValue;

// ---------------------------------------------------------------------------
// Helpers
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
// getPerpConfig / fetchPerpConfigFromChain -- modules()
// ---------------------------------------------------------------------------

test "getPerpConfig decodes modules() into the six module addresses" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.modules_selector, &.{
        .{ .address = addr(0xA1) },
        .{ .address = addr(0xA2) },
        .{ .address = addr(0xA3) },
        .{ .address = addr(0xA4) },
        .{ .address = addr(0xA5) },
        .{ .address = addr(0xA6) },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const cfg = try ctx.getPerpConfig(addr(0xEE));
    try std.testing.expectEqualSlices(u8, &addr(0xA1), &cfg.modules.beacon);
    try std.testing.expectEqualSlices(u8, &addr(0xA2), &cfg.modules.fees);
    try std.testing.expectEqualSlices(u8, &addr(0xA3), &cfg.modules.funding);
    try std.testing.expectEqualSlices(u8, &addr(0xA4), &cfg.modules.margin_ratios);
    try std.testing.expectEqualSlices(u8, &addr(0xA5), &cfg.modules.price_impact);
    try std.testing.expectEqualSlices(u8, &addr(0xA6), &cfg.modules.pricing);
    try std.testing.expectEqualSlices(u8, &addr(0xEE), &cfg.perp);
}

test "getPerpConfig with no mock response surfaces NoMockResponse" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(MockChainClient.MockError.NoMockResponse, ctx.getPerpConfig(addr(0xEE)));
}

// ---------------------------------------------------------------------------
// getPositionRawData -- positions()
// ---------------------------------------------------------------------------

test "getPositionRawData decodes the positions() tuple" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // (int256 delta, uint128 margin, uint24 liq, uint24 backstop, int256 lastFunding)
    try setReturn(&mock, perp_abi.positions_selector, &.{
        .{ .int256 = 123_456_789 },
        .{ .uint256 = 5_000_000 },
        .{ .uint256 = 50_000 },
        .{ .uint256 = 20_000 },
        .{ .int256 = -777 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const raw = try ctx.getPositionRawData(addr(0xBE), 42);
    try std.testing.expectEqualSlices(u8, &addr(0xBE), &raw.perp);
    try std.testing.expectEqual(@as(u256, 42), raw.position_id);
    try std.testing.expectEqual(@as(i256, 123_456_789), raw.delta);
    try std.testing.expectEqual(@as(u128, 5_000_000), raw.margin);
    try std.testing.expectEqual(@as(u24, 50_000), raw.liq_margin_ratio);
    try std.testing.expectEqual(@as(u24, 20_000), raw.backstop_margin_ratio);
    try std.testing.expectEqual(@as(i256, -777), raw.last_cuml_funding_x96);
}

// ---------------------------------------------------------------------------
// getOpenInterest / getCapacity
// ---------------------------------------------------------------------------

test "getOpenInterest decodes (long, short)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.open_interest_selector, &.{
        .{ .uint256 = 1_000 },
        .{ .uint256 = 500 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const oi = try ctx.getOpenInterest(addr(0xBE));
    try std.testing.expectEqual(@as(u128, 1_000), oi.long);
    try std.testing.expectEqual(@as(u128, 500), oi.short);
}

test "getCapacity decodes (long, short)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_abi.capacity_selector, &.{
        .{ .uint256 = 9_000_000 },
        .{ .uint256 = 8_000_000 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const cap = try ctx.getCapacity(addr(0xBE));
    try std.testing.expectEqual(@as(u128, 9_000_000), cap.long);
    try std.testing.expectEqual(@as(u128, 8_000_000), cap.short);
}

// ---------------------------------------------------------------------------
// getPerpData -- fetchFees + taker/maker bounds + fetchMarkPrice
// ---------------------------------------------------------------------------

test "getPerpData wires fees, both bounds, and mark price" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const q96: u256 = @as(u256, 1) << 96;

    // modules(): beacon + five modules. The mock keys on the selector only, so
    // each downstream read (fees/margin/pool) resolves regardless of target.
    try setReturn(&mock, perp_abi.modules_selector, &.{
        .{ .address = addr(0xB0) }, // beacon
        .{ .address = addr(0xB1) }, // fees
        .{ .address = addr(0xB2) }, // funding
        .{ .address = addr(0xB3) }, // marginRatios
        .{ .address = addr(0xB4) }, // priceImpact
        .{ .address = addr(0xB5) }, // pricing
    });
    // fees(): (creator, insurance, lp) scaled by 1e6.
    try setReturn(&mock, fees_abi.fees_selector, &.{
        .{ .uint256 = 10_000 },
        .{ .uint256 = 5_000 },
        .{ .uint256 = 3_000 },
    });
    // liqFee()
    try setReturn(&mock, fees_abi.liq_fee_selector, &.{.{ .uint256 = 20_000 }});
    // takerMarginRatios(): (init, liq, backstop) scaled by 1e6.
    try setReturn(&mock, margin_ratios_abi.taker_margin_ratios_selector, &.{
        .{ .uint256 = 100_000 },
        .{ .uint256 = 50_000 },
        .{ .uint256 = 20_000 },
    });
    // makerMarginRatios()
    try setReturn(&mock, margin_ratios_abi.maker_margin_ratios_selector, &.{
        .{ .uint256 = 200_000 },
        .{ .uint256 = 100_000 },
        .{ .uint256 = 40_000 },
    });
    // poolState(): (int256, uint256 sqrtPriceX96, uint256, uint256). Choose
    // sqrtPriceX96 = 2 * Q96 so the price is 4.0.
    try setReturn(&mock, perp_abi.pool_state_selector, &.{
        .{ .int256 = 0 },
        .{ .uint256 = 2 * q96 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const data = try ctx.getPerpData(addr(0xBE));

    try std.testing.expectEqualSlices(u8, &addr(0xB0), &data.beacon);

    try expectApprox(0.01, data.fees.creator_fee);
    try expectApprox(0.005, data.fees.insurance_fee);
    try expectApprox(0.003, data.fees.lp_fee);
    try expectApprox(0.02, data.fees.liquidation_fee);

    try expectApprox(0.1, data.taker_bounds.init_margin_ratio);
    try expectApprox(0.05, data.taker_bounds.liq_margin_ratio);
    try expectApprox(0.02, data.taker_bounds.backstop_margin_ratio);
    try expectApprox(10.0, data.taker_bounds.max_leverage);

    try expectApprox(0.2, data.maker_bounds.init_margin_ratio);
    try expectApprox(0.1, data.maker_bounds.liq_margin_ratio);
    try expectApprox(0.04, data.maker_bounds.backstop_margin_ratio);
    try expectApprox(5.0, data.maker_bounds.max_leverage);

    try expectApprox(4.0, data.mark);
}

// ---------------------------------------------------------------------------
// getMarkPriceCached -- fetchMarkPrice with a chosen sqrtPriceX96
// ---------------------------------------------------------------------------

test "getMarkPriceCached decodes poolState() sqrtPriceX96 into a price" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // sqrtPriceX96 = Q96 -> price 1.0.
    const q96: u256 = @as(u256, 1) << 96;
    try setReturn(&mock, perp_abi.pool_state_selector, &.{
        .{ .int256 = 0 },
        .{ .uint256 = q96 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const mark = try ctx.getMarkPriceCached(addr(0xBE));
    try expectApprox(1.0, mark);
}

// ---------------------------------------------------------------------------
// fetchUsdcBalance (via getUserData with no positions)
// ---------------------------------------------------------------------------

test "getUserData decodes the USDC balance" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // balanceOf() -> 12_345_678 raw (6 decimals) = 12.345678 USDC.
    try setReturn(&mock, erc20_abi.balance_of_selector, &.{.{ .uint256 = 12_345_678 }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const empty: []const PerpPositionId = &.{};
    const ud = try ctx.getUserData(addr(0x55), empty);
    defer allocator.free(ud.open_positions);

    try std.testing.expectEqualSlices(u8, &addr(0x55), &ud.wallet_address);
    try expectApprox(12.345678, ud.usdc_balance);
    try std.testing.expectEqual(@as(usize, 0), ud.open_positions.len);
}

// ---------------------------------------------------------------------------
// perp_factory.isPerp
// ---------------------------------------------------------------------------

test "perp_factory.isPerp decodes the bool" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    try setReturn(&mock, perp_factory_abi.perps_selector, &.{.{ .boolean = true }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expect(try perp_factory.isPerp(&ctx, addr(0xBE)));
}

// ---------------------------------------------------------------------------
// setupForTrading -- reads allowance + signer address through the seam
// ---------------------------------------------------------------------------

test "setupForTrading skips approval when allowance is already high" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // allowance() returns max, so setupForTrading records the perp without a
    // write (approveUsdcMax would need a receipt, which the mock leaves null).
    try setReturn(&mock, erc20_abi.allowance_selector, &.{.{ .uint256 = std.math.maxInt(u256) }});

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    try ctx.setupForTrading(perp);
    try std.testing.expect(ctx.approved_perps.contains(perp));
    try std.testing.expectEqual(@as(usize, 0), mock.sent.items.len);
}

// ---------------------------------------------------------------------------
// Write seam sanity: writeContract records a sent tx on the mock
// ---------------------------------------------------------------------------

test "writeContract routes through the mock and records the tx" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const tx_hash = try perp_contract.touch(&ctx, perp);

    try std.testing.expectEqualSlices(u8, &mock.next_hash, &tx_hash);
    try std.testing.expectEqual(@as(usize, 1), mock.sent.items.len);
    try std.testing.expectEqualSlices(u8, &perp, &mock.sent.items[0].to);
    try std.testing.expectEqual(@as(u256, 0), mock.sent.items[0].value);
    try std.testing.expectEqualSlices(u8, &perp_abi.touch_selector, mock.sent.items[0].data[0..4]);
}
