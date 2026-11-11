// Write-path unit tests for the contract layer, driven through the ChainClient
// seam with an in-memory mock (no network / Anvil). Each test invokes a write
// wrapper and asserts the recorded `sent` entry's target, 4-byte selector,
// calldata length, and -- where the args are statically encoded -- decodes the
// calldata back to the inputs. Open/create wrappers additionally seed a canned
// receipt so the id-decoding path is exercised.
//
// The most safety-critical assertions are the selectors: they are pinned to the
// hex values solc derives from the perpcity-contracts v1.0.0 interfaces, so a
// drifted signature string fails here rather than on-chain.
const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const conversions = sdk.conversions;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const mock_chain_client = sdk.testing.mock_chain_client;
const MockChainClient = mock_chain_client.MockChainClient;
const perp_contract = sdk.perp_contract;
const perp_factory = sdk.perp_factory;
const approve = sdk.approve;

const perp_abi = sdk.abi.perp_abi;
const erc20_abi = sdk.abi.erc20_abi;
const perp_factory_abi = sdk.abi.perp_factory_abi;
const withdrawal_controller = sdk.withdrawal_controller;
const withdrawal_controller_abi = sdk.abi.withdrawal_controller_abi;

const AbiType = eth.abi_types.AbiType;

// ---------------------------------------------------------------------------
// Helpers
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

/// Interpret a 20-byte address as a big-endian u256. Used to seed a
/// PerpCreated log whose data word carries `a` in its low 20 bytes.
fn addrToU256(a: types.Address) u256 {
    var v: u256 = 0;
    for (a) |b| v = (v << 8) | @as(u256, b);
    return v;
}

/// Decode the ABI args following the 4-byte selector. Caller frees with
/// `eth.abi_decode.freeValues`.
fn decodeArgs(data: []const u8, arg_types: []const AbiType) ![]eth.abi_encode.AbiValue {
    return eth.abi_decode.decodeValues(data[4..], arg_types, std.testing.allocator);
}

// ---------------------------------------------------------------------------
// liquidateTaker / liquidateMaker -- 3-arg v1.0.0 selector guard
// ---------------------------------------------------------------------------

test "liquidateTaker encodes the v1.0.0 selector and (posId, feeRecipient, perpAmount)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const recipient = addr(0x77);
    const pos_id: u256 = 4242;

    const tx_hash = try perp_contract.liquidateTaker(&ctx, perp, .{
        .position_id = pos_id,
        .fee_recipient = recipient,
        .amount = 1_500_000,
    });
    try std.testing.expectEqualSlices(u8, &mock.next_hash, &tx_hash);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    // liquidateTaker(uint256,address,uint128) == 0xbfb4b1c7.
    const v1_selector = [4]u8{ 0xbf, 0xb4, 0xb1, 0xc7 };
    try std.testing.expectEqualSlices(u8, &v1_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 3 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .uint256, .address, .uint128 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(pos_id, decoded[0].uint256);
    try std.testing.expectEqualSlices(u8, &recipient, &decoded[1].address);
    try std.testing.expectEqual(@as(u256, 1_500_000), decoded[2].uint256);
}

test "liquidateMaker encodes the v1.0.0 selector and (posId, feeRecipient, liquidityAmount)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const recipient = addr(0x77);
    const pos_id: u256 = 1;

    _ = try perp_contract.liquidateMaker(&ctx, perp, .{
        .position_id = pos_id,
        .fee_recipient = recipient,
        .amount = std.math.maxInt(u128),
    });

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    // liquidateMaker(uint256,address,uint128) == 0x14ca0f4c.
    const v1_selector = [4]u8{ 0x14, 0xca, 0x0f, 0x4c };
    try std.testing.expectEqualSlices(u8, &v1_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 3 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .uint256, .address, .uint128 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(pos_id, decoded[0].uint256);
    try std.testing.expectEqualSlices(u8, &recipient, &decoded[1].address);
    try std.testing.expectEqual(@as(u256, std.math.maxInt(u128)), decoded[2].uint256);
}

