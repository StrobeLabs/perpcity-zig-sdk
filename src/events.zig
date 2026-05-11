const std = @import("std");
const types = @import("types.zig");

// =============================================================================
// Event types matching the perpcity-contracts v0.1.0 Perp + PerpFactory events.
// =============================================================================
//
// SwapResult is the per-swap delta block reported by taker events.
// Mirror of `struct SwapResult` in SharedStructs.sol.
pub const SwapResult = struct {
    /// BalanceDelta packed as int256: amount0 in high 128 bits, amount1 in low 128 bits.
    delta: i256,
    amm_price: u256,
    total_fee_amt: i256,
    lp_fee_amt: u256,
    protocol_fee_amt: u256,
    creator_fee_amt: u256,
    insurance_fee_amt: u256,
};

pub const PerpCreatedEvent = struct {
    perp: types.Address,
    pool_id: types.Bytes32,
    modules: types.Modules,
    initial_index: u256,
    ema_window: u24,
    protocol_fee: u256,
    sqrt_price_x96: u256,
    tick: i24,
    owner: types.Address,
};

pub const MakerOpenedEvent = struct {
    pos_id: u256,
};

pub const MakerAdjustedEvent = struct {
    pos_id: u256,
    funding: i256,
    long_util_fees: u256,
    short_util_fees: u256,
    lp_fees: u256,
};

pub const MakerClosedEvent = struct {
    pos_id: u256,
    funding: i256,
    long_util_fees: u256,
    short_util_fees: u256,
    lp_fees: u256,
    liq_fee: u256,
    is_liquidation: bool,
};

pub const MakerConvertedEvent = struct {
    pos_id: u256,
    funding: i256,
    long_util_fees: u256,
    short_util_fees: u256,
    lp_fees: u256,
    liq_fee: u256,
    is_liquidation: bool,
};

pub const MakerBackstoppedEvent = struct {
    pos_id: u256,
    margin_in: u128,
    pos_recipient: types.Address,
    funding: i256,
    long_util_fees: u256,
    short_util_fees: u256,
    lp_fees: u256,
};

pub const TakerOpenedEvent = struct {
    pos_id: u256,
    sr: SwapResult,
};

pub const TakerAdjustedEvent = struct {
    pos_id: u256,
    sr: SwapResult,
    funding: i256,
    util_fees: u256,
};

pub const TakerClosedEvent = struct {
    pos_id: u256,
    sr: SwapResult,
    funding: i256,
    util_fees: u256,
    liq_fee: u256,
    is_liquidation: bool,
};

pub const TakerBackstoppedEvent = struct {
    pos_id: u256,
    margin_in: u128,
    pos_recipient: types.Address,
    funding: i256,
    util_fees: u256,
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
    taker_opened,
    taker_adjusted,
    taker_closed,
    taker_backstopped,
    donated,
    open_interest_updated,
    capacity_updated,
    index_updated,
    new_block,
};

// =============================================================================
// Pre-computed event topic hashes (keccak256 of canonical event signature)
// =============================================================================

