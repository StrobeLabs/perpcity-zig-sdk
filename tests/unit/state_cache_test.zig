const std = @import("std");
const sdk = @import("perpcity_sdk");
const StateCache = sdk.state_cache.StateCache;
const CachedValue = sdk.state_cache.CachedValue;
const CachedFees = sdk.state_cache.CachedFees;
const CachedBounds = sdk.state_cache.CachedBounds;

// =============================================================================
// CachedValue isValid
// =============================================================================

test "CachedValue - isValid returns true when not expired" {
    const cv = CachedValue(f64){
        .value = 42.0,
        .expires_at = 1000,
    };
    try std.testing.expect(cv.isValid(999));
    try std.testing.expect(cv.isValid(500));
    try std.testing.expect(cv.isValid(0));
}

test "CachedValue - isValid returns false when expired" {
    const cv = CachedValue(f64){
        .value = 42.0,
        .expires_at = 1000,
    };
    try std.testing.expect(!cv.isValid(1000));
    try std.testing.expect(!cv.isValid(1001));
    try std.testing.expect(!cv.isValid(9999));
}

test "CachedValue - isValid works with i256 type" {
    const cv = CachedValue(i256){
        .value = -12345,
        .expires_at = 50,
    };
    try std.testing.expect(cv.isValid(49));
    try std.testing.expect(!cv.isValid(50));
}

// =============================================================================
// Mark price get/put
// =============================================================================

test "getMarkPrice - returns null on cache miss" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_id = [_]u8{0xAA} ** 32;
    const result = cache.getMarkPrice(perp_id, 100);
    try std.testing.expect(result == null);
}

test "putMarkPrice/getMarkPrice - stores and retrieves price" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_id = [_]u8{0xBB} ** 32;
    try cache.putMarkPrice(perp_id, 1850.50, 100);

    const result = cache.getMarkPrice(perp_id, 101);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f64, 1850.50), result.?);
}

test "getMarkPrice - returns null after expiry" {
    var cache = StateCache.init(std.testing.allocator, .{ .fast_ttl = 2 });
    defer cache.deinit();

    const perp_id = [_]u8{0xCC} ** 32;
    try cache.putMarkPrice(perp_id, 2000.0, 100);

    // Still valid at 101 (expires_at = 102)
    try std.testing.expect(cache.getMarkPrice(perp_id, 101) != null);

    // Expired at 102 (now >= expires_at)
    try std.testing.expect(cache.getMarkPrice(perp_id, 102) == null);

    // Expired well after
    try std.testing.expect(cache.getMarkPrice(perp_id, 200) == null);
}

test "putMarkPrice - overwrites previous value for same perp_id" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_id = [_]u8{0xDD} ** 32;
    try cache.putMarkPrice(perp_id, 1000.0, 100);
    try cache.putMarkPrice(perp_id, 2000.0, 100);

    const result = cache.getMarkPrice(perp_id, 101);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f64, 2000.0), result.?);
}

// =============================================================================
// Funding rate get/put
// =============================================================================

test "getFundingRate - returns null on cache miss" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_id = [_]u8{0x01} ** 32;
    try std.testing.expect(cache.getFundingRate(perp_id, 100) == null);
}

test "putFundingRate/getFundingRate - stores and retrieves rate" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_id = [_]u8{0x02} ** 32;
    const rate: i256 = -999_999;
    try cache.putFundingRate(perp_id, rate, 100);

    const result = cache.getFundingRate(perp_id, 101);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i256, -999_999), result.?);
}

test "getFundingRate - returns null after expiry" {
    var cache = StateCache.init(std.testing.allocator, .{ .fast_ttl = 2 });
    defer cache.deinit();

    const perp_id = [_]u8{0x03} ** 32;
    try cache.putFundingRate(perp_id, 12345, 100);

    try std.testing.expect(cache.getFundingRate(perp_id, 101) != null);
    try std.testing.expect(cache.getFundingRate(perp_id, 102) == null);
}

// =============================================================================
// USDC balance get/put
// =============================================================================

test "getUsdcBalance - returns null when not set" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    try std.testing.expect(cache.getUsdcBalance(100) == null);
}

test "putUsdcBalance/getUsdcBalance - stores and retrieves balance" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    cache.putUsdcBalance(5000.25, 100);

    const result = cache.getUsdcBalance(101);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f64, 5000.25), result.?);
}

test "getUsdcBalance - returns null after expiry" {
    var cache = StateCache.init(std.testing.allocator, .{ .fast_ttl = 2 });
    defer cache.deinit();

    cache.putUsdcBalance(1000.0, 100);

    try std.testing.expect(cache.getUsdcBalance(101) != null);
    try std.testing.expect(cache.getUsdcBalance(102) == null);
}

// =============================================================================
// Fees get/put
// =============================================================================

test "getFees - returns null on cache miss" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const addr = [_]u8{0xAA} ** 20;
    try std.testing.expect(cache.getFees(addr, 100) == null);
}

test "putFees/getFees - stores and retrieves fees" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const addr = [_]u8{0xBB} ** 20;
    const fees = CachedFees{
        .creator_fee = 0.001,
        .insurance_fee = 0.002,
        .lp_fee = 0.003,
        .liquidation_fee = 0.01,
    };
    try cache.putFees(addr, fees, 100);

    const result = cache.getFees(addr, 150);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f64, 0.001), result.?.creator_fee);
    try std.testing.expectEqual(@as(f64, 0.002), result.?.insurance_fee);
    try std.testing.expectEqual(@as(f64, 0.003), result.?.lp_fee);
    try std.testing.expectEqual(@as(f64, 0.01), result.?.liquidation_fee);
}

