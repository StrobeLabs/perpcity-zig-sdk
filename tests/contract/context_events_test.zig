const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;
const context_mod = sdk.context;
const PerpCityContext = context_mod.PerpCityContext;
const MockChainClient = sdk.testing.mock_chain_client.MockChainClient;
const events = sdk.events;
const event_decode = sdk.event_decode;

const fx = @import("event_fixtures.zig");
const AbiValue = fx.AbiValue;
const Log = fx.Log;
const enc = fx.enc;
const mkLog = fx.mkLog;
const topicU256 = fx.topicU256;
const topicAddr = fx.topicAddr;

// ---------------------------------------------------------------------------
// Helpers (mirror the other contract/*_test.zig files)
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

// ---------------------------------------------------------------------------
// pollEvents -- getLogs seam + decodeEvent over a batch of canned logs
// ---------------------------------------------------------------------------

test "pollEvents decodes a batch of logs and skips unknown topics" {
    const allocator = std.testing.allocator;
    var mock = MockChainClient.init(allocator);
    defer mock.deinit();

    const owner = addr(0xA1);
    const tc_topics = fx.positionTopics(events.Topics.TAKER_CLOSED, 42, owner);
    const mo_topics = fx.positionTopics(events.Topics.MAKER_OPENED, 7, owner);
    const dn_topics = [_][32]u8{events.Topics.DONATED};
    const oi_topics = [_][32]u8{events.Topics.OPEN_INTEREST_UPDATED};
    const to_topics = fx.positionTopics(events.Topics.TAKER_OPENED, 99, owner);
    const unknown_topics = [_][32]u8{@as([32]u8, @splat(0xFF))};

    // TakerClosed data: marginDelta + inline SwapResult(8) + funding + utilFees
    // + delta + margin + lastCumlFundingX96.
    const tc_data = try enc(&.{
        .{ .int256 = -2_000_000 }, // marginDelta
        .{ .int256 = -1000 }, // sr.delta
        .{ .uint256 = 5000 }, // sr.ammPrice
        .{ .int256 = -20 }, // sr.totalFeeAmt
        .{ .uint256 = 30 }, // sr.lpFeeAmt
        .{ .uint256 = 40 }, // sr.protocolFeeAmt
        .{ .uint256 = 50 }, // sr.creatorFeeAmt
        .{ .uint256 = 60 }, // sr.insuranceFeeAmt
        .{ .uint256 = 70 }, // sr.feeFundFeeAmt
        .{ .int256 = -777 }, // funding
        .{ .uint256 = 12345 }, // utilFees
        .{ .int256 = 88 }, // delta
        .{ .uint256 = 99 }, // margin
        .{ .int256 = -111 }, // lastCumlFundingX96
    });
    defer allocator.free(tc_data);

    const mo_data = try fx.makerOpenedData();
    defer allocator.free(mo_data);

    const dn_data = try enc(&.{
        .{ .address = addr(0xDD) }, .{ .uint256 = 1_000_000 },
        .{ .uint256 = 2_000_000 },  .{ .uint256 = 3_000_000 },
    });
    defer allocator.free(dn_data);

    const oi_data = try enc(&.{ .{ .uint256 = 111_000 }, .{ .uint256 = 55_000 } });
    defer allocator.free(oi_data);

    // TakerOpened data: margin, the inline SwapResult tuple, then the funding
    // checkpoint; the assertions below prove every nested field is decoded
    // from its ABI offset.
    const to_data = try enc(&.{
        .{ .uint256 = 10_000_000 }, // margin
        .{ .int256 = 111 },
        .{ .uint256 = 222 },
        .{ .int256 = 333 },
        .{ .uint256 = 444 },
        .{ .uint256 = 555 },
        .{ .uint256 = 666 },
        .{ .uint256 = 777 },
        .{ .uint256 = 888 },
        .{ .int256 = -999 }, // lastCumlFundingX96
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

    // [0] TakerClosed -- indexed (posId, owner) from the topics, the rest from
    // the data, including the inline SwapResult.
    const tc = decoded[0].taker_closed;
    try std.testing.expectEqual(@as(u256, 42), tc.pos_id);
    try std.testing.expectEqualSlices(u8, &owner, &tc.owner);
    try std.testing.expectEqual(@as(i128, -2_000_000), tc.margin_delta);
    try std.testing.expectEqual(@as(i256, -1000), tc.sr.delta);
    try std.testing.expectEqual(@as(u256, 5000), tc.sr.amm_price);
    try std.testing.expectEqual(@as(i256, -20), tc.sr.total_fee_amt);
    try std.testing.expectEqual(@as(u256, 30), tc.sr.lp_fee_amt);
    try std.testing.expectEqual(@as(u256, 40), tc.sr.protocol_fee_amt);
    try std.testing.expectEqual(@as(u256, 50), tc.sr.creator_fee_amt);
    try std.testing.expectEqual(@as(u256, 60), tc.sr.insurance_fee_amt);
    try std.testing.expectEqual(@as(u256, 70), tc.sr.fee_fund_fee_amt);
    try std.testing.expectEqual(@as(i256, -777), tc.funding);
    try std.testing.expectEqual(@as(u256, 12345), tc.util_fees);
    try std.testing.expectEqual(@as(i256, 88), tc.delta);
    try std.testing.expectEqual(@as(u128, 99), tc.margin);
    try std.testing.expectEqual(@as(i256, -111), tc.last_cuml_funding_x96);

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

    // [4] TakerOpened -- posId/owner plus the fully decoded inline SwapResult.
    const to = decoded[4].taker_opened;
    try std.testing.expectEqual(@as(u256, 99), to.pos_id);
    try std.testing.expectEqualSlices(u8, &owner, &to.owner);
    try std.testing.expectEqual(@as(u128, 10_000_000), to.margin);
    try std.testing.expectEqual(@as(i256, 111), to.sr.delta);
    try std.testing.expectEqual(@as(u256, 222), to.sr.amm_price);
    try std.testing.expectEqual(@as(i256, 333), to.sr.total_fee_amt);
    try std.testing.expectEqual(@as(u256, 444), to.sr.lp_fee_amt);
    try std.testing.expectEqual(@as(u256, 555), to.sr.protocol_fee_amt);
    try std.testing.expectEqual(@as(u256, 666), to.sr.creator_fee_amt);
    try std.testing.expectEqual(@as(u256, 777), to.sr.insurance_fee_amt);
    try std.testing.expectEqual(@as(u256, 888), to.sr.fee_fund_fee_amt);
    try std.testing.expectEqual(@as(i256, -999), to.last_cuml_funding_x96);
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

test "decodeEvent decodes MakerOpened fully" {
    const allocator = std.testing.allocator;
    const topics = fx.positionTopics(events.Topics.MAKER_OPENED, 12, addr(0xA1));
    const data = try enc(&.{
        .{ .int256 = -600 }, // tickLower
        .{ .int256 = 900 }, // tickUpper
        .{ .uint256 = 5_000 }, // liquidity
        .{ .int256 = -31 }, // delta
        .{ .int256 = 32 }, // lastCumlFundingX96
        .{ .int256 = -33 }, // lastCumlFunding.belowX96
        .{ .int256 = 34 }, // lastCumlFunding.withinInventoryX192
    });
    defer allocator.free(data);

    const mo = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.maker_opened;
    try std.testing.expectEqual(@as(u256, 12), mo.pos_id);
    try std.testing.expectEqualSlices(u8, &addr(0xA1), &mo.owner);
    try std.testing.expectEqual(@as(i24, -600), mo.tick_lower);
    try std.testing.expectEqual(@as(i24, 900), mo.tick_upper);
    try std.testing.expectEqual(@as(u128, 5_000), mo.liquidity);
    try std.testing.expectEqual(@as(i256, -31), mo.delta);
    try std.testing.expectEqual(@as(i256, 32), mo.last_cuml_funding_x96);
    try std.testing.expectEqual(@as(i256, -33), mo.last_cuml_funding.below_x96);
    try std.testing.expectEqual(@as(i256, 34), mo.last_cuml_funding.within_inventory_x192);
}

/// Distinct-valued MakerAdjusted / MakerClosed / MakerConverted data.
fn makerLifecycleFixture() ![]u8 {
    return enc(&.{
        .{ .int256 = -41 }, // marginDelta
        .{ .int256 = -42 }, // liquidityDelta
        .{ .int256 = -43 }, // funding
        .{ .uint256 = 44 }, // lpFees
        .{ .int256 = -45 }, // delta
        .{ .uint256 = 46 }, // margin
        .{ .uint256 = 47 }, // liquidity
        .{ .int256 = -48 }, // lastCumlFundingX96
        .{ .int256 = 49 }, // lastCumlFunding.belowX96
        .{ .int256 = -50 }, // lastCumlFunding.withinInventoryX192
    });
}

fn expectMakerLifecycle(e: events.MakerAdjustedEvent, pos_id: u256, owner: types.Address) !void {
    try std.testing.expectEqual(pos_id, e.pos_id);
    try std.testing.expectEqualSlices(u8, &owner, &e.owner);
    try std.testing.expectEqual(@as(i128, -41), e.margin_delta);
    try std.testing.expectEqual(@as(i128, -42), e.liquidity_delta);
    try std.testing.expectEqual(@as(i256, -43), e.funding);
    try std.testing.expectEqual(@as(u256, 44), e.lp_fees);
    try std.testing.expectEqual(@as(i256, -45), e.delta);
    try std.testing.expectEqual(@as(u128, 46), e.margin);
    try std.testing.expectEqual(@as(u128, 47), e.liquidity);
    try std.testing.expectEqual(@as(i256, -48), e.last_cuml_funding_x96);
    try std.testing.expectEqual(@as(i256, 49), e.last_cuml_funding.below_x96);
    try std.testing.expectEqual(@as(i256, -50), e.last_cuml_funding.within_inventory_x192);
}

test "decodeEvent decodes MakerAdjusted, MakerClosed, and MakerConverted to their own tags" {
    const allocator = std.testing.allocator;
    const data = try makerLifecycleFixture();
    defer allocator.free(data);
    const owner = addr(0xA2);

    const adjusted = fx.positionTopics(events.Topics.MAKER_ADJUSTED, 5, owner);
    try expectMakerLifecycle((try event_decode.decodeEvent(allocator, mkLog(&adjusted, data))).?.maker_adjusted, 5, owner);

    const closed = fx.positionTopics(events.Topics.MAKER_CLOSED, 6, owner);
    try expectMakerLifecycle((try event_decode.decodeEvent(allocator, mkLog(&closed, data))).?.maker_closed, 6, owner);

    const converted = fx.positionTopics(events.Topics.MAKER_CONVERTED, 7, owner);
    try expectMakerLifecycle((try event_decode.decodeEvent(allocator, mkLog(&converted, data))).?.maker_converted, 7, owner);
}

test "decodeEvent decodes MakerBackstopped fully" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{ events.Topics.MAKER_BACKSTOPPED, topicU256(21) };
    const data = try enc(&.{
        .{ .uint256 = 61 }, // marginIn
        .{ .address = addr(0x62) }, // posRecipient
        .{ .int256 = -63 }, // funding
        .{ .uint256 = 64 }, // lpFees
        .{ .uint256 = 65 }, // margin
        .{ .int256 = -66 }, // delta
        .{ .uint256 = 67 }, // liquidity
        .{ .int256 = -68 }, // lastCumlFundingX96
        .{ .int256 = 69 }, // lastCumlFunding.belowX96
        .{ .int256 = -70 }, // lastCumlFunding.withinInventoryX192
    });
    defer allocator.free(data);

    const mb = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.maker_backstopped;
    try std.testing.expectEqual(@as(u256, 21), mb.pos_id);
    try std.testing.expectEqual(@as(u128, 61), mb.margin_in);
    try std.testing.expectEqualSlices(u8, &addr(0x62), &mb.pos_recipient);
    try std.testing.expectEqual(@as(i256, -63), mb.funding);
    try std.testing.expectEqual(@as(u256, 64), mb.lp_fees);
    try std.testing.expectEqual(@as(u128, 65), mb.margin);
    try std.testing.expectEqual(@as(i256, -66), mb.delta);
    try std.testing.expectEqual(@as(u128, 67), mb.liquidity);
    try std.testing.expectEqual(@as(i256, -68), mb.last_cuml_funding_x96);
    try std.testing.expectEqual(@as(i256, 69), mb.last_cuml_funding.below_x96);
    try std.testing.expectEqual(@as(i256, -70), mb.last_cuml_funding.within_inventory_x192);
}

test "decodeEvent decodes MakerMoved fully" {
    const allocator = std.testing.allocator;
    const topics = fx.positionTopics(events.Topics.MAKER_MOVED, 22, addr(0xA3));
    const data = try enc(&.{
        .{ .int256 = -300 }, // oldTickLower
        .{ .int256 = 300 }, // oldTickUpper
        .{ .int256 = -90 }, // newTickLower
        .{ .int256 = 120 }, // newTickUpper
        .{ .uint256 = 71 }, // oldLiquidity
        .{ .uint256 = 72 }, // newLiquidity
        .{ .int256 = -73 }, // marginDelta
        .{ .int256 = -74 }, // funding
        .{ .uint256 = 75 }, // lpFees
    });
    defer allocator.free(data);

    const mm = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.maker_moved;
    try std.testing.expectEqual(@as(u256, 22), mm.pos_id);
    try std.testing.expectEqualSlices(u8, &addr(0xA3), &mm.owner);
    try std.testing.expectEqual(@as(i24, -300), mm.old_tick_lower);
    try std.testing.expectEqual(@as(i24, 300), mm.old_tick_upper);
    try std.testing.expectEqual(@as(i24, -90), mm.new_tick_lower);
    try std.testing.expectEqual(@as(i24, 120), mm.new_tick_upper);
    try std.testing.expectEqual(@as(u128, 71), mm.old_liquidity);
    try std.testing.expectEqual(@as(u128, 72), mm.new_liquidity);
    try std.testing.expectEqual(@as(i128, -73), mm.margin_delta);
    try std.testing.expectEqual(@as(i256, -74), mm.funding);
    try std.testing.expectEqual(@as(u256, 75), mm.lp_fees);
}

test "decodeEvent decodes TakerAdjusted to its own tag" {
    const allocator = std.testing.allocator;
    const topics = fx.positionTopics(events.Topics.TAKER_ADJUSTED, 23, addr(0xA4));
    const data = try enc(&(.{AbiValue{ .int256 = 500 }} ++ fx.zero_swap_result ++ .{
        AbiValue{ .int256 = 1 },
        AbiValue{ .uint256 = 2 },
        AbiValue{ .int256 = 3 },
        AbiValue{ .uint256 = 4 },
        AbiValue{ .int256 = 5 },
    }));
    defer allocator.free(data);

    const ta = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.taker_adjusted;
    try std.testing.expectEqual(@as(u256, 23), ta.pos_id);
    try std.testing.expectEqualSlices(u8, &addr(0xA4), &ta.owner);
    try std.testing.expectEqual(@as(i128, 500), ta.margin_delta);
    try std.testing.expectEqual(@as(i256, 1), ta.funding);
    try std.testing.expectEqual(@as(u256, 2), ta.util_fees);
    try std.testing.expectEqual(@as(i256, 3), ta.delta);
    try std.testing.expectEqual(@as(u128, 4), ta.margin);
    try std.testing.expectEqual(@as(i256, 5), ta.last_cuml_funding_x96);
}

test "decodeEvent decodes TakerBackstopped fully" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{ events.Topics.TAKER_BACKSTOPPED, topicU256(24) };
    const data = try enc(&.{
        .{ .uint256 = 81 }, // marginIn
        .{ .address = addr(0x82) }, // posRecipient
        .{ .int256 = -83 }, // funding
        .{ .uint256 = 84 }, // utilFees
        .{ .int256 = -85 }, // delta
        .{ .uint256 = 86 }, // margin
        .{ .int256 = -87 }, // lastCumlFundingX96
    });
    defer allocator.free(data);

    const tb = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.taker_backstopped;
    try std.testing.expectEqual(@as(u256, 24), tb.pos_id);
    try std.testing.expectEqual(@as(u128, 81), tb.margin_in);
    try std.testing.expectEqualSlices(u8, &addr(0x82), &tb.pos_recipient);
    try std.testing.expectEqual(@as(i256, -83), tb.funding);
    try std.testing.expectEqual(@as(u256, 84), tb.util_fees);
    try std.testing.expectEqual(@as(i256, -85), tb.delta);
    try std.testing.expectEqual(@as(u128, 86), tb.margin);
    try std.testing.expectEqual(@as(i256, -87), tb.last_cuml_funding_x96);
}

test "decodeEvent decodes MakerLiquidated and TakerLiquidated with the indexed fee recipient" {
    const allocator = std.testing.allocator;
    const keeper = addr(0x4B);
    const data = try enc(&.{ .{ .uint256 = 9_000 }, .{ .uint256 = 250_000 } });
    defer allocator.free(data);

    const maker = fx.positionTopics(events.Topics.MAKER_LIQUIDATED, 30, keeper);
    const ml = (try event_decode.decodeEvent(allocator, mkLog(&maker, data))).?.maker_liquidated;
    try std.testing.expectEqual(@as(u256, 30), ml.pos_id);
    try std.testing.expectEqualSlices(u8, &keeper, &ml.fee_recipient);
    try std.testing.expectEqual(@as(u128, 9_000), ml.liquidity_amount);
    try std.testing.expectEqual(@as(u256, 250_000), ml.liq_fee);

    const taker = fx.positionTopics(events.Topics.TAKER_LIQUIDATED, 31, keeper);
    const tl = (try event_decode.decodeEvent(allocator, mkLog(&taker, data))).?.taker_liquidated;
    try std.testing.expectEqual(@as(u256, 31), tl.pos_id);
    try std.testing.expectEqualSlices(u8, &keeper, &tl.fee_recipient);
    try std.testing.expectEqual(@as(u128, 9_000), tl.perp_amount);
    try std.testing.expectEqual(@as(u256, 250_000), tl.liq_fee);
}

test "decodeEvent decodes PositionOwnerUpdated entirely from topics" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{
        events.Topics.POSITION_OWNER_UPDATED,
        topicU256(40),
        topicAddr(addr(0xA5)),
        topicAddr(types.ZERO_ADDRESS),
    };

    const ou = (try event_decode.decodeEvent(allocator, mkLog(&topics, &.{}))).?.position_owner_updated;
    try std.testing.expectEqual(@as(u256, 40), ou.pos_id);
    try std.testing.expectEqualSlices(u8, &addr(0xA5), &ou.old_owner);
    // A zero new owner is how a close or full liquidation is reported.
    try std.testing.expectEqualSlices(u8, &types.ZERO_ADDRESS, &ou.new_owner);
}

