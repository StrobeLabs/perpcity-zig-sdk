const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const events = sdk.events;
const event_decode = sdk.event_decode;

const AbiValue = eth.abi_encode.AbiValue;
const Log = eth.receipt.Log;

// ---------------------------------------------------------------------------
// Helpers (mirror the other contract/*_test.zig files)
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

/// ABI-encode `values` as a log's `data` payload. Caller frees.
fn enc(values: []const AbiValue) ![]u8 {
    return eth.abi_encode.encodeValues(std.testing.allocator, values);
}

/// Build a Log emitted by perp `0xBE` with the given topics and data. Both
/// slices are borrowed; `MockChainClient.setLogs` deep-copies them.
fn mkLog(topics: []const [32]u8, data: []const u8) Log {
    return .{
        .address = addr(0xBE),
        .topics = topics,
        .data = data,
        .block_number = 100,
        .transaction_hash = null,
        .transaction_index = null,
        .log_index = null,
        .block_hash = null,
        .removed = false,
    };
}

// ---------------------------------------------------------------------------
// pollEvents -- getLogs seam + decodeEvent over a batch of canned logs
// ---------------------------------------------------------------------------

test "pollEvents decodes a batch of logs and skips unknown topics" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const tc_topics = [_][32]u8{events.Topics.TAKER_CLOSED};
    const mo_topics = [_][32]u8{events.Topics.MAKER_OPENED};
    const dn_topics = [_][32]u8{events.Topics.DONATED};
    const oi_topics = [_][32]u8{events.Topics.OPEN_INTEREST_UPDATED};
    const to_topics = [_][32]u8{events.Topics.TAKER_OPENED};
    const unknown_topics = [_][32]u8{[_]u8{0xFF} ** 32};

    // TakerClosed: posId + inline SwapResult(7) + funding + utilFees + liqFee + isLiquidation.
    const tc_data = try enc(&.{
        .{ .uint256 = 42 },
        .{ .int256 = -1000 },
        .{ .uint256 = 5000 },
        .{ .int256 = -20 },
        .{ .uint256 = 30 },
        .{ .uint256 = 40 },
        .{ .uint256 = 50 },
        .{ .uint256 = 60 },
        .{ .int256 = -777 },
        .{ .uint256 = 12345 },
        .{ .uint256 = 999 },
        .{ .boolean = true },
    });
    defer allocator.free(tc_data);

    const mo_data = try enc(&.{.{ .uint256 = 7 }});
    defer allocator.free(mo_data);

    const dn_data = try enc(&.{
        .{ .address = addr(0xDD) }, .{ .uint256 = 1_000_000 },
        .{ .uint256 = 2_000_000 },  .{ .uint256 = 3_000_000 },
    });
    defer allocator.free(dn_data);

    const oi_data = try enc(&.{ .{ .uint256 = 111_000 }, .{ .uint256 = 55_000 } });
    defer allocator.free(oi_data);

    // TakerOpened: posId followed by the inline SwapResult tuple; the assertions
    // below prove every nested field is decoded from its ABI offset.
    const to_data = try enc(&.{
        .{ .uint256 = 99 },
        .{ .int256 = 111 },
        .{ .uint256 = 222 },
        .{ .int256 = 333 },
        .{ .uint256 = 444 },
        .{ .uint256 = 555 },
        .{ .uint256 = 666 },
        .{ .uint256 = 777 },
    });
    defer allocator.free(to_data);

    const unknown_data = try enc(&.{.{ .uint256 = 123 }});
    defer allocator.free(unknown_data);

    const logs = [_]Log{
        mkLog(&tc_topics, tc_data),
        mkLog(&mo_topics, mo_data),
        mkLog(&dn_topics, dn_data),
        mkLog(&oi_topics, oi_data),
        mkLog(&to_topics, to_data),
        mkLog(&unknown_topics, unknown_data),
    };
    try mock.setLogs(&logs);

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const decoded = try ctx.pollEvents(addr(0xBE), 100, 200);
    defer allocator.free(decoded);

    // Six logs in, one unknown topic0 skipped -> five decoded, order preserved.
    try std.testing.expectEqual(@as(usize, 5), decoded.len);

    // [0] TakerClosed -- fully decoded, including the inline SwapResult.
    const tc = decoded[0].taker_closed;
    try std.testing.expectEqual(@as(u256, 42), tc.pos_id);
    try std.testing.expectEqual(@as(i256, -1000), tc.sr.delta);
    try std.testing.expectEqual(@as(u256, 5000), tc.sr.amm_price);
    try std.testing.expectEqual(@as(i256, -20), tc.sr.total_fee_amt);
    try std.testing.expectEqual(@as(u256, 30), tc.sr.lp_fee_amt);
    try std.testing.expectEqual(@as(u256, 40), tc.sr.protocol_fee_amt);
    try std.testing.expectEqual(@as(u256, 50), tc.sr.creator_fee_amt);
    try std.testing.expectEqual(@as(u256, 60), tc.sr.insurance_fee_amt);
    try std.testing.expectEqual(@as(i256, -777), tc.funding);
    try std.testing.expectEqual(@as(u256, 12345), tc.util_fees);
    try std.testing.expectEqual(@as(u256, 999), tc.liq_fee);
    try std.testing.expectEqual(true, tc.is_liquidation);

    // [1] MakerOpened
    try std.testing.expectEqual(@as(u256, 7), decoded[1].maker_opened.pos_id);

    // [2] Donated
    const dn = decoded[2].donated;
    try std.testing.expectEqualSlices(u8, &addr(0xDD), &dn.donor);
    try std.testing.expectEqual(@as(u128, 1_000_000), dn.amount);
    try std.testing.expectEqual(@as(u128, 2_000_000), dn.bad_debt);
    try std.testing.expectEqual(@as(u80, 3_000_000), dn.insurance);

    // [3] OpenInterestUpdated
    const oi = decoded[3].open_interest_updated.oi;
    try std.testing.expectEqual(@as(u128, 111_000), oi.long);
    try std.testing.expectEqual(@as(u128, 55_000), oi.short);

    // [4] TakerOpened -- posId plus the fully decoded inline SwapResult.
    const to = decoded[4].taker_opened;
    try std.testing.expectEqual(@as(u256, 99), to.pos_id);
    try std.testing.expectEqual(@as(i256, 111), to.sr.delta);
    try std.testing.expectEqual(@as(u256, 222), to.sr.amm_price);
    try std.testing.expectEqual(@as(i256, 333), to.sr.total_fee_amt);
    try std.testing.expectEqual(@as(u256, 444), to.sr.lp_fee_amt);
    try std.testing.expectEqual(@as(u256, 555), to.sr.protocol_fee_amt);
    try std.testing.expectEqual(@as(u256, 666), to.sr.creator_fee_amt);
    try std.testing.expectEqual(@as(u256, 777), to.sr.insurance_fee_amt);
}

