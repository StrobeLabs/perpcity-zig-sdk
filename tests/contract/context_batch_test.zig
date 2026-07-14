const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const chain_client = sdk.chain_client;
const ChainClient = chain_client.ChainClient;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;

const perp_abi = sdk.abi.perp_abi;
const fees_abi = sdk.abi.fees_abi;
const margin_ratios_abi = sdk.abi.margin_ratios_abi;

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
// Direct callBatch: selector-keyed lookups + missing selector -> success=false
// ---------------------------------------------------------------------------

test "callBatch resolves each call by selector and flags missing ones" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // Two registered selectors with distinct canned return bytes.
    try setReturn(&mock, perp_abi.open_interest_selector, &.{
        .{ .uint256 = 111 },
        .{ .uint256 = 222 },
    });
    try setReturn(&mock, perp_abi.capacity_selector, &.{
        .{ .uint256 = 333 },
        .{ .uint256 = 444 },
    });

    var client = mock.client();

    // No-arg calldata is just the 4-byte selector; the mock keys on those bytes,
    // so the target address is irrelevant. solvencyState() is left unregistered.
    const oi_data: []const u8 = &perp_abi.open_interest_selector;
    const cap_data: []const u8 = &perp_abi.capacity_selector;
    const missing_data: []const u8 = &perp_abi.solvency_state_selector;

    const calls = [_]ChainClient.BatchCall{
        .{ .to = addr(0x01), .data = oi_data },
        .{ .to = addr(0x02), .data = cap_data },
        .{ .to = addr(0x03), .data = missing_data },
    };

    const results = try client.callBatch(allocator, &calls);
    defer chain_client.freeBatchResults(results, allocator);

    try std.testing.expectEqual(@as(usize, 3), results.len);
    try std.testing.expect(results[0].success);
    try std.testing.expect(results[1].success);
    try std.testing.expect(!results[2].success);
    try std.testing.expectEqual(@as(usize, 0), results[2].bytes.len);

    // The successful entries decode back to their registered tuples.
    const oi_vals = try eth.abi_decode.decodeValues(results[0].bytes, &.{ .uint256, .uint256 }, allocator);
    defer eth.abi_decode.freeValues(oi_vals, allocator);
    try std.testing.expectEqual(@as(u256, 111), oi_vals[0].uint256);
    try std.testing.expectEqual(@as(u256, 222), oi_vals[1].uint256);

    const cap_vals = try eth.abi_decode.decodeValues(results[1].bytes, &.{ .uint256, .uint256 }, allocator);
    defer eth.abi_decode.freeValues(cap_vals, allocator);
    try std.testing.expectEqual(@as(u256, 333), cap_vals[0].uint256);
    try std.testing.expectEqual(@as(u256, 444), cap_vals[1].uint256);
}

// ---------------------------------------------------------------------------
// getPerpData now issues its five field reads as one batch. Assert the composite
// output field-for-field (the selector-keyed mock resolves each entry).
// ---------------------------------------------------------------------------

test "getPerpData composes fees, both bounds, mark, and beacon via callBatch" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const q96: u256 = @as(u256, 1) << 96;

    // modules(): beacon + five modules (served from the config cache read).
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
    // poolState(): (int256, uint256 sqrtPriceX96, uint256, uint256). sqrtPriceX96
    // = 2 * Q96 so the mark price is 4.0.
    try setReturn(&mock, perp_abi.pool_state_selector, &.{
        .{ .int256 = 0 },
        .{ .uint256 = 2 * q96 },
        .{ .uint256 = 0 },
        .{ .uint256 = 0 },
    });

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const data = try ctx.getPerpData(addr(0xBE));

    try std.testing.expectEqualSlices(u8, &addr(0xBE), &data.perp);
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

    // The batched read still seeds the mark-price cache.
    try expectApprox(4.0, try ctx.getMarkPriceCached(addr(0xBE)));
}

// ---------------------------------------------------------------------------
// A failed batch entry (unregistered selector) surfaces an error rather than
// decoding zero bytes into misleading zeros.
// ---------------------------------------------------------------------------

test "getPerpData errors when a batched read fails" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    // Register modules() and everything except poolState(), so the batch's last
    // entry comes back success=false.
    try setReturn(&mock, perp_abi.modules_selector, &.{
        .{ .address = addr(0xB0) },
        .{ .address = addr(0xB1) },
        .{ .address = addr(0xB2) },
        .{ .address = addr(0xB3) },
        .{ .address = addr(0xB4) },
        .{ .address = addr(0xB5) },
    });
    try setReturn(&mock, fees_abi.fees_selector, &.{
        .{ .uint256 = 10_000 },
        .{ .uint256 = 5_000 },
        .{ .uint256 = 3_000 },
    });
    try setReturn(&mock, fees_abi.liq_fee_selector, &.{.{ .uint256 = 20_000 }});
    try setReturn(&mock, margin_ratios_abi.taker_margin_ratios_selector, &.{
        .{ .uint256 = 100_000 },
        .{ .uint256 = 50_000 },
        .{ .uint256 = 20_000 },
    });
    try setReturn(&mock, margin_ratios_abi.maker_margin_ratios_selector, &.{
        .{ .uint256 = 200_000 },
        .{ .uint256 = 100_000 },
        .{ .uint256 = 40_000 },
    });
    // poolState() intentionally NOT registered.

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(error.BatchCallFailed, ctx.getPerpData(addr(0xBE)));
}