test "decodeEvent decodes QuoteFolded" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{ events.Topics.QUOTE_FOLDED, topicU256(41) };
    const data = try enc(&.{.{ .int256 = -1_250_000 }});
    defer allocator.free(data);

    const qf = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.quote_folded;
    try std.testing.expectEqual(@as(u256, 41), qf.pos_id);
    try std.testing.expectEqual(@as(i256, -1_250_000), qf.amount);
}

test "decodeEvent decodes RatesAndEmasRefreshed, flattening Rates and PricePair" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{events.Topics.RATES_AND_EMAS_REFRESHED};
    const data = try enc(&.{
        .{ .int256 = -91 }, // rates.fundingPerDay
        .{ .uint256 = 92 }, // rates.longUtilFeePerDay
        .{ .uint256 = 93 }, // rates.shortUtilFeePerDay
        .{ .uint256 = 1_700_000_094 }, // rates.lastTouch
        .{ .uint256 = 95 }, // rates.lastMark
        .{ .uint256 = 96 }, // index
        .{ .uint256 = 97 }, // emas.ammPrice
        .{ .uint256 = 98 }, // emas.index
    });
    defer allocator.free(data);

    const rr = (try event_decode.decodeEvent(allocator, mkLog(&topics, data))).?.rates_and_emas_refreshed;
    try std.testing.expectEqual(@as(i256, -91), rr.rates.funding_per_day);
    try std.testing.expectEqual(@as(u64, 92), rr.rates.long_util_fee_per_day);
    try std.testing.expectEqual(@as(u64, 93), rr.rates.short_util_fee_per_day);
    try std.testing.expectEqual(@as(u64, 1_700_000_094), rr.rates.last_touch);
    try std.testing.expectEqual(@as(u256, 95), rr.rates.last_mark);
    try std.testing.expectEqual(@as(u128, 96), rr.index);
    try std.testing.expectEqual(@as(u128, 97), rr.emas.amm_price);
    try std.testing.expectEqual(@as(u128, 98), rr.emas.index);
}