test "pollEvents returns an empty slice when the perp has no logs" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    var ctx = PerpCityContext.initWithClient(allocator, mock.client(), testDeployments());
    defer ctx.deinit();

    const decoded = try ctx.pollEvents(addr(0xBE), 0, 10);
    defer allocator.free(decoded);
    try std.testing.expectEqual(@as(usize, 0), decoded.len);
}

// ---------------------------------------------------------------------------
// decodeEvent -- direct unit tests
// ---------------------------------------------------------------------------

test "decodeEvent decodes IndexUpdated" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{events.Topics.INDEX_UPDATED};
    const index_val: u256 = 79_228_162_514_264_337_593_543_950_336; // ~Q96
    const data = try enc(&.{.{ .uint256 = index_val }});
    defer allocator.free(data);

    const ev = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?;
    try std.testing.expectEqual(index_val, ev.index_updated.index);
}

test "decodeEvent decodes MakerClosed fully" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{events.Topics.MAKER_CLOSED};
    const data = try enc(&.{
        .{ .uint256 = 5 },     .{ .int256 = -42 }, .{ .uint256 = 10 },
        .{ .uint256 = 20 },    .{ .uint256 = 30 }, .{ .uint256 = 40 },
        .{ .boolean = false },
    });
    defer allocator.free(data);

    const mc = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.maker_closed;
    try std.testing.expectEqual(@as(u256, 5), mc.pos_id);
    try std.testing.expectEqual(@as(i256, -42), mc.funding);
    try std.testing.expectEqual(@as(u256, 10), mc.long_util_fees);
    try std.testing.expectEqual(@as(u256, 20), mc.short_util_fees);
    try std.testing.expectEqual(@as(u256, 30), mc.lp_fees);
    try std.testing.expectEqual(@as(u256, 40), mc.liq_fee);
    try std.testing.expectEqual(false, mc.is_liquidation);
}

