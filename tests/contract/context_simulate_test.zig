// Preflight (simulate-before-send) unit tests for the contract layer, driven
// through the ChainClient seam with an in-memory mock (no network / Anvil).
//
// The `simulate<Op>` wrappers are the opt-in revert preflight: they encode the
// SAME calldata as the matching write wrapper and run it through eth_call
// (`ChainClient.call`) instead of `sendTransaction`, so a caller learns a tx
// would revert without spending gas or burning a nonce.
//
// The mock resolves `call` by the 4-byte selector: a registered response means
// "would not revert" (simulate returns normally); a missing selector surfaces
// as `MockError.NoMockResponse`, standing in for the revert-preflight path
// (simulate propagates the error). No transaction is ever recorded -- each test
// asserts `mock.lastSent()` stays null, proving the preflight never sends.
const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const chain_client = sdk.chain_client;
const mock_chain_client = sdk.testing.mock_chain_client;
const MockChainClient = mock_chain_client.MockChainClient;
const NoMockResponse = MockChainClient.MockError.NoMockResponse;
const perp_contract = sdk.perp_contract;
const perp_factory = sdk.perp_factory;
const approve = sdk.approve;

const perp_abi = sdk.abi.perp_abi;
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

/// A non-empty canned eth_call return; any registered response marks the
/// selector as "would not revert" for the preflight.
const ok_return = [_]u8{0} ** 32;

// ---------------------------------------------------------------------------
// Direct chain_client.simulateContract
// ---------------------------------------------------------------------------

test "simulateContract returns normally when the call would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const sel = [4]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    try mock.setResponse(sel, &ok_return);

    try chain_client.simulateContract(&ctx.client, allocator, addr(0xBE), sel, &.{});

    // A preflight never sends a transaction.
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateContract propagates the error when the call would revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    // No response registered -> the mock's `call` errors, standing in for a revert.
    const sel = [4]u8{ 0x01, 0x02, 0x03, 0x04 };
    try std.testing.expectError(
        NoMockResponse,
        chain_client.simulateContract(&ctx.client, allocator, addr(0xBE), sel, &.{}),
    );
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

// ---------------------------------------------------------------------------
// simulateOpenTaker
// ---------------------------------------------------------------------------

test "simulateOpenTaker returns normally when the write would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(perp_abi.open_taker_selector, &ok_return);

    try perp_contract.simulateOpenTaker(&ctx, addr(0xBE), .{
        .margin = 100.0,
        .perp_delta = 250,
        .amt1_limit = 999,
    });
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateOpenTaker propagates the revert-preflight error" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    // No response for openTaker -> preflight surfaces the "revert".
    try std.testing.expectError(NoMockResponse, perp_contract.simulateOpenTaker(&ctx, addr(0xBE), .{
        .margin = 100.0,
        .perp_delta = 250,
        .amt1_limit = 999,
    }));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

// ---------------------------------------------------------------------------
// simulateOpenMaker
// ---------------------------------------------------------------------------

test "simulateOpenMaker returns normally when the write would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(perp_abi.open_maker_selector, &ok_return);

    try perp_contract.simulateOpenMaker(&ctx, addr(0xBE), .{
        .margin = 50.0,
        .price_lower = 1.0,
        .price_upper = 4.0,
        .liquidity = 123_456,
        .max_amt0_in = 10,
        .max_amt1_in = 20,
    });
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

// ---------------------------------------------------------------------------
// simulateAdjustTaker
// ---------------------------------------------------------------------------

test "simulateAdjustTaker returns normally when the write would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(perp_abi.adjust_taker_selector, &ok_return);

    try perp_contract.simulateAdjustTaker(&ctx, addr(0xBE), .{
        .position_id = 42,
        .margin_delta = -500_000,
        .perp_delta = 33,
        .amt1_limit = 1000,
    });
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateAdjustTaker propagates the revert-preflight error" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(NoMockResponse, perp_contract.simulateAdjustTaker(&ctx, addr(0xBE), .{
        .position_id = 42,
        .margin_delta = -500_000,
        .perp_delta = 33,
        .amt1_limit = 1000,
    }));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

// ---------------------------------------------------------------------------
// simulateLiquidateTaker
// ---------------------------------------------------------------------------

test "simulateLiquidateTaker returns normally when the write would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(perp_abi.liquidate_taker_selector, &ok_return);

    try perp_contract.simulateLiquidateTaker(&ctx, addr(0xBE), .{
        .position_id = 4242,
        .fee_recipient = addr(0x77),
    });
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateLiquidateTaker propagates the revert-preflight error" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    // No response -> an underwater/non-liquidatable position's revert is caught
    // by the preflight before a nonce is burned.
    try std.testing.expectError(NoMockResponse, perp_contract.simulateLiquidateTaker(&ctx, addr(0xBE), .{
        .position_id = 4242,
        .fee_recipient = addr(0x77),
    }));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

// ---------------------------------------------------------------------------
// simulateBackstopTaker
// ---------------------------------------------------------------------------

test "simulateBackstopTaker returns normally when the write would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(perp_abi.backstop_taker_selector, &ok_return);

    try perp_contract.simulateBackstopTaker(&ctx, addr(0xBE), .{
        .position_id = 9,
        .margin_in = 1_000_000,
        .position_recipient = addr(0x66),
    });
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateBackstopTaker propagates the revert-preflight error" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(NoMockResponse, perp_contract.simulateBackstopTaker(&ctx, addr(0xBE), .{
        .position_id = 9,
        .margin_in = 1_000_000,
        .position_recipient = addr(0x66),
    }));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

// ---------------------------------------------------------------------------
// simulateApproveUsdcMax / simulateCreatePerp
// ---------------------------------------------------------------------------

test "simulateApproveUsdcMax returns normally when the approval would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(erc20_abi.approve_selector, &ok_return);

    try approve.simulateApproveUsdcMax(&ctx, addr(0xBE));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateApproveUsdcMax propagates the revert-preflight error" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(NoMockResponse, approve.simulateApproveUsdcMax(&ctx, addr(0xBE)));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

fn testCreatePerpParams() types.CreatePerpParams {
    return .{
        .owner = addr(0x01),
        .name = "Test Market",
        .symbol = "TEST",
        .token_uri = "ipfs://uri",
        .modules = .{
            .beacon = addr(0xB0),
            .fees = addr(0xB1),
            .funding = addr(0xB2),
            .margin_ratios = addr(0xB3),
            .price_impact = addr(0xB4),
            .pricing = addr(0xB5),
        },
        .ema_window = 3600,
    };
}

test "simulateCreatePerp returns normally when the deployment would not revert" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try mock.setResponse(perp_factory_abi.create_perp_selector, &ok_return);

    try perp_factory.simulateCreatePerp(&ctx, testCreatePerpParams());
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "simulateCreatePerp propagates the revert-preflight error" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    try std.testing.expectError(NoMockResponse, perp_factory.simulateCreatePerp(&ctx, testCreatePerpParams()));
    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}
