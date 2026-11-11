const std = @import("std");
const types = @import("types.zig");

// =============================================================================
// Event types matching the perpcity-contracts v1.0.0 Perp + PerpFactory events.
// =============================================================================
//
// On every position event `posId` is indexed, and so are `owner` and
// `feeRecipient` where present; the decoder reads those from the log topics.
//
// A liquidation is reported as the position's lifecycle event (`*Adjusted` for
// a partial, `*Closed` for a full, `MakerConverted` when a maker is left with
// taker exposure) followed in the same transaction by `MakerLiquidated` /
// `TakerLiquidated`, which carries the fee recipient and the fee. The lifecycle
// events no longer carry an `isLiquidation` flag.

/// The per-swap balances and fees reported by taker events.
/// Mirror of `struct SwapResult` in Structs.sol.
pub const SwapResult = struct {
    /// BalanceDelta packed as int256: amount0 in high 128 bits, amount1 in low 128 bits.
    delta: i256,
    amm_price: u256,
    total_fee_amt: i256,
    lp_fee_amt: u256,
    protocol_fee_amt: u256,
    creator_fee_amt: u256,
    insurance_fee_amt: u256,
    /// Protocol, creator, and insurance fees finalized after socialization and
    /// debt repayment.
    fee_fund_fee_amt: u256,
};

pub const PerpCreatedEvent = struct {
    perp: types.Address,
    pool_id: types.Bytes32,
    modules: types.Modules,
    initial_index: u256,
    ema_window: u24,
    latency: u32,
    protocol_fee: u256,
    sqrt_price_x96: u256,
    tick: i24,
    owner: types.Address,
};

pub const MakerOpenedEvent = struct {
    pos_id: u256,
    owner: types.Address,
    tick_lower: i24,
    tick_upper: i24,
    liquidity: u128,
    /// Packed BalanceDelta: the signed perp and USD accounting balances.
    delta: i256,
    last_cuml_funding_x96: i256,
    last_cuml_funding: types.MakerFunding,
};

/// Shared layout of `MakerAdjusted`, `MakerClosed`, and `MakerConverted`.
/// `lp_fees` combines swap-LP and utilization earnings; the fields after it
/// are post-action levels (zero liquidity after a close or conversion).
pub const MakerAdjustedEvent = struct {
    pos_id: u256,
    owner: types.Address,
    /// Positive deposits, negative withdraws.
    margin_delta: i128,
    /// Signed liquidity change, including liquidations.
    liquidity_delta: i128,
    /// Positive amounts are owed by the position.
    funding: i256,
    lp_fees: u256,
    delta: i256,
    margin: u128,
    liquidity: u128,
    last_cuml_funding_x96: i256,
    last_cuml_funding: types.MakerFunding,
};

pub const MakerClosedEvent = MakerAdjustedEvent;
pub const MakerConvertedEvent = MakerAdjustedEvent;

pub const MakerBackstoppedEvent = struct {
    pos_id: u256,
    margin_in: u128,
    pos_recipient: types.Address,
    funding: i256,
    lp_fees: u256,
    margin: u128,
    delta: i256,
    liquidity: u128,
    last_cuml_funding_x96: i256,
    last_cuml_funding: types.MakerFunding,
};

pub const MakerLiquidatedEvent = struct {
    pos_id: u256,
    fee_recipient: types.Address,
    liquidity_amount: u128,
    /// The capped liquidation fee before any bad-debt payout haircut.
    liq_fee: u256,
};

pub const MakerMovedEvent = struct {
    pos_id: u256,
    owner: types.Address,
    old_tick_lower: i24,
    old_tick_upper: i24,
    new_tick_lower: i24,
    new_tick_upper: i24,
    old_liquidity: u128,
    new_liquidity: u128,
    margin_delta: i128,
    funding: i256,
    lp_fees: u256,
};