test "OpenPosition.liquidate routes by role and forwards the amount" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const taker: sdk.open_position.OpenPosition = .{ .ctx = &ctx, .perp = perp, .position_id = 3, .is_maker = false, .tx_hash = null };
    const maker: sdk.open_position.OpenPosition = .{ .ctx = &ctx, .perp = perp, .position_id = 4, .is_maker = true, .tx_hash = null };

    _ = try taker.liquidate(addr(0x77), 11);
    try std.testing.expectEqualSlices(u8, &perp_abi.liquidate_taker_selector, mock.lastSent().?.data[0..4]);
    {
        const decoded = try decodeArgs(mock.lastSent().?.data, &.{ .uint256, .address, .uint128 });
        defer eth.abi_decode.freeValues(decoded, allocator);
        try std.testing.expectEqual(@as(u256, 3), decoded[0].uint256);
        try std.testing.expectEqual(@as(u256, 11), decoded[2].uint256);
    }

    _ = try maker.liquidate(addr(0x77), 22);
    try std.testing.expectEqualSlices(u8, &perp_abi.liquidate_maker_selector, mock.lastSent().?.data[0..4]);
    {
        const decoded = try decodeArgs(mock.lastSent().?.data, &.{ .uint256, .address, .uint128 });
        defer eth.abi_decode.freeValues(decoded, allocator);
        try std.testing.expectEqual(@as(u256, 4), decoded[0].uint256);
        try std.testing.expectEqual(@as(u256, 22), decoded[2].uint256);
    }
}

// ---------------------------------------------------------------------------
// openTaker
// ---------------------------------------------------------------------------

test "openTaker sends openTaker calldata and returns the seeded position id" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const pos_id: u256 = 0x1234_5678;
    mock.setReceipt(try mock_chain_client.makeOpenReceipt(allocator, perp, perp_abi.taker_opened_topic, pos_id));

    const op = try perp_contract.openTaker(&ctx, perp, .{
        .margin = 100.0,
        .perp_delta = 250,
        .amt1_limit = 999,
        .max_total_fee = 77,
        .deadline = 1_900_000_000,
    });
    try std.testing.expectEqual(pos_id, op.position_id);
    try std.testing.expect(!op.is_maker);
    try std.testing.expectEqualSlices(u8, &perp, &op.perp);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.open_taker_selector, sent.data[0..4]);
    // tuple(address, uint128, int256, uint256, uint256, uint64) is fully static -> inlined.
    try std.testing.expectEqual(@as(usize, 4 + 6 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .address, .uint256, .int256, .uint256, .uint256, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqualSlices(u8, &mock.mock_addr, &decoded[0].address);
    const expected_margin: u256 = @intCast(try conversions.scale6Decimals(100.0));
    try std.testing.expectEqual(expected_margin, decoded[1].uint256);
    try std.testing.expectEqual(@as(i256, 250), decoded[2].int256);
    try std.testing.expectEqual(@as(u256, 999), decoded[3].uint256);
    try std.testing.expectEqual(@as(u256, 77), decoded[4].uint256);
    try std.testing.expectEqual(@as(u256, 1_900_000_000), decoded[5].uint256);
}

test "openTaker defaults to no fee cap and no deadline" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    mock.setReceipt(try mock_chain_client.makeOpenReceipt(allocator, perp, perp_abi.taker_opened_topic, 1));
    _ = try perp_contract.openTaker(&ctx, perp, .{ .margin = 10.0, .perp_delta = -5, .amt1_limit = 0 });

    const decoded = try decodeArgs(mock.lastSent().?.data, &.{ .address, .uint256, .int256, .uint256, .uint256, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(i256, -5), decoded[2].int256);
    try std.testing.expectEqual(std.math.maxInt(u256), decoded[4].uint256);
    try std.testing.expectEqual(@as(u256, std.math.maxInt(u64)), decoded[5].uint256);
}

test "openTaker reads the position id from the indexed topic, not the log data" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    // A v1.0.0 TakerOpened log: the id is in topics[1] and the data starts with
    // the posted margin. Reading the first data word (the pre-v1 layout) would
    // return the margin instead.
    const receipt = try mock_chain_client.makeOpenReceipt(allocator, perp, perp_abi.taker_opened_topic, 31);
    const margin_word = try eth.abi_encode.encodeValues(allocator, &.{.{ .uint256 = 100_000_000 }});
    allocator.free(receipt.logs[0].data);
    @constCast(receipt.logs)[0].data = margin_word;
    mock.setReceipt(receipt);

    const op = try perp_contract.openTaker(&ctx, perp, .{ .margin = 100.0, .perp_delta = 1, .amt1_limit = 0 });
    try std.testing.expectEqual(@as(u256, 31), op.position_id);
}

