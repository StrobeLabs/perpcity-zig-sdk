const std = @import("std");
const sdk = @import("perpcity_sdk");
const events = sdk.events;
const EventType = events.EventType;
const EventRegistry = events.EventRegistry;
const Topics = events.Topics;

// =============================================================================
// Topic hash computation
// =============================================================================

test "topic hashes are 32-byte non-zero values" {
    const zero = [_]u8{0} ** 32;
    try std.testing.expect(!std.mem.eql(u8, &Topics.POSITION_OPENED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.POSITION_CLOSED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.PERP_CREATED, &zero));
    try std.testing.expect(!std.mem.eql(u8, &Topics.INDEX_UPDATED, &zero));
}

test "all topic hashes are distinct from each other" {
    const topic_list = [_][32]u8{
        Topics.POSITION_OPENED,
        Topics.POSITION_CLOSED,
        Topics.PERP_CREATED,
        Topics.INDEX_UPDATED,
    };
    for (0..topic_list.len) |i| {
        for ((i + 1)..topic_list.len) |j| {
            try std.testing.expect(!std.mem.eql(u8, &topic_list[i], &topic_list[j]));
        }
    }
}

test "topic hash matches runtime keccak256 of event signature" {
    // Verify comptime hashes match runtime computation.
    var runtime_hash: [32]u8 = undefined;
    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
    hasher.update("PositionOpened(bytes32,uint256,bool)");
    hasher.final(&runtime_hash);
    try std.testing.expectEqualSlices(u8, &runtime_hash, &Topics.POSITION_OPENED);
}

test "computeTopicHash is deterministic" {
    const hash1 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    const hash2 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    try std.testing.expectEqualSlices(u8, &hash1, &hash2);
}

test "computeTopicHash produces different results for different signatures" {
    const hash1 = Topics.computeTopicHash("Transfer(address,address,uint256)");
    const hash2 = Topics.computeTopicHash("Approval(address,address,uint256)");
    try std.testing.expect(!std.mem.eql(u8, &hash1, &hash2));
}

// =============================================================================
// identifyEvent
// =============================================================================

test "identifyEvent - returns position_opened for POSITION_OPENED topic" {
    try std.testing.expectEqual(EventType.position_opened, events.identifyEvent(Topics.POSITION_OPENED).?);
}

test "identifyEvent - returns position_closed for POSITION_CLOSED topic" {
    try std.testing.expectEqual(EventType.position_closed, events.identifyEvent(Topics.POSITION_CLOSED).?);
}

test "identifyEvent - returns perp_created for PERP_CREATED topic" {
    try std.testing.expectEqual(EventType.perp_created, events.identifyEvent(Topics.PERP_CREATED).?);
}

test "identifyEvent - returns index_updated for INDEX_UPDATED topic" {
    try std.testing.expectEqual(EventType.index_updated, events.identifyEvent(Topics.INDEX_UPDATED).?);
}

test "identifyEvent - returns null for unknown topic (all 0xff)" {
    const unknown = [_]u8{0xff} ** 32;
    try std.testing.expectEqual(@as(?EventType, null), events.identifyEvent(unknown));
}

test "identifyEvent - returns null for zero topic" {
    const zero = [_]u8{0} ** 32;
    try std.testing.expectEqual(@as(?EventType, null), events.identifyEvent(zero));
}

test "identifyEvent - returns null for random bytes" {
    var random_topic: [32]u8 = undefined;
    // Fill with a non-matching pattern.
    for (&random_topic, 0..) |*byte, i| {
        byte.* = @truncate(i * 7 + 3);
    }
    try std.testing.expectEqual(@as(?EventType, null), events.identifyEvent(random_topic));
}

// =============================================================================
// EventRegistry subscribe / unsubscribe
// =============================================================================

test "subscribe - returns unique IDs" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id1 = try registry.subscribe(.position_opened, null);
    const id2 = try registry.subscribe(.position_closed, null);
    const id3 = try registry.subscribe(.index_updated, null);

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);
    try std.testing.expect(id1 != id3);
}

test "subscribe - IDs are monotonically increasing" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id1 = try registry.subscribe(.position_opened, null);
    const id2 = try registry.subscribe(.position_closed, null);
    const id3 = try registry.subscribe(.index_updated, null);

    try std.testing.expect(id1 < id2);
    try std.testing.expect(id2 < id3);
}