pub const TakerOpenedEvent = struct {
    pos_id: u256,
    owner: types.Address,
    /// The posted margin before swap fees; stored margin is this minus
    /// `sr.total_fee_amt`.
    margin: u128,
    sr: SwapResult,
    last_cuml_funding_x96: i256,
};

/// Shared layout of `TakerAdjusted` and `TakerClosed`. `sr.delta` is the swap's
/// change; the fields after `util_fees` are post-action levels.
pub const TakerAdjustedEvent = struct {
    pos_id: u256,
    owner: types.Address,
    margin_delta: i128,
    sr: SwapResult,
    funding: i256,
    util_fees: u256,
    delta: i256,
    margin: u128,
    last_cuml_funding_x96: i256,
};

pub const TakerClosedEvent = TakerAdjustedEvent;

pub const TakerBackstoppedEvent = struct {
    pos_id: u256,
    margin_in: u128,
    pos_recipient: types.Address,
    funding: i256,
    util_fees: u256,
    delta: i256,
    margin: u128,
    last_cuml_funding_x96: i256,
};

pub const TakerLiquidatedEvent = struct {
    pos_id: u256,
    fee_recipient: types.Address,
    perp_amount: u128,
    /// The capped liquidation fee before any bad-debt payout haircut.
    liq_fee: u256,
};

/// Emitted when a position opens (`old_owner` zero), closes or is fully
/// liquidated (`new_owner` zero), or changes owner through a backstop.
pub const PositionOwnerUpdatedEvent = struct {
    pos_id: u256,
    old_owner: types.Address,
    new_owner: types.Address,
};

/// Quote balance moved into settled margin without changing equity.
pub const QuoteFoldedEvent = struct {
    pos_id: u256,
    amount: i256,
};

pub const DonatedEvent = struct {
    donor: types.Address,
    amount: u128,
    bad_debt: u128,
    insurance: u80,
};

pub const OpenInterestUpdatedEvent = struct {
    oi: types.OpenInterest,
};

pub const CapacityUpdatedEvent = struct {
    cap: types.Capacity,
};

/// The full-book closing-capacity ledger, scaled by 2^64.
pub const PhysicalCapacityUpdatedEvent = struct {
    long_close_x64: u256,
    short_close_x64: u256,
};

/// Emitted whenever a market accrues: the refreshed rates and cached mark, the
/// beacon index used for the refresh (Q96), and the AMM-price / index EMAs.
/// This is the only place the EMAs are published.
pub const RatesAndEmasRefreshedEvent = struct {
    rates: types.Rates,
    index: u128,
    emas: types.PricePair,
};

/// A negative-equity position consumed insurance; `bad_debt_after` is the
/// market's outstanding uncovered bad debt. Amounts use USDC decimals.
pub const BadDebtAccountedEvent = struct {
    bad_debt: u256,
    insurance_consumed: u256,
    insurance_after: u256,
    bad_debt_after: u128,
};

pub const IndexUpdatedEvent = struct {
    index: u256,
};

pub const EventType = enum {
    perp_created,
    maker_opened,
    maker_adjusted,
    maker_closed,
    maker_converted,
    maker_backstopped,
    maker_liquidated,
    maker_moved,
    taker_opened,
    taker_adjusted,
    taker_closed,
    taker_backstopped,
    taker_liquidated,
    position_owner_updated,
    quote_folded,
    donated,
    open_interest_updated,
    capacity_updated,
    physical_capacity_updated,
    rates_and_emas_refreshed,
    bad_debt_accounted,
    index_updated,
    new_block,
};

// =============================================================================
// Pre-computed event topic hashes (keccak256 of canonical event signature)
// =============================================================================

const swap_result_sig = "(int256,uint256,int256,uint256,uint256,uint256,uint256,uint256)";
const maker_lifecycle_args =
    "(uint256,address,int128,int128,int256,uint256,int256,uint128,uint128,int256,(int256,int256))";