test "openTaker surfaces TransactionReverted when the receipt status is 0" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    var receipt = try mock_chain_client.makeOpenReceipt(allocator, perp, perp_abi.taker_opened_topic, 1);
    receipt.status = 0;
    mock.setReceipt(receipt);

    try std.testing.expectError(perp_contract.PerpError.TransactionReverted, perp_contract.openTaker(&ctx, perp, .{
        .margin = 10.0,
        .perp_delta = 1,
        .amt1_limit = 0,
    }));
}

test "openTaker surfaces EventDecodeFailed when no matching log is present" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    // Success receipt, but the log carries the MakerOpened topic -> no TakerOpened match.
    mock.setReceipt(try mock_chain_client.makeOpenReceipt(allocator, perp, perp_abi.maker_opened_topic, 1));

    try std.testing.expectError(perp_contract.PerpError.EventDecodeFailed, perp_contract.openTaker(&ctx, perp, .{
        .margin = 10.0,
        .perp_delta = 1,
        .amt1_limit = 0,
    }));
}

// ---------------------------------------------------------------------------
// openMaker
// ---------------------------------------------------------------------------

test "openMaker sends openMaker calldata and returns the seeded position id" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const pos_id: u256 = 777;
    mock.setReceipt(try mock_chain_client.makeOpenReceipt(allocator, perp, perp_abi.maker_opened_topic, pos_id));

    const op = try perp_contract.openMaker(&ctx, perp, .{
        .margin = 50.0,
        .price_lower = 1.0,
        .price_upper = 4.0,
        .liquidity = 123_456,
        .max_amt0_in = 10,
        .max_amt1_in = 20,
        .deadline = 1_900_000_001,
    });
    try std.testing.expectEqual(pos_id, op.position_id);
    try std.testing.expect(op.is_maker);
    try std.testing.expectEqualSlices(u8, &perp, &op.perp);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.open_maker_selector, sent.data[0..4]);
    // tuple(address, uint128, int24, int24, uint128, uint256, uint256, uint64) -> 8 static words.
    try std.testing.expectEqual(@as(usize, 4 + 8 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .address, .uint256, .int256, .int256, .uint256, .uint256, .uint256, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqualSlices(u8, &mock.mock_addr, &decoded[0].address);
    const expected_margin: u256 = @intCast(try conversions.scale6Decimals(50.0));
    try std.testing.expectEqual(expected_margin, decoded[1].uint256);
    // price_lower < price_upper -> tickLower < tickUpper.
    try std.testing.expect(decoded[2].int256 < decoded[3].int256);
    try std.testing.expectEqual(@as(u256, 123_456), decoded[4].uint256);
    try std.testing.expectEqual(@as(u256, 10), decoded[5].uint256);
    try std.testing.expectEqual(@as(u256, 20), decoded[6].uint256);
    try std.testing.expectEqual(@as(u256, 1_900_000_001), decoded[7].uint256);
}

// ---------------------------------------------------------------------------
// adjustTaker / adjustMaker
// ---------------------------------------------------------------------------

test "adjustTaker encodes selector and every AdjustTakerParams field" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    _ = try perp_contract.adjustTaker(&ctx, perp, .{
        .position_id = 42,
        .margin_delta = -500_000,
        .perp_delta = 33,
        .amt1_limit = 1000,
        .max_total_fee = 55,
        .reduce_only = true,
        .deadline = 1_900_000_002,
    });

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.adjust_taker_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 7 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .uint256, .int256, .int256, .uint256, .uint256, .bool, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 42), decoded[0].uint256);
    try std.testing.expectEqual(@as(i256, -500_000), decoded[1].int256);
    try std.testing.expectEqual(@as(i256, 33), decoded[2].int256);
    try std.testing.expectEqual(@as(u256, 1000), decoded[3].uint256);
    try std.testing.expectEqual(@as(u256, 55), decoded[4].uint256);
    try std.testing.expectEqual(true, decoded[5].boolean);
    try std.testing.expectEqual(@as(u256, 1_900_000_002), decoded[6].uint256);
}