pub const Topics = struct {
    pub const PERP_CREATED: [32]u8 = computeTopicHash(
        "PerpCreated(address,bytes32,(address,address,address,address,address,address),uint256,uint24,uint256,uint160,int24,address,string,string,string)",
    );

    pub const MAKER_OPENED: [32]u8 = computeTopicHash("MakerOpened(uint256)");
    pub const MAKER_ADJUSTED: [32]u8 = computeTopicHash(
        "MakerAdjusted(uint256,int256,uint256,uint256,uint256)",
    );
    pub const MAKER_CLOSED: [32]u8 = computeTopicHash(
        "MakerClosed(uint256,int256,uint256,uint256,uint256,uint256,bool)",
    );
    pub const MAKER_CONVERTED: [32]u8 = computeTopicHash(
        "MakerConverted(uint256,int256,uint256,uint256,uint256,uint256,bool)",
    );
    pub const MAKER_BACKSTOPPED: [32]u8 = computeTopicHash(
        "MakerBackstopped(uint256,uint128,address,int256,uint256,uint256,uint256)",
    );

    pub const TAKER_OPENED: [32]u8 = computeTopicHash(
        "TakerOpened(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256))",
    );
    pub const TAKER_ADJUSTED: [32]u8 = computeTopicHash(
        "TakerAdjusted(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256),int256,uint256)",
    );
    pub const TAKER_CLOSED: [32]u8 = computeTopicHash(
        "TakerClosed(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256),int256,uint256,uint256,bool)",
    );
    pub const TAKER_BACKSTOPPED: [32]u8 = computeTopicHash(
        "TakerBackstopped(uint256,uint128,address,int256,uint256)",
    );

    pub const DONATED: [32]u8 = computeTopicHash("Donated(address,uint128,uint128,uint80)");
    pub const OPEN_INTEREST_UPDATED: [32]u8 = computeTopicHash("OpenInterestUpdated((uint128,uint128))");
    pub const CAPACITY_UPDATED: [32]u8 = computeTopicHash("CapacityUpdated((uint128,uint128))");

    pub const INDEX_UPDATED: [32]u8 = computeTopicHash("IndexUpdated(uint256)");

    /// Compute the keccak256 hash of an event signature at compile time.
    pub fn computeTopicHash(comptime sig: []const u8) [32]u8 {
        @setEvalBranchQuota(50_000);
        var out: [32]u8 = undefined;
        std.crypto.hash.sha3.Keccak256.hash(sig, &out, .{});
        return out;
    }
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
    if (std.mem.eql(u8, &topic0, &Topics.PERP_CREATED)) return .perp_created;
    if (std.mem.eql(u8, &topic0, &Topics.MAKER_OPENED)) return .maker_opened;
    if (std.mem.eql(u8, &topic0, &Topics.MAKER_ADJUSTED)) return .maker_adjusted;
    if (std.mem.eql(u8, &topic0, &Topics.MAKER_CLOSED)) return .maker_closed;
    if (std.mem.eql(u8, &topic0, &Topics.MAKER_CONVERTED)) return .maker_converted;
    if (std.mem.eql(u8, &topic0, &Topics.MAKER_BACKSTOPPED)) return .maker_backstopped;
    if (std.mem.eql(u8, &topic0, &Topics.TAKER_OPENED)) return .taker_opened;
    if (std.mem.eql(u8, &topic0, &Topics.TAKER_ADJUSTED)) return .taker_adjusted;
    if (std.mem.eql(u8, &topic0, &Topics.TAKER_CLOSED)) return .taker_closed;
    if (std.mem.eql(u8, &topic0, &Topics.TAKER_BACKSTOPPED)) return .taker_backstopped;
    if (std.mem.eql(u8, &topic0, &Topics.DONATED)) return .donated;
    if (std.mem.eql(u8, &topic0, &Topics.OPEN_INTEREST_UPDATED)) return .open_interest_updated;
    if (std.mem.eql(u8, &topic0, &Topics.CAPACITY_UPDATED)) return .capacity_updated;
    if (std.mem.eql(u8, &topic0, &Topics.INDEX_UPDATED)) return .index_updated;
    return null;
}

// =============================================================================
// Internal tests
// =============================================================================

test "Topics are 32-byte non-zero hashes" {
    const zero = [_]u8{0} ** 32;
    try std.testing.expect(!std.mem.eql(u8, &Topics.PERP_CREATED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.MAKER_OPENED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.TAKER_OPENED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.INDEX_UPDATED, &zero));
}

test "All topic hashes are distinct" {
    const topics = [_][32]u8{
        Topics.PERP_CREATED,
        Topics.MAKER_OPENED,
        Topics.MAKER_ADJUSTED,
        Topics.MAKER_CLOSED,
        Topics.MAKER_CONVERTED,
        Topics.MAKER_BACKSTOPPED,
        Topics.TAKER_OPENED,
        Topics.TAKER_ADJUSTED,
        Topics.TAKER_CLOSED,
        Topics.TAKER_BACKSTOPPED,
        Topics.DONATED,
        Topics.OPEN_INTEREST_UPDATED,
        Topics.CAPACITY_UPDATED,
        Topics.INDEX_UPDATED,
    };
    for (0..topics.len) |i| {
        for ((i + 1)..topics.len) |j| {
            try std.testing.expect(!std.mem.eql(u8, &topics[i], &topics[j]));
        }
    }
}

test "MakerOpened topic equals keccak256(MakerOpened(uint256))" {
    const expected = Topics.computeTopicHash("MakerOpened(uint256)");
    try std.testing.expectEqualSlices(u8, &expected, &Topics.MAKER_OPENED);
}

test "TakerOpened topic equals canonical signature hash" {
    const expected = Topics.computeTopicHash(
        "TakerOpened(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256))",
    );
    try std.testing.expectEqualSlices(u8, &expected, &Topics.TAKER_OPENED);
}

test "identifyEvent returns correct event type for each topic" {
    try std.testing.expectEqual(EventType.perp_created, identifyEvent(Topics.PERP_CREATED).?);
    try std.testing.expectEqual(EventType.maker_opened, identifyEvent(Topics.MAKER_OPENED).?);
    try std.testing.expectEqual(EventType.taker_opened, identifyEvent(Topics.TAKER_OPENED).?);
    try std.testing.expectEqual(EventType.index_updated, identifyEvent(Topics.INDEX_UPDATED).?);
}

test "identifyEvent returns null for unknown topic" {
    const unknown = [_]u8{0xff} ** 32;
    try std.testing.expectEqual(@as(?EventType, null), identifyEvent(unknown));

    const zero = [_]u8{0} ** 32;
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

    const perp_a: types.Address = [_]u8{0xAA} ** 20;
    const perp_b: types.Address = [_]u8{0xBB} ** 20;

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