test "getFees - returns null after slow TTL expiry" {
    var cache = StateCache.init(std.testing.allocator, .{ .slow_ttl = 60 });
    defer cache.deinit();

    const addr = [_]u8{0xCC} ** 20;
    const fees = CachedFees{
        .creator_fee = 0.001,
        .insurance_fee = 0.002,
        .lp_fee = 0.003,
        .liquidation_fee = 0.01,
    };
    try cache.putFees(addr, fees, 100);

    // Valid at 159 (expires_at = 160)
    try std.testing.expect(cache.getFees(addr, 159) != null);
    // Expired at 160
    try std.testing.expect(cache.getFees(addr, 160) == null);
}

// =============================================================================
// Bounds get/put
// =============================================================================

test "getBounds - returns null on cache miss" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const addr = [_]u8{0x11} ** 20;
    try std.testing.expect(cache.getBounds(addr, 100) == null);
}

test "putBounds/getBounds - stores and retrieves bounds" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const addr = [_]u8{0x22} ** 20;
    const b = CachedBounds{
        .min_margin = 0.1,
        .min_taker_leverage = 1.0,
        .max_taker_leverage = 50.0,
        .liquidation_taker_ratio = 0.05,
    };
    try cache.putBounds(addr, b, 100);

    const result = cache.getBounds(addr, 150);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(f64, 50.0), result.?.max_taker_leverage);
}

// =============================================================================
// invalidateFastLayer
// =============================================================================

test "invalidateFastLayer - clears mark prices and funding rates" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_id = [_]u8{0xFF} ** 32;
    try cache.putMarkPrice(perp_id, 1850.0, 100);
    try cache.putFundingRate(perp_id, 42, 100);
    cache.putUsdcBalance(1000.0, 100);

    // Verify data is present before invalidation
    try std.testing.expect(cache.getMarkPrice(perp_id, 101) != null);
    try std.testing.expect(cache.getFundingRate(perp_id, 101) != null);
    try std.testing.expect(cache.getUsdcBalance(101) != null);

    cache.invalidateFastLayer();

    // Fast layer data should be gone
    try std.testing.expect(cache.getMarkPrice(perp_id, 101) == null);
    try std.testing.expect(cache.getFundingRate(perp_id, 101) == null);
    try std.testing.expect(cache.getUsdcBalance(101) == null);
}

test "invalidateFastLayer - preserves fees and bounds" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const fees_addr = [_]u8{0xAA} ** 20;
    const bounds_addr = [_]u8{0xBB} ** 20;
    const perp_id = [_]u8{0xCC} ** 32;

    const fees = CachedFees{
        .creator_fee = 0.001,
        .insurance_fee = 0.002,
        .lp_fee = 0.003,
        .liquidation_fee = 0.01,
    };
    const bounds = CachedBounds{
        .min_margin = 0.1,
        .min_taker_leverage = 1.0,
        .max_taker_leverage = 50.0,
        .liquidation_taker_ratio = 0.05,
    };

    try cache.putFees(fees_addr, fees, 100);
    try cache.putBounds(bounds_addr, bounds, 100);
    try cache.putMarkPrice(perp_id, 1850.0, 100);

    cache.invalidateFastLayer();

    // Slow layer data should still be present
    try std.testing.expect(cache.getFees(fees_addr, 110) != null);
    try std.testing.expect(cache.getBounds(bounds_addr, 110) != null);

    // Fast layer data should be gone
    try std.testing.expect(cache.getMarkPrice(perp_id, 101) == null);
}

// =============================================================================
// Custom TTL configuration
// =============================================================================

test "StateCache - respects custom TTL values" {
    var cache = StateCache.init(std.testing.allocator, .{
        .slow_ttl = 10,
        .fast_ttl = 1,
    });
    defer cache.deinit();

    const perp_id = [_]u8{0x01} ** 32;
    const fees_addr = [_]u8{0x02} ** 20;

    try cache.putMarkPrice(perp_id, 100.0, 1000);
    try cache.putFees(fees_addr, .{
        .creator_fee = 0.001,
        .insurance_fee = 0.002,
        .lp_fee = 0.003,
        .liquidation_fee = 0.01,
    }, 1000);

    // Mark price expires after 1s (fast_ttl = 1)
    try std.testing.expect(cache.getMarkPrice(perp_id, 1000) != null);
    try std.testing.expect(cache.getMarkPrice(perp_id, 1001) == null);

    // Fees expire after 10s (slow_ttl = 10)
    try std.testing.expect(cache.getFees(fees_addr, 1009) != null);
    try std.testing.expect(cache.getFees(fees_addr, 1010) == null);
}

// =============================================================================
// Multiple entries in the same map
// =============================================================================

test "StateCache - supports multiple perp IDs simultaneously" {
    var cache = StateCache.init(std.testing.allocator, .{});
    defer cache.deinit();

    const perp_a = [_]u8{0x01} ** 32;
    const perp_b = [_]u8{0x02} ** 32;
    const perp_c = [_]u8{0x03} ** 32;

    try cache.putMarkPrice(perp_a, 100.0, 1000);
    try cache.putMarkPrice(perp_b, 200.0, 1000);
    try cache.putMarkPrice(perp_c, 300.0, 1000);

    try std.testing.expectEqual(@as(f64, 100.0), cache.getMarkPrice(perp_a, 1001).?);
    try std.testing.expectEqual(@as(f64, 200.0), cache.getMarkPrice(perp_b, 1001).?);
    try std.testing.expectEqual(@as(f64, 300.0), cache.getMarkPrice(perp_c, 1001).?);
}