test "decodeEvent decodes BadDebtAccounted and PhysicalCapacityUpdated" {
    const allocator = std.testing.allocator;

    const bd_topics = [_][32]u8{events.Topics.BAD_DEBT_ACCOUNTED};
    const bd_data = try enc(&.{ .{ .uint256 = 1 }, .{ .uint256 = 2 }, .{ .uint256 = 3 }, .{ .uint256 = 4 } });
    defer allocator.free(bd_data);
    const bd = (try event_decode.decodeEvent(allocator, mkLog(&bd_topics, bd_data))).?.bad_debt_accounted;
    try std.testing.expectEqual(@as(u256, 1), bd.bad_debt);
    try std.testing.expectEqual(@as(u256, 2), bd.insurance_consumed);
    try std.testing.expectEqual(@as(u256, 3), bd.insurance_after);
    try std.testing.expectEqual(@as(u128, 4), bd.bad_debt_after);

    const pc_topics = [_][32]u8{events.Topics.PHYSICAL_CAPACITY_UPDATED};
    const pc_data = try enc(&.{ .{ .uint256 = 5 << 64 }, .{ .uint256 = 6 << 64 } });
    defer allocator.free(pc_data);
    const pc = (try event_decode.decodeEvent(allocator, mkLog(&pc_topics, pc_data))).?.physical_capacity_updated;
    try std.testing.expectEqual(@as(u256, 5 << 64), pc.long_close_x64);
    try std.testing.expectEqual(@as(u256, 6 << 64), pc.short_close_x64);
}