test "adjustTaker defaults to not reduce-only" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    _ = try perp_contract.adjustTaker(&ctx, addr(0xBE), .{ .position_id = 1, .margin_delta = 0, .perp_delta = -1, .amt1_limit = 0 });
    const decoded = try decodeArgs(mock.lastSent().?.data, &.{ .uint256, .int256, .int256, .uint256, .uint256, .bool, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(std.math.maxInt(u256), decoded[4].uint256);
    try std.testing.expectEqual(false, decoded[5].boolean);
    try std.testing.expectEqual(@as(u256, std.math.maxInt(u64)), decoded[6].uint256);
}

test "adjustMaker encodes selector and every AdjustMakerParams field" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    _ = try perp_contract.adjustMaker(&ctx, perp, .{
        .position_id = 7,
        .margin_delta = 250_000,
        .liquidity_delta = -900,
        .amt0_limit = 11,
        .amt1_limit = 22,
        .deadline = 1_900_000_003,
    });

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.adjust_maker_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 6 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .uint256, .int256, .int256, .uint256, .uint256, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 7), decoded[0].uint256);
    try std.testing.expectEqual(@as(i256, 250_000), decoded[1].int256);
    try std.testing.expectEqual(@as(i256, -900), decoded[2].int256);
    try std.testing.expectEqual(@as(u256, 11), decoded[3].uint256);
    try std.testing.expectEqual(@as(u256, 22), decoded[4].uint256);
    try std.testing.expectEqual(@as(u256, 1_900_000_003), decoded[5].uint256);
}

// ---------------------------------------------------------------------------
// moveMaker
// ---------------------------------------------------------------------------

test "moveMaker encodes selector and every MoveMakerParams field" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    _ = try perp_contract.moveMaker(&ctx, perp, .{
        .position_id = 8,
        .tick_lower = -600,
        .tick_upper = 900,
        .liquidity = 5_000,
        .remove_amt0_min = 1,
        .remove_amt1_min = 2,
        .add_amt0_max = 3,
        .add_amt1_max = 4,
        .margin_delta = -250_000,
        .deadline = 1_900_000_004,
    });

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.move_maker_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 10 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{
        .uint256, .int24,   .int24,   .uint128, .uint256,
        .uint256, .uint256, .uint256, .int128,  .uint64,
    });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 8), decoded[0].uint256);
    try std.testing.expectEqual(@as(i256, -600), decoded[1].int256);
    try std.testing.expectEqual(@as(i256, 900), decoded[2].int256);
    try std.testing.expectEqual(@as(u256, 5_000), decoded[3].uint256);
    try std.testing.expectEqual(@as(u256, 1), decoded[4].uint256);
    try std.testing.expectEqual(@as(u256, 2), decoded[5].uint256);
    try std.testing.expectEqual(@as(u256, 3), decoded[6].uint256);
    try std.testing.expectEqual(@as(u256, 4), decoded[7].uint256);
    try std.testing.expectEqual(@as(i256, -250_000), decoded[8].int256);
    try std.testing.expectEqual(@as(u256, 1_900_000_004), decoded[9].uint256);
}