test "unsubscribe - returns true for existing subscription" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id = try registry.subscribe(.position_opened, null);
    try std.testing.expect(registry.unsubscribe(id));
}

test "unsubscribe - returns false for already-unsubscribed ID" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id = try registry.subscribe(.position_opened, null);
    _ = registry.unsubscribe(id);
    // Second call should return false since active is already false.
    try std.testing.expect(!registry.unsubscribe(id));
}

test "unsubscribe - returns false for non-existent ID" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expect(!registry.unsubscribe(9999));
}

// =============================================================================
// EventRegistry matchingCount
// =============================================================================

test "matchingCount - counts matching event type without filter" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    _ = try registry.subscribe(.position_opened, null);
    _ = try registry.subscribe(.position_opened, null);
    _ = try registry.subscribe(.position_closed, null);

    try std.testing.expectEqual(@as(usize, 2), registry.matchingCount(.position_opened, null));
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_closed, null));
    try std.testing.expectEqual(@as(usize, 0), registry.matchingCount(.index_updated, null));
}

test "matchingCount - filtered subscription matches only its perp_id" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const perp_a = [_]u8{0xAA} ** 32;
    const perp_b = [_]u8{0xBB} ** 32;

    _ = try registry.subscribe(.position_opened, perp_a);

    // Matches perp_a.
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, perp_a));
    // Does not match perp_b.
    try std.testing.expectEqual(@as(usize, 0), registry.matchingCount(.position_opened, perp_b));
    // Does not match null.
    try std.testing.expectEqual(@as(usize, 0), registry.matchingCount(.position_opened, null));
}

test "matchingCount - unfiltered subscription matches any perp_id" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    _ = try registry.subscribe(.position_opened, null);

    const perp_a = [_]u8{0xAA} ** 32;
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, perp_a));
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, null));
}

test "matchingCount - mixed filtered and unfiltered subscriptions" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const perp_a = [_]u8{0xAA} ** 32;
    const perp_b = [_]u8{0xBB} ** 32;

    // One filtered for perp_a, one unfiltered.
    _ = try registry.subscribe(.position_opened, perp_a);
    _ = try registry.subscribe(.position_opened, null);

    // perp_a matches both.
    try std.testing.expectEqual(@as(usize, 2), registry.matchingCount(.position_opened, perp_a));
    // perp_b matches only unfiltered.
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, perp_b));
    // null matches only unfiltered.
    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, null));
}

test "matchingCount - excludes inactive subscriptions" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id1 = try registry.subscribe(.position_opened, null);
    _ = try registry.subscribe(.position_opened, null);

    _ = registry.unsubscribe(id1);

    try std.testing.expectEqual(@as(usize, 1), registry.matchingCount(.position_opened, null));
}

// =============================================================================
// EventRegistry activeCount
// =============================================================================

test "activeCount - starts at zero" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    try std.testing.expectEqual(@as(usize, 0), registry.activeCount());
}

test "activeCount - increments on subscribe" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    _ = try registry.subscribe(.position_opened, null);
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());

    _ = try registry.subscribe(.position_closed, null);
    try std.testing.expectEqual(@as(usize, 2), registry.activeCount());

    _ = try registry.subscribe(.index_updated, null);
    try std.testing.expectEqual(@as(usize, 3), registry.activeCount());
}

test "activeCount - decrements on unsubscribe" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id1 = try registry.subscribe(.position_opened, null);
    const id2 = try registry.subscribe(.position_closed, null);
    const id3 = try registry.subscribe(.perp_created, null);

    try std.testing.expectEqual(@as(usize, 3), registry.activeCount());

    _ = registry.unsubscribe(id2);
    try std.testing.expectEqual(@as(usize, 2), registry.activeCount());

    _ = registry.unsubscribe(id1);
    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());

    _ = registry.unsubscribe(id3);
    try std.testing.expectEqual(@as(usize, 0), registry.activeCount());
}

test "activeCount - unsubscribing same ID twice does not double-decrement" {
    var registry = EventRegistry.init(std.testing.allocator);
    defer registry.deinit();

    const id1 = try registry.subscribe(.position_opened, null);
    _ = try registry.subscribe(.position_closed, null);

    _ = registry.unsubscribe(id1);
    _ = registry.unsubscribe(id1); // already inactive

    try std.testing.expectEqual(@as(usize, 1), registry.activeCount());
}