const taker_lifecycle_args =
    "(uint256,address,int128," ++ swap_result_sig ++ ",int256,uint256,int256,uint128,int256)";

pub const Topics = struct {
    pub const PERP_CREATED: [32]u8 = computeTopicHash(
        "PerpCreated(address,bytes32,(address,address,address,address,address,address),uint256,uint24,uint32,uint256,uint160,int24,address)",
    );

    pub const MAKER_OPENED: [32]u8 = computeTopicHash(
        "MakerOpened(uint256,address,int24,int24,uint128,int256,int256,(int256,int256))",
    );
    pub const MAKER_ADJUSTED: [32]u8 = computeTopicHash("MakerAdjusted" ++ maker_lifecycle_args);
    pub const MAKER_CLOSED: [32]u8 = computeTopicHash("MakerClosed" ++ maker_lifecycle_args);
    pub const MAKER_CONVERTED: [32]u8 = computeTopicHash("MakerConverted" ++ maker_lifecycle_args);
    pub const MAKER_BACKSTOPPED: [32]u8 = computeTopicHash(
        "MakerBackstopped(uint256,uint128,address,int256,uint256,uint128,int256,uint128,int256,(int256,int256))",
    );
    pub const MAKER_LIQUIDATED: [32]u8 = computeTopicHash("MakerLiquidated(uint256,address,uint128,uint256)");
    pub const MAKER_MOVED: [32]u8 = computeTopicHash(
        "MakerMoved(uint256,address,int24,int24,int24,int24,uint128,uint128,int128,int256,uint256)",
    );

    pub const TAKER_OPENED: [32]u8 = computeTopicHash(
        "TakerOpened(uint256,address,uint128," ++ swap_result_sig ++ ",int256)",
    );
    pub const TAKER_ADJUSTED: [32]u8 = computeTopicHash("TakerAdjusted" ++ taker_lifecycle_args);
    pub const TAKER_CLOSED: [32]u8 = computeTopicHash("TakerClosed" ++ taker_lifecycle_args);
    pub const TAKER_BACKSTOPPED: [32]u8 = computeTopicHash(
        "TakerBackstopped(uint256,uint128,address,int256,uint256,int256,uint128,int256)",
    );
    pub const TAKER_LIQUIDATED: [32]u8 = computeTopicHash("TakerLiquidated(uint256,address,uint128,uint256)");

    pub const POSITION_OWNER_UPDATED: [32]u8 = computeTopicHash("PositionOwnerUpdated(uint256,address,address)");
    pub const QUOTE_FOLDED: [32]u8 = computeTopicHash("QuoteFolded(uint256,int256)");

    pub const DONATED: [32]u8 = computeTopicHash("Donated(address,uint128,uint128,uint80)");
    pub const OPEN_INTEREST_UPDATED: [32]u8 = computeTopicHash("OpenInterestUpdated((uint128,uint128))");
    pub const CAPACITY_UPDATED: [32]u8 = computeTopicHash("CapacityUpdated((uint128,uint128))");
    pub const PHYSICAL_CAPACITY_UPDATED: [32]u8 = computeTopicHash("PhysicalCapacityUpdated((uint256,uint256))");
    pub const RATES_AND_EMAS_REFRESHED: [32]u8 = computeTopicHash(
        "RatesAndEmasRefreshed((int88,uint64,uint64,uint40,uint256),uint128,(uint128,uint128))",
    );
    pub const BAD_DEBT_ACCOUNTED: [32]u8 = computeTopicHash("BadDebtAccounted(uint256,uint256,uint256,uint128)");

    pub const INDEX_UPDATED: [32]u8 = computeTopicHash("IndexUpdated(uint256)");

    /// Compute the keccak256 hash of an event signature at compile time.
    pub fn computeTopicHash(comptime sig: []const u8) [32]u8 {
        @setEvalBranchQuota(50_000);
        var out: [32]u8 = undefined;
        std.crypto.hash.sha3.Keccak256.hash(sig, &out, .{});
        return out;
    }
};