// ---------------------------------------------------------------------------
// backstopTaker / backstopMaker
// ---------------------------------------------------------------------------

test "backstopTaker encodes selector and (posId, marginIn, positionRecipient, deadline)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const recipient = addr(0x66);
    _ = try perp_contract.backstopTaker(&ctx, perp, .{
        .position_id = 9,
        .margin_in = 1_000_000,
        .position_recipient = recipient,
        .deadline = 1_900_000_005,
    });

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.backstop_taker_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 4 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .uint256, .uint256, .address, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 9), decoded[0].uint256);
    try std.testing.expectEqual(@as(u256, 1_000_000), decoded[1].uint256);
    try std.testing.expectEqualSlices(u8, &recipient, &decoded[2].address);
    try std.testing.expectEqual(@as(u256, 1_900_000_005), decoded[3].uint256);
}

test "backstopMaker encodes selector and (posId, marginIn, positionRecipient, deadline)" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const recipient = addr(0x66);
    _ = try perp_contract.backstopMaker(&ctx, perp, .{
        .position_id = 5,
        .margin_in = 2_000_000,
        .position_recipient = recipient,
        .deadline = 1_900_000_005,
    });

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.backstop_maker_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 4 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .uint256, .uint256, .address, .uint64 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 5), decoded[0].uint256);
    try std.testing.expectEqual(@as(u256, 2_000_000), decoded[1].uint256);
    try std.testing.expectEqualSlices(u8, &recipient, &decoded[2].address);
    try std.testing.expectEqual(@as(u256, 1_900_000_005), decoded[3].uint256);
}

// ---------------------------------------------------------------------------
// donate / touch / syncProtocolFee
// ---------------------------------------------------------------------------

test "donate encodes selector and the amount word" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    _ = try perp_contract.donate(&ctx, perp, 5_000_000);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.donate_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{.uint256});
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 5_000_000), decoded[0].uint256);
}

test "touch encodes the no-arg selector" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    _ = try perp_contract.touch(&ctx, perp);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.touch_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4), sent.data.len);
}

test "syncProtocolFee encodes the no-arg selector" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    _ = try perp_contract.syncProtocolFee(&ctx, perp);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.sync_protocol_fee_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4), sent.data.len);
}

// ---------------------------------------------------------------------------
// collectCreatorFees / collectProtocolFees
// ---------------------------------------------------------------------------

test "collectCreatorFees encodes selector and the recipient" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const recipient = addr(0x88);
    _ = try perp_contract.collectCreatorFees(&ctx, perp, recipient);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.collect_creator_fees_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{.address});
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqualSlices(u8, &recipient, &decoded[0].address);
}

test "collectProtocolFees encodes selector and the recipient" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const perp = addr(0xBE);
    const recipient = addr(0x88);
    _ = try perp_contract.collectProtocolFees(&ctx, perp, recipient);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &perp, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_abi.collect_protocol_fees_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{.address});
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqualSlices(u8, &recipient, &decoded[0].address);
}

// ---------------------------------------------------------------------------
// approveUsdcMax (approve.zig)
// ---------------------------------------------------------------------------

test "approveUsdcMax sends approve(perp, maxUint256) to the USDC address" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    const deployments = testDeployments();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), deployments);
    defer ctx.deinit();

    const perp = addr(0xBE);
    // approveUsdc requires a success receipt before returning the hash.
    mock.setReceipt(try mock_chain_client.makeOpenReceipt(allocator, addr(0x00), perp_abi.taker_opened_topic, 0));

    _ = try approve.approveUsdcMax(&ctx, perp);

    const sent = mock.lastSent().?;
    // Sent to USDC (0x44), not the perp.
    try std.testing.expectEqualSlices(u8, &deployments.usdc, &sent.to);
    // approve(address,uint256) == 0x095ea7b3 (canonical ERC20 selector).
    const erc20_approve_selector = [4]u8{ 0x09, 0x5e, 0xa7, 0xb3 };
    try std.testing.expectEqualSlices(u8, &erc20_approve_selector, sent.data[0..4]);
    try std.testing.expectEqualSlices(u8, &erc20_abi.approve_selector, sent.data[0..4]);
    try std.testing.expectEqual(@as(usize, 4 + 32 + 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{ .address, .uint256 });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqualSlices(u8, &perp, &decoded[0].address);
    try std.testing.expectEqual(std.math.maxInt(u256), decoded[1].uint256);
}

