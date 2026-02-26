const std = @import("std");

// =============================================================================
// Event types matching the PerpManager contract events
// =============================================================================

pub const PositionOpenedEvent = struct {
    perp_id: [32]u8,
    pos_id: u256,
    is_maker: bool,
    sqrt_price_x96: u256,
    long_oi: u128,
    short_oi: u128,
};

pub const PositionClosedEvent = struct {
    perp_id: [32]u8,
    pos_id: u256,
    was_maker: bool,
    was_liquidated: bool,
    was_partial_close: bool,
};

pub const IndexUpdatedEvent = struct {
    index: u256,
};

pub const PerpCreatedEvent = struct {
    perp_id: [32]u8,
};

pub const EventType = enum {
    position_opened,
    position_closed,
    index_updated,
    perp_created,
    new_block,
};

// =============================================================================
// Pre-computed event topic hashes (keccak256 of event signature)
// =============================================================================

pub const Topics = struct {
    pub const POSITION_OPENED: [32]u8 = computeTopicHash("PositionOpened(bytes32,uint256,bool)");
    pub const POSITION_CLOSED: [32]u8 = computeTopicHash("PositionClosed(bytes32,uint256)");
    pub const PERP_CREATED: [32]u8 = computeTopicHash("PerpCreated(bytes32)");
    pub const INDEX_UPDATED: [32]u8 = computeTopicHash("IndexUpdated(uint256)");

    /// Compute the keccak256 hash of an event signature at compile time.
    pub fn computeTopicHash(comptime sig: []const u8) [32]u8 {
        @setEvalBranchQuota(10000);
        var out: [32]u8 = undefined;
        std.crypto.hash.sha3.Keccak256.hash(sig, &out, .{});
        return out;
    }
};

// =============================================================================
// Subscription registry
// =============================================================================