test "decodeEvent decodes PerpCreated, flattening Modules and ignoring trailing strings" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{events.Topics.PERP_CREATED};

    var pool_id: [32]u8 = undefined;
    for (&pool_id, 0..) |*b, i| b.* = @intCast(i + 1);

    // Only the leading static fields are encoded; the real event's trailing
    // (name, symbol, tokenUri) strings sit after every declared field and are
    // ignored by the decoder, so omitting them here is faithful.
    const data = try enc(&.{
        .{ .address = addr(0xA0) }, // perp
        .{ .fixed_bytes = .{ .data = pool_id, .len = 32 } }, // poolId
        .{ .address = addr(0xB1) },
        .{ .address = addr(0xB2) },
        .{ .address = addr(0xB3) },
        .{ .address = addr(0xB4) }, .{ .address = addr(0xB5) }, .{ .address = addr(0xB6) }, // Modules
        .{ .uint256 = 123_456 }, // initialIndex
        .{ .uint256 = 300 }, // emaWindow (uint24)
        .{ .uint256 = 5000 }, // protocolFee
        .{ .uint256 = @as(u256, 1) << 96 }, // sqrtPriceX96 (uint160)
        .{ .int256 = -60 }, // tick (int24)
        .{ .address = addr(0xEE) }, // owner
    });
    defer allocator.free(data);

    const pc = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.perp_created;
    try std.testing.expectEqualSlices(u8, &addr(0xA0), &pc.perp);
    try std.testing.expectEqualSlices(u8, &pool_id, &pc.pool_id);
    try std.testing.expectEqualSlices(u8, &addr(0xB1), &pc.modules.beacon);
    try std.testing.expectEqualSlices(u8, &addr(0xB2), &pc.modules.fees);
    try std.testing.expectEqualSlices(u8, &addr(0xB6), &pc.modules.pricing);
    try std.testing.expectEqual(@as(u256, 123_456), pc.initial_index);
    try std.testing.expectEqual(@as(u24, 300), pc.ema_window);
    try std.testing.expectEqual(@as(u256, 5000), pc.protocol_fee);
    try std.testing.expectEqual(@as(u256, @as(u256, 1) << 96), pc.sqrt_price_x96);
    try std.testing.expectEqual(@as(i24, -60), pc.tick);
    try std.testing.expectEqualSlices(u8, &addr(0xEE), &pc.owner);
}

test "decodeEvent returns null for an unknown topic0" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{[_]u8{0xAB} ** 32};
    const data = try enc(&.{.{ .uint256 = 1 }});
    defer allocator.free(data);

    try std.testing.expectEqual(
        @as(?event_decode.DecodedEvent, null),
        try event_decode.decodeEvent(allocator, mkLog(&topics, data)),
    );
}

test "decodeEvent returns null for a log with no topics" {
    const allocator = std.testing.allocator;
    const empty_topics = [_][32]u8{};
    const data = try enc(&.{.{ .uint256 = 1 }});
    defer allocator.free(data);

    try std.testing.expectEqual(
        @as(?event_decode.DecodedEvent, null),
        try event_decode.decodeEvent(allocator, mkLog(&empty_topics, data)),
    );
}