// ---------------------------------------------------------------------------
// createPerp (perp_factory)
// ---------------------------------------------------------------------------

fn testCreatePerpParams() types.CreatePerpParams {
    return .{
        .owner = addr(0x01),
        .governor = addr(0x02),
        .modules = .{
            .beacon = addr(0xB0),
            .fees = addr(0xB1),
            .funding = addr(0xB2),
            .margin_ratios = addr(0xB3),
            .price_impact = addr(0xB4),
            .pricing = addr(0xB5),
        },
        .ema_window = 3600,
        .latency = 900,
        .salt = @as([32]u8, @splat(0x5A)),
        .withdrawal_config = .{
            .capacity = 50_000_000_000,
            .refill_per_second = 1_000_000,
            .challenge_window = 86_400,
        },
    };
}

test "createPerp sends createPerp calldata and decodes the perp address from PerpCreated" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    const deployments = testDeployments();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), deployments);
    defer ctx.deinit();

    const perp_addr = addr(0x99);
    // PerpCreated's first data word carries `perp` in its low 20 bytes; the
    // factory is the emitter it filters on.
    mock.setReceipt(try mock_chain_client.makeDataWordReceipt(
        allocator,
        deployments.perp_factory,
        perp_factory_abi.perp_created_topic,
        addrToU256(perp_addr),
    ));

    const out = try perp_factory.createPerp(&ctx, testCreatePerpParams());
    try std.testing.expectEqualSlices(u8, &perp_addr, &out);

    const sent = mock.lastSent().?;
    // Sent to the factory (0x11).
    try std.testing.expectEqualSlices(u8, &deployments.perp_factory, &sent.to);
    try std.testing.expectEqualSlices(u8, &perp_factory_abi.create_perp_selector, sent.data[0..4]);
    // (owner, governor, Modules x6, emaWindow, latency, salt, WithdrawalConfig x3)
    // is fully static -> 14 inlined words.
    try std.testing.expectEqual(@as(usize, 4 + 14 * 32), sent.data.len);

    const decoded = try decodeArgs(sent.data, &.{
        .address, .address, .address, .address, .address, .address, .address,
        .address, .uint24,  .uint32,  .bytes32, .uint128, .uint128, .uint48,
    });
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqualSlices(u8, &addr(0x01), &decoded[0].address);
    try std.testing.expectEqualSlices(u8, &addr(0x02), &decoded[1].address);
    // Modules in struct order: beacon, fees, funding, marginRatios, priceImpact, pricing.
    inline for (0..6) |i| {
        try std.testing.expectEqualSlices(u8, &addr(0xB0 + @as(u8, i)), &decoded[2 + i].address);
    }
    try std.testing.expectEqual(@as(u256, 3600), decoded[8].uint256);
    try std.testing.expectEqual(@as(u256, 900), decoded[9].uint256);
    try std.testing.expectEqualSlices(u8, &@as([32]u8, @splat(0x5A)), &decoded[10].fixed_bytes.data);
    try std.testing.expectEqual(@as(u256, 50_000_000_000), decoded[11].uint256);
    try std.testing.expectEqual(@as(u256, 1_000_000), decoded[12].uint256);
    try std.testing.expectEqual(@as(u256, 86_400), decoded[13].uint256);
}