/// A subscription entry in the registry.
pub const Subscription = struct {
    id: u64,
    event_type: EventType,
    /// Optional filter: only match events for this perp ID.
    perp_id_filter: ?[32]u8 = null,
    /// Whether this subscription is active.
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
    pub fn subscribe(self: *EventRegistry, event_type: EventType, perp_id_filter: ?[32]u8) !u64 {
        const id = self.next_id;
        self.next_id += 1;

        try self.subscriptions.put(id, .{
            .id = id,
            .event_type = event_type,
            .perp_id_filter = perp_id_filter,
            .active = true,
        });

        return id;
    }

    /// Unsubscribe by ID. Returns true if the subscription was active and is now deactivated.
    /// Returns false if the ID does not exist or the subscription was already inactive.
    pub fn unsubscribe(self: *EventRegistry, id: u64) bool {
        if (self.subscriptions.getPtr(id)) |sub| {
            if (sub.active) {
                sub.active = false;
                return true;
            }
        }
        return false;
    }

    /// Get count of active subscriptions matching an event type and optional perp_id.
    pub fn matchingCount(self: *const EventRegistry, event_type: EventType, perp_id: ?[32]u8) usize {
        var count: usize = 0;
        var iter = self.subscriptions.valueIterator();
        while (iter.next()) |sub| {
            if (!sub.active) continue;
            if (sub.event_type != event_type) continue;

            // If the subscription has a perp_id filter, check it matches.
            if (sub.perp_id_filter) |filter| {
                if (perp_id) |pid| {
                    if (std.mem.eql(u8, &filter, &pid)) {
                        count += 1;
                    }
                }
                // If no perp_id was provided but subscription has a filter, skip.
            } else {
                // No filter on subscription -- matches any perp_id.
                count += 1;
            }
        }
        return count;
    }

    /// Get total active subscription count.
    pub fn activeCount(self: *const EventRegistry) usize {
        var count: usize = 0;
        var iter = self.subscriptions.valueIterator();
        while (iter.next()) |sub| {
            if (sub.active) {
                count += 1;
            }
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
    if (std.mem.eql(u8, &topic0, &Topics.POSITION_OPENED)) return .position_opened;
    if (std.mem.eql(u8, &topic0, &Topics.POSITION_CLOSED)) return .position_closed;
    if (std.mem.eql(u8, &topic0, &Topics.PERP_CREATED)) return .perp_created;
    if (std.mem.eql(u8, &topic0, &Topics.INDEX_UPDATED)) return .index_updated;
    return null;
}

// =============================================================================
// Internal tests (run with `zig test src/events.zig`)
// =============================================================================

test "Topics are 32-byte non-zero hashes" {
    // Each topic should be a 32-byte hash and not all zeros.
    const zero = [_]u8{0} ** 32;
    try std.testing.expect(!std.mem.eql(u8, &Topics.POSITION_OPENED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.POSITION_CLOSED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.PERP_CREATED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.INDEX_UPDATED, &zero));
}

test "All topic hashes are distinct" {
    const topics = [_][32]u8{
        Topics.POSITION_OPENED,
        Topics.POSITION_CLOSED,
        Topics.PERP_CREATED,
        Topics.INDEX_UPDATED,
    };
    // Check all pairs are distinct.
    for (0..topics.len) |i| {
        for ((i + 1)..topics.len) |j| {
            try std.testing.expect(!std.mem.eql(u8, &topics[i], &topics[j]));
        }
    }
}

test "identifyEvent returns correct event type for each topic" {
    try std.testing.expectEqual(EventType.position_opened, identifyEvent(Topics.POSITION_OPENED).?);
    try std.testing.expectEqual(EventType.position_closed, identifyEvent(Topics.POSITION_CLOSED).?);
    try std.testing.expectEqual(EventType.perp_created, identifyEvent(Topics.PERP_CREATED).?);
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

    const id1 = try registry.subscribe(.position_opened, null);
    const id2 = try registry.subscribe(.position_closed, null);

    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(@as(usize, 2), registry.activeCount());

    // Unsubscribe the first one.
    try std.testing.expect(registry.unsubscribe(id1));
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());

    // Unsubscribing again returns false.
    try std.testing.expect(!registry.unsubscribe(id1));

    // Unsubscribe non-existent ID.
    try std.testing.expect(!registry.unsubscribe(9999));
}

test "EventRegistry matchingCount without filter" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    _ = try registry.subscribe(.position_opened, null);
    _ = try registry.subscribe(.position_opened, null);
    _ = try registry.subscribe(.position_closed, null);

    try std.testing.expectEqual(@as(usize, 2), registry.matchingCount(.position_opened, null));
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_closed, null));
    try std.testing.expectEqual(@as(usize, 0), registry.matchingCount(.index_updated, null));
}

test "EventRegistry matchingCount with perp_id filter" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const perp_a = [_]u8{0xAA} ** 32;
    const perp_b = [_]u8{0xBB} ** 32;

    // One subscription for perp_a, one with no filter.
    _ = try registry.subscribe(.position_opened, perp_a);
    _ = try registry.subscribe(.position_opened, null);

    // Querying with perp_a should match both (filtered + unfiltered).
    try std.testing.expectEqual(@as(usize, 2), registry.matchingCount(.position_opened, perp_a));

    // Querying with perp_b should match only the unfiltered one.
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, perp_b));

    // Querying with null perp_id should match only the unfiltered one
    // (the filtered subscription requires a perp_id to match).
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, null));
}

test "EventRegistry activeCount tracks correctly after subscribe and unsubscribe" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.activeCount());

    const id1 = try registry.subscribe(.position_opened, null);
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());

    const id2 = try registry.subscribe(.index_updated, null);
    try std.testing.expectEqual(@as(usize, 2), registry.activeCount());

    const id3 = try registry.subscribe(.perp_created, null);
    try std.testing.expectEqual(@as(usize, 3), registry.activeCount());

    _ = registry.unsubscribe(id2);
    try std.testing.expectEqual(@as(usize, 2), registry.activeCount());

    _ = registry.unsubscribe(id1);
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());

    _ = registry.unsubscribe(id3);
    try std.testing.expectEqual(@as(usize, 0), registry.activeCount());
}

test "computeTopicHash is deterministic" {
    const hash1 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    const hash2 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}
