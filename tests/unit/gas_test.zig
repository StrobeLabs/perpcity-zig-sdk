const std = @import("std");
const sdk = @import("perpcity_sdk");
const GasLimits = sdk.gas.GasLimits;
const GasCache = sdk.gas.GasCache;
const GasFees = sdk.gas.GasFees;
const Urgency = sdk.gas.Urgency;

// =============================================================================
// GasLimits constants
// =============================================================================

test "GasLimits - all constants have expected values" {
    try std.testing.expectEqual(@as(u64, 60_000), GasLimits.APPROVE);
    try std.testing.expectEqual(@as(u64, 500_000), GasLimits.OPEN_TAKER_POS);
    try std.testing.expectEqual(@as(u64, 600_000), GasLimits.OPEN_MAKER_POS);
    try std.testing.expectEqual(@as(u64, 400_000), GasLimits.CLOSE_POSITION);
    try std.testing.expectEqual(@as(u64, 350_000), GasLimits.ADJUST_NOTIONAL);
    try std.testing.expectEqual(@as(u64, 250_000), GasLimits.ADJUST_MARGIN);
}

test "GasLimits - ordering is reasonable" {
    // Maker positions cost more gas than taker
    try std.testing.expect(GasLimits.OPEN_MAKER_POS > GasLimits.OPEN_TAKER_POS);
    // Opening positions costs more than closing
    try std.testing.expect(GasLimits.OPEN_TAKER_POS > GasLimits.CLOSE_POSITION);
    // Approve is the cheapest operation
    try std.testing.expect(GasLimits.APPROVE < GasLimits.ADJUST_MARGIN);
}

// =============================================================================
// GasCache init
// =============================================================================

test "GasCache init - default config" {
    const cache = GasCache.init(.{});

    try std.testing.expectEqual(@as(?GasFees, null), cache.current);
    try std.testing.expectEqual(@as(i64, 2000), cache.ttl_ms);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), cache.default_priority_fee);
}

test "GasCache init - custom config" {
    const cache = GasCache.init(.{
        .ttl_ms = 500,
        .default_priority_fee = 2_000_000_000,
    });

    try std.testing.expectEqual(@as(i64, 500), cache.ttl_ms);
    try std.testing.expectEqual(@as(u64, 2_000_000_000), cache.default_priority_fee);
    try std.testing.expectEqual(@as(?GasFees, null), cache.current);
}

// =============================================================================
// GasCache isValid
// =============================================================================

test "GasCache isValid - returns false when empty" {
    const cache = GasCache.init(.{});
    try std.testing.expect(!cache.isValid(0));
    try std.testing.expect(!cache.isValid(9999));
}

test "GasCache isValid - returns true within TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    // Immediately after update
    try std.testing.expect(cache.isValid(1000));
    // 1ms before expiry
    try std.testing.expect(cache.isValid(2999));
}

test "GasCache isValid - returns false at TTL boundary" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    // Exactly at TTL: (3000 - 1000) = 2000 is NOT < 2000
    try std.testing.expect(!cache.isValid(3000));
}

test "GasCache isValid - returns false well past TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expect(!cache.isValid(10000));
}

// =============================================================================
// GasCache get
// =============================================================================

test "GasCache get - returns null when empty" {
    const cache = GasCache.init(.{});
    try std.testing.expectEqual(@as(?GasFees, null), cache.get(0));
}

test "GasCache get - returns fees within TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    const fees = cache.get(2000).?;
    try std.testing.expectEqual(@as(u64, 100), fees.base_fee);
    try std.testing.expectEqual(@as(i64, 1000), fees.updated_at_ms);
}

test "GasCache get - returns null after TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expectEqual(@as(?GasFees, null), cache.get(3000));
}

// =============================================================================
// GasCache updateFromBlock
// =============================================================================

test "GasCache updateFromBlock - stores correct normal-urgency fees" {
    var cache = GasCache.init(.{ .default_priority_fee = 1_000_000_000 });
    cache.updateFromBlock(50_000_000_000, 5000);

    const fees = cache.current.?;
    try std.testing.expectEqual(@as(u64, 50_000_000_000), fees.base_fee);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), fees.max_priority_fee);
    // normal: 2*base + priority = 101 gwei
    try std.testing.expectEqual(@as(u64, 2 * 50_000_000_000 + 1_000_000_000), fees.max_fee_per_gas);
    try std.testing.expectEqual(@as(i64, 5000), fees.updated_at_ms);
}

test "GasCache updateFromBlock - replaces previous cached value" {
    var cache = GasCache.init(.{});
    cache.updateFromBlock(100, 1000);
    cache.updateFromBlock(200, 2000);

    const fees = cache.current.?;
    try std.testing.expectEqual(@as(u64, 200), fees.base_fee);
    try std.testing.expectEqual(@as(i64, 2000), fees.updated_at_ms);
}

test "GasCache updateFromBlock - refreshed cache becomes valid again" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    // Expired
    try std.testing.expect(!cache.isValid(3000));

    // Refresh
    cache.updateFromBlock(150, 3000);

    // Valid again
    try std.testing.expect(cache.isValid(3000));
    try std.testing.expect(cache.isValid(4999));
    try std.testing.expect(!cache.isValid(5000));
}