test "createPerp rejects inputs the factory would revert on, without sending" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    var no_window = testCreatePerpParams();
    no_window.ema_window = 0;
    try std.testing.expectError(perp_factory.FactoryError.EmaWindowTooLow, perp_factory.createPerp(&ctx, no_window));

    var no_governor = testCreatePerpParams();
    no_governor.governor = types.ZERO_ADDRESS;
    try std.testing.expectError(perp_factory.FactoryError.ZeroGovernor, perp_factory.createPerp(&ctx, no_governor));

    var no_challenge = testCreatePerpParams();
    no_challenge.withdrawal_config.challenge_window = 0;
    try std.testing.expectError(perp_factory.FactoryError.ZeroChallengeWindow, perp_factory.createPerp(&ctx, no_challenge));

    try std.testing.expectEqual(@as(?mock_chain_client.SentTx, null), mock.lastSent());
}

test "createPerp surfaces TransactionReverted when the receipt status is 0" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    const deployments = testDeployments();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), deployments);
    defer ctx.deinit();

    var receipt = try mock_chain_client.makeDataWordReceipt(
        allocator,
        deployments.perp_factory,
        perp_factory_abi.perp_created_topic,
        addrToU256(addr(0x99)),
    );
    receipt.status = 0;
    mock.setReceipt(receipt);

    try std.testing.expectError(perp_factory.FactoryError.TransactionReverted, perp_factory.createPerp(&ctx, testCreatePerpParams()));
}

test "createPerp surfaces EventDecodeFailed when no PerpCreated log matches" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    const deployments = testDeployments();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), deployments);
    defer ctx.deinit();

    // Success receipt, but the log was emitted by a different contract.
    mock.setReceipt(try mock_chain_client.makeDataWordReceipt(
        allocator,
        addr(0xDE),
        perp_factory_abi.perp_created_topic,
        addrToU256(addr(0x99)),
    ));

    try std.testing.expectError(perp_factory.FactoryError.EventDecodeFailed, perp_factory.createPerp(&ctx, testCreatePerpParams()));
}

// ---------------------------------------------------------------------------
// WithdrawalController
// ---------------------------------------------------------------------------

test "withdrawal_controller.release sends release(claimId) to the controller" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const controller = addr(0xC7);
    _ = try withdrawal_controller.release(&ctx, controller, 12);

    const sent = mock.lastSent().?;
    try std.testing.expectEqualSlices(u8, &controller, &sent.to);
    // release(uint256) == 0x37bdc99b.
    try std.testing.expectEqualSlices(u8, &[4]u8{ 0x37, 0xbd, 0xc9, 0x9b }, sent.data[0..4]);
    const decoded = try decodeArgs(sent.data, &.{.uint256});
    defer eth.abi_decode.freeValues(decoded, allocator);
    try std.testing.expectEqual(@as(u256, 12), decoded[0].uint256);
}

test "claimIdFromReceipt finds the claim created for the recipient" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();
    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const controller = addr(0xC7);
    const recipient = addr(0x9A);
    // ClaimCreated(uint256 indexed claimId, address indexed recipient, uint128 amount).
    const receipt = try mock_chain_client.makeOpenReceipt(allocator, controller, withdrawal_controller_abi.claim_created_topic, 5);
    @memcpy(@constCast(receipt.logs[0].topics)[2][12..32], &recipient);
    mock.setReceipt(receipt);

    const tx: types.Bytes32 = @splat(0xCD);
    try std.testing.expectEqual(@as(?u256, 5), try withdrawal_controller.claimIdFromReceipt(&ctx, controller, tx, recipient));
    // A different recipient, or a different emitter, is not this wallet's claim.
    try std.testing.expectEqual(@as(?u256, null), try withdrawal_controller.claimIdFromReceipt(&ctx, controller, tx, addr(0x9B)));
    try std.testing.expectEqual(@as(?u256, null), try withdrawal_controller.claimIdFromReceipt(&ctx, addr(0xC8), tx, recipient));
}