/// Every recognized topic paired with its event type.
const topic_table = [_]struct { topic: [32]u8, event_type: EventType }{
    .{ .topic = Topics.PERP_CREATED, .event_type = .perp_created },
    .{ .topic = Topics.MAKER_OPENED, .event_type = .maker_opened },
    .{ .topic = Topics.MAKER_ADJUSTED, .event_type = .maker_adjusted },
    .{ .topic = Topics.MAKER_CLOSED, .event_type = .maker_closed },
    .{ .topic = Topics.MAKER_CONVERTED, .event_type = .maker_converted },
    .{ .topic = Topics.MAKER_BACKSTOPPED, .event_type = .maker_backstopped },
    .{ .topic = Topics.MAKER_LIQUIDATED, .event_type = .maker_liquidated },
    .{ .topic = Topics.MAKER_MOVED, .event_type = .maker_moved },
    .{ .topic = Topics.TAKER_OPENED, .event_type = .taker_opened },
    .{ .topic = Topics.TAKER_ADJUSTED, .event_type = .taker_adjusted },
    .{ .topic = Topics.TAKER_CLOSED, .event_type = .taker_closed },
    .{ .topic = Topics.TAKER_BACKSTOPPED, .event_type = .taker_backstopped },
    .{ .topic = Topics.TAKER_LIQUIDATED, .event_type = .taker_liquidated },
    .{ .topic = Topics.POSITION_OWNER_UPDATED, .event_type = .position_owner_updated },
    .{ .topic = Topics.QUOTE_FOLDED, .event_type = .quote_folded },
    .{ .topic = Topics.DONATED, .event_type = .donated },
    .{ .topic = Topics.OPEN_INTEREST_UPDATED, .event_type = .open_interest_updated },
    .{ .topic = Topics.CAPACITY_UPDATED, .event_type = .capacity_updated },
    .{ .topic = Topics.PHYSICAL_CAPACITY_UPDATED, .event_type = .physical_capacity_updated },
    .{ .topic = Topics.RATES_AND_EMAS_REFRESHED, .event_type = .rates_and_emas_refreshed },
    .{ .topic = Topics.BAD_DEBT_ACCOUNTED, .event_type = .bad_debt_accounted },
    .{ .topic = Topics.INDEX_UPDATED, .event_type = .index_updated },
};

// =============================================================================
// Subscription registry
// =============================================================================

pub const Subscription = struct {
    id: u64,
    event_type: EventType,
    /// Optional filter: only match events emitted by this Perp market.
    perp_filter: ?types.Address = null,
    active: bool = true,
};

/// Manages event subscriptions for WebSocket event streaming.
///
/// Thread safety: NOT thread-safe. Callers must synchronize access externally
/// if used from multiple threads.
pub const EventRegistry = struct {
    subscriptions: std.AutoHashMap(u64, Subscription),
    next_id: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EventRegistry {
        return .{
            .subscriptions = std.AutoHashMap(u64, Subscription).init(allocator),
            .next_id = 1,
            .allocator = allocator,
        };
    }

    /// Register a subscription. Returns the subscription ID.
    pub fn subscribe(self: *EventRegistry, event_type: EventType, perp_filter: ?types.Address) !u64 {
        const id = self.next_id;
        self.next_id += 1;

        try self.subscriptions.put(id, .{
            .id = id,
            .event_type = event_type,
            .perp_filter = perp_filter,
            .active = true,
        });

        return id;
    }

    /// Unsubscribe by ID. Returns true if the subscription was active and is now deactivated.
    pub fn unsubscribe(self: *EventRegistry, id: u64) bool {
        if (self.subscriptions.getPtr(id)) |sub| {
            if (sub.active) {
                sub.active = false;
                return true;
            }
        }
        return false;
    }

    /// Get count of active subscriptions matching an event type and optional perp address.
    pub fn matchingCount(self: *const EventRegistry, event_type: EventType, perp: ?types.Address) usize {
        var count: usize = 0;
        var iter = self.subscriptions.valueIterator();
        while (iter.next()) |sub| {
            if (!sub.active) continue;
            if (sub.event_type != event_type) continue;

            if (sub.perp_filter) |filter| {
                if (perp) |p| {
                    if (std.mem.eql(u8, &filter, &p)) {
                        count += 1;
                    }
                }
            } else {
                count += 1;
            }
        }
        return count;
    }

    pub fn activeCount(self: *const EventRegistry) usize {
        var count: usize = 0;
        var iter = self.subscriptions.valueIterator();
        while (iter.next()) |sub| {
            if (sub.active) count += 1;
        }
        return count;
    }

    pub fn deinit(self: *EventRegistry) void {
        self.subscriptions.deinit();
    }
};