// =============================================================================
// feesForUrgency
// =============================================================================

test "feesForUrgency - returns null when cache is empty" {
    const cache = GasCache.init(.{});
    try std.testing.expectEqual(@as(?GasFees, null), cache.feesForUrgency(.normal, 1000));
}

test "feesForUrgency - returns null when cache is stale" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expectEqual(@as(?GasFees, null), cache.feesForUrgency(.normal, 3000));
}

test "feesForUrgency low - maxFee = baseFee + priorityFee" {
    var cache = GasCache.init(.{
        .ttl_ms = 5000,
        .default_priority_fee = 1_000_000_000,
    });
    cache.updateFromBlock(25_000_000_000, 1000);

    const fees = cache.feesForUrgency(.low, 2000).?;

    try std.testing.expectEqual(@as(u64, 25_000_000_000), fees.base_fee);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), fees.max_priority_fee);
    try std.testing.expectEqual(@as(u64, 25_000_000_000 + 1_000_000_000), fees.max_fee_per_gas);
}

test "feesForUrgency normal - maxFee = 2*baseFee + priorityFee" {
    var cache = GasCache.init(.{
        .ttl_ms = 5000,
        .default_priority_fee = 1_000_000_000,
    });
    cache.updateFromBlock(25_000_000_000, 1000);

    const fees = cache.feesForUrgency(.normal, 2000).?;

    try std.testing.expectEqual(@as(u64, 25_000_000_000), fees.base_fee);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), fees.max_priority_fee);
    try std.testing.expectEqual(@as(u64, 2 * 25_000_000_000 + 1_000_000_000), fees.max_fee_per_gas);
}

test "feesForUrgency high - maxFee = 3*baseFee + 2*priorityFee" {
    var cache = GasCache.init(.{
        .ttl_ms = 5000,
        .default_priority_fee = 1_000_000_000,
    });
    cache.updateFromBlock(25_000_000_000, 1000);

    const fees = cache.feesForUrgency(.high, 2000).?;

    try std.testing.expectEqual(@as(u64, 25_000_000_000), fees.base_fee);
    try std.testing.expectEqual(@as(u64, 2 * 1_000_000_000), fees.max_priority_fee);
    try std.testing.expectEqual(@as(u64, 3 * 25_000_000_000 + 2 * 1_000_000_000), fees.max_fee_per_gas);
}

test "feesForUrgency critical - maxFee = 4*baseFee + 5*priorityFee" {
    var cache = GasCache.init(.{
        .ttl_ms = 5000,
        .default_priority_fee = 1_000_000_000,
    });
    cache.updateFromBlock(25_000_000_000, 1000);

    const fees = cache.feesForUrgency(.critical, 2000).?;

    try std.testing.expectEqual(@as(u64, 25_000_000_000), fees.base_fee);
    try std.testing.expectEqual(@as(u64, 5 * 1_000_000_000), fees.max_priority_fee);
    try std.testing.expectEqual(@as(u64, 4 * 25_000_000_000 + 5 * 1_000_000_000), fees.max_fee_per_gas);
}

test "feesForUrgency - preserves updated_at_ms from cache" {
    var cache = GasCache.init(.{ .ttl_ms = 5000 });
    cache.updateFromBlock(100, 42_000);

    const fees = cache.feesForUrgency(.normal, 43_000).?;
    try std.testing.expectEqual(@as(i64, 42_000), fees.updated_at_ms);
}

// =============================================================================
// Cache expiry edge cases
// =============================================================================

test "cache expiry - exact boundary behavior" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    // 1ms before expiry: valid
    try std.testing.expect(cache.get(2999) != null);
    // At expiry: stale
    try std.testing.expect(cache.get(3000) == null);
    // After expiry: stale
    try std.testing.expect(cache.get(3001) == null);
}

test "cache expiry - feesForUrgency respects TTL for all levels" {
    var cache = GasCache.init(.{ .ttl_ms = 100 });
    cache.updateFromBlock(100, 1000);

    // Within TTL: all urgency levels should return fees
    try std.testing.expect(cache.feesForUrgency(.low, 1050) != null);
    try std.testing.expect(cache.feesForUrgency(.normal, 1050) != null);
    try std.testing.expect(cache.feesForUrgency(.high, 1050) != null);
    try std.testing.expect(cache.feesForUrgency(.critical, 1050) != null);

    // After TTL: all urgency levels should return null
    try std.testing.expect(cache.feesForUrgency(.low, 1100) == null);
    try std.testing.expect(cache.feesForUrgency(.normal, 1100) == null);
    try std.testing.expect(cache.feesForUrgency(.high, 1100) == null);
    try std.testing.expect(cache.feesForUrgency(.critical, 1100) == null);
}

test "cache expiry - update after expiry revalidates" {
    var cache = GasCache.init(.{ .ttl_ms = 1000 });
    cache.updateFromBlock(100, 0);

    // Expired
    try std.testing.expect(cache.get(1000) == null);

    // Update with new block
    cache.updateFromBlock(200, 1000);

    // Valid again
    const fees = cache.get(1500).?;
    try std.testing.expectEqual(@as(u64, 200), fees.base_fee);
}