test "decodeEvent decodes PerpCreated, flattening Modules" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{events.Topics.PERP_CREATED};

    var pool_id: [32]u8 = undefined;
    for (&pool_id, 0..) |*b, i| b.* = @intCast(i + 1);

    const data = try enc(&.{
        .{ .address = addr(0xA0) }, // perp
        .{ .fixed_bytes = .{ .data = pool_id, .len = 32 } }, // poolId
        .{ .address = addr(0xB1) },
        .{ .address = addr(0xB2) },
        .{ .address = addr(0xB3) },
        .{ .address = addr(0xB4) }, .{ .address = addr(0xB5) }, .{ .address = addr(0xB6) }, // Modules
        .{ .uint256 = 123_456 }, // initialIndex
        .{ .uint256 = 300 }, // emaWindow (uint24)
        .{ .uint256 = 900 }, // latency (uint32)
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
    try std.testing.expectEqual(@as(u32, 900), pc.latency);
    try std.testing.expectEqual(@as(u256, 5000), pc.protocol_fee);
    try std.testing.expectEqual(@as(u256, @as(u256, 1) << 96), pc.sqrt_price_x96);
    try std.testing.expectEqual(@as(i24, -60), pc.tick);
    try std.testing.expectEqualSlices(u8, &addr(0xEE), &pc.owner);
}

test "decodeEvent errors when an indexed parameter's topic is missing" {
    const allocator = std.testing.allocator;
    // A TakerLiquidated log with only topic0: a pre-v1.0.0 style log, or one
    // from a contract that reuses the name without indexing.
    const topics = [_][32]u8{events.Topics.TAKER_LIQUIDATED};
    const data = try enc(&.{ .{ .uint256 = 1 }, .{ .uint256 = 2 } });
    defer allocator.free(data);

    try std.testing.expectError(
        event_decode.DecodeError.MissingIndexedTopic,
        event_decode.decodeEvent(allocator, mkLog(&topics, data)),
    );
}

test "decodeEvent returns null for an unknown topic0" {
    const allocator = std.testing.allocator;
    const topics = [_][32]u8{@as([32]u8, @splat(0xAB))};
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