// =============================================================================
// Log identification helpers
// =============================================================================

/// Identify event type from a log topic (topic0).
pub fn identifyEvent(topic0: [32]u8) ?EventType {
    for (topic_table) |entry| {
        if (std.mem.eql(u8, &topic0, &entry.topic)) return entry.event_type;
    }
    return null;
}

// =============================================================================
// Internal tests
// =============================================================================

test "Topics are 32-byte non-zero hashes" {
    const zero = @as([32]u8, @splat(0));
    for (topic_table) |entry| {
        try std.testing.expect(!std.mem.eql(u8, &entry.topic, &zero));
    }
}

test "All topic hashes are distinct" {
    for (0..topic_table.len) |i| {
        for ((i + 1)..topic_table.len) |j| {
            try std.testing.expect(!std.mem.eql(u8, &topic_table[i].topic, &topic_table[j].topic));
        }
    }
}

test "topic table covers every log-backed event type" {
    // `new_block` is the only variant with no log behind it.
    try std.testing.expectEqual(@typeInfo(EventType).@"enum".fields.len - 1, topic_table.len);
}

test "identifyEvent returns correct event type for each topic" {
    for (topic_table) |entry| {
        try std.testing.expectEqual(entry.event_type, identifyEvent(entry.topic).?);
    }
}

test "identifyEvent returns null for unknown topic" {
    const unknown = @as([32]u8, @splat(0xff));
    try std.testing.expectEqual(@as(?EventType, null), identifyEvent(unknown));

    const zero = @as([32]u8, @splat(0));
    try std.testing.expectEqual(@as(?EventType, null), identifyEvent(zero));
}

test "EventRegistry subscribe and unsubscribe" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id1 = try registry.subscribe(.maker_opened, null);
    const id2 = try registry.subscribe(.taker_opened, null);

    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(usize, 2), registry.activeCount());

    try std.testing.expect(registry.unsubscribe(id1));
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());

    try std.testing.expect(!registry.unsubscribe(id1));
    try std.testing.expect(!registry.unsubscribe(9999));
}

test "EventRegistry matchingCount without filter" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    _ = try registry.subscribe(.maker_opened, null);
    _ = try registry.subscribe(.maker_opened, null);
    _ = try registry.subscribe(.taker_opened, null);

    try std.testing.expectEqual(@as(usize, 2), registry.matchingCount(.maker_opened, null));
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.taker_opened, null));
    try std.testing.expectEqual(@as(usize, 0), registry.matchingCount(.index_updated, null));
}

test "EventRegistry matchingCount with perp filter" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const perp_a: types.Address = @splat(0xAA);
    const perp_b: types.Address = @splat(0xBB);

    _ = try registry.subscribe(.maker_opened, perp_a);
    _ = try registry.subscribe(.maker_opened, null);

    try std.testing.expectEqual(@as(usize, 2), registry.matchingCount(.maker_opened, perp_a));
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.maker_opened, perp_b));
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.maker_opened, null));
}

test "computeTopicHash is deterministic" {
    const hash1 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    const hash2 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}
