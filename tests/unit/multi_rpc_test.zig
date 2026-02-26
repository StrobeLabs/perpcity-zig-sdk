const std = @import("std");
const sdk = @import("perpcity_sdk");
const multi_rpc = sdk.multi_rpc;
const RpcEndpoint = multi_rpc.RpcEndpoint;
const MultiRpcProvider = multi_rpc.MultiRpcProvider;

// =============================================================================
// RpcEndpoint.recordSuccess
// =============================================================================

test "recordSuccess - first request sets avg_latency_ns directly" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordSuccess(1_000_000);

    try std.testing.expectEqual(@as(u64, 1_000_000), ep.avg_latency_ns);
    try std.testing.expectEqual(@as(u64, 1), ep.total_requests);
    try std.testing.expectEqual(@as(u32, 0), ep.consecutive_errors);
    try std.testing.expectEqual(true, ep.is_healthy);
}

test "recordSuccess - second request uses exponential moving average" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordSuccess(1_000_000);
    ep.recordSuccess(2_000_000);

    // EMA: (1_000_000 * 4 + 2_000_000) / 5 = 1_200_000
    try std.testing.expectEqual(@as(u64, 1_200_000), ep.avg_latency_ns);
    try std.testing.expectEqual(@as(u64, 2), ep.total_requests);
}

test "recordSuccess - multiple calls converge toward new value" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordSuccess(1_000_000);

    // Push many samples of 5_000_000, latency should converge up
    for (0..20) |_| {
        ep.recordSuccess(5_000_000);
    }
    // After many iterations the EMA should be close to 5_000_000
    try std.testing.expect(ep.avg_latency_ns > 4_500_000);
    try std.testing.expect(ep.avg_latency_ns <= 5_000_000);
}

test "recordSuccess - resets consecutive_errors and restores health" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.consecutive_errors = 5;
    ep.is_healthy = false;

    ep.recordSuccess(500_000);

    try std.testing.expectEqual(@as(u32, 0), ep.consecutive_errors);
    try std.testing.expectEqual(true, ep.is_healthy);
}

test "recordSuccess - zero latency is valid" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordSuccess(0);

    try std.testing.expectEqual(@as(u64, 0), ep.avg_latency_ns);
    try std.testing.expectEqual(@as(u64, 1), ep.total_requests);
}

// =============================================================================
// RpcEndpoint.recordError
// =============================================================================

test "recordError - first error keeps endpoint healthy" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);

    try std.testing.expectEqual(@as(u32, 1), ep.consecutive_errors);
    try std.testing.expectEqual(true, ep.is_healthy);
}

test "recordError - two errors keeps endpoint healthy" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);
    ep.recordError(1001);

    try std.testing.expectEqual(@as(u32, 2), ep.consecutive_errors);
    try std.testing.expectEqual(true, ep.is_healthy);
}

test "recordError - three consecutive errors marks endpoint unhealthy" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);
    ep.recordError(1001);
    ep.recordError(1002);

    try std.testing.expectEqual(@as(u32, 3), ep.consecutive_errors);
    try std.testing.expectEqual(false, ep.is_healthy);
}

test "recordError - updates last_error_time_ms" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(42_000);

    try std.testing.expectEqual(@as(i64, 42_000), ep.last_error_time_ms);
}

test "recordError - success resets then errors accumulate fresh" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);
    ep.recordError(1001);
    ep.recordSuccess(100);
    // After success consecutive_errors is 0
    try std.testing.expectEqual(@as(u32, 0), ep.consecutive_errors);
    try std.testing.expectEqual(true, ep.is_healthy);

    // Two more errors should NOT trigger unhealthy
    ep.recordError(2000);
    ep.recordError(2001);
    try std.testing.expectEqual(@as(u32, 2), ep.consecutive_errors);
    try std.testing.expectEqual(true, ep.is_healthy);
}

// =============================================================================
// RpcEndpoint.shouldRetry
// =============================================================================

test "shouldRetry - healthy endpoint always returns true" {
    const ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    try std.testing.expectEqual(true, ep.shouldRetry(0));
    try std.testing.expectEqual(true, ep.shouldRetry(999_999_999));
}

test "shouldRetry - unhealthy endpoint within cooldown returns false" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);
    ep.recordError(1000);
    ep.recordError(1000);

    try std.testing.expectEqual(false, ep.is_healthy);
    // 1ms before cooldown expires
    try std.testing.expectEqual(false, ep.shouldRetry(1000 + 29_999));
}

test "shouldRetry - unhealthy endpoint at cooldown boundary returns true" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);
    ep.recordError(1000);
    ep.recordError(1000);

    try std.testing.expectEqual(false, ep.is_healthy);
    // Exactly at cooldown boundary
    try std.testing.expectEqual(true, ep.shouldRetry(1000 + 30_000));
}

test "shouldRetry - unhealthy endpoint well past cooldown returns true" {
    var ep = RpcEndpoint{ .url = "http://rpc1.example.com" };
    ep.recordError(1000);
    ep.recordError(1000);
    ep.recordError(1000);

    try std.testing.expectEqual(true, ep.shouldRetry(1000 + 60_000));
}

// =============================================================================
// MultiRpcProvider.init
// =============================================================================

test "MultiRpcProvider.init - creates endpoints from URLs" {
    const urls = [_][]const u8{ "http://rpc1.example.com", "http://rpc2.example.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    try std.testing.expectEqual(@as(usize, 2), provider.endpoints.len);
    try std.testing.expectEqualStrings("http://rpc1.example.com", provider.endpoints[0].url);
    try std.testing.expectEqualStrings("http://rpc2.example.com", provider.endpoints[1].url);
}

test "MultiRpcProvider.init - all endpoints start healthy" {
    const urls = [_][]const u8{ "http://a.com", "http://b.com", "http://c.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    for (provider.endpoints) |ep| {
        try std.testing.expectEqual(true, ep.is_healthy);
        try std.testing.expectEqual(@as(u64, 0), ep.total_requests);
    }
}

test "MultiRpcProvider.init - empty list returns NoEndpoints" {
    const urls = [_][]const u8{};
    try std.testing.expectError(error.NoEndpoints, MultiRpcProvider.init(std.testing.allocator, &urls));
}

// =============================================================================
// MultiRpcProvider.selectEndpoint
// =============================================================================

test "selectEndpoint - returns the lowest latency healthy endpoint" {
    const urls = [_][]const u8{ "http://slow.com", "http://fast.com", "http://medium.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    provider.endpoints[0].recordSuccess(5_000_000); // slow
    provider.endpoints[1].recordSuccess(1_000_000); // fast
    provider.endpoints[2].recordSuccess(3_000_000); // medium

    const now: i64 = 100_000;
    const best = provider.selectEndpoint(now);
    try std.testing.expect(best != null);
    try std.testing.expectEqualStrings("http://fast.com", best.?.url);
}

test "selectEndpoint - skips unhealthy endpoints within cooldown" {
    const urls = [_][]const u8{ "http://fast-but-down.com", "http://slow-but-up.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    // Make endpoint 0 the fastest but then kill it
    provider.endpoints[0].recordSuccess(100);
    const err_time: i64 = 50_000;
    provider.endpoints[0].recordError(err_time);
    provider.endpoints[0].recordError(err_time);
    provider.endpoints[0].recordError(err_time); // now unhealthy

    provider.endpoints[1].recordSuccess(5_000_000);

    // Query within cooldown of endpoint 0
    const now: i64 = err_time + 10_000;
    const best = provider.selectEndpoint(now);
    try std.testing.expect(best != null);
    try std.testing.expectEqualStrings("http://slow-but-up.com", best.?.url);
}

test "selectEndpoint - returns null when all endpoints are unhealthy within cooldown" {
    const urls = [_][]const u8{ "http://a.com", "http://b.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    const err_time: i64 = 10_000;
    for (provider.endpoints) |*ep| {
        ep.recordError(err_time);
        ep.recordError(err_time);
        ep.recordError(err_time);
    }

    // Query within cooldown
    const now: i64 = err_time + 1_000;
    const result = provider.selectEndpoint(now);
    try std.testing.expectEqual(@as(?*RpcEndpoint, null), result);
}

test "selectEndpoint - returns unhealthy endpoint after cooldown expires" {
    const urls = [_][]const u8{"http://only.com"};
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    const err_time: i64 = 10_000;
    provider.endpoints[0].recordError(err_time);
    provider.endpoints[0].recordError(err_time);
    provider.endpoints[0].recordError(err_time);

    // Within cooldown -> null
    try std.testing.expectEqual(@as(?*RpcEndpoint, null), provider.selectEndpoint(err_time + 1_000));

    // Past cooldown -> returned
    const best = provider.selectEndpoint(err_time + 30_000);
    try std.testing.expect(best != null);
    try std.testing.expectEqualStrings("http://only.com", best.?.url);
}

test "selectEndpoint - prefers first endpoint when all latencies are zero" {
    const urls = [_][]const u8{ "http://a.com", "http://b.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    const best = provider.selectEndpoint(0);
    try std.testing.expect(best != null);
    try std.testing.expectEqualStrings("http://a.com", best.?.url);
}

// =============================================================================
// MultiRpcProvider.healthyCount
// =============================================================================

test "healthyCount - all healthy initially" {
    const urls = [_][]const u8{ "http://a.com", "http://b.com", "http://c.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    try std.testing.expectEqual(@as(usize, 3), provider.healthyCount());
}

test "healthyCount - decreases when endpoints become unhealthy" {
    const urls = [_][]const u8{ "http://a.com", "http://b.com", "http://c.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    // Kill first endpoint
    provider.endpoints[0].recordError(1000);
    provider.endpoints[0].recordError(1000);
    provider.endpoints[0].recordError(1000);
    try std.testing.expectEqual(@as(usize, 2), provider.healthyCount());

    // Kill second endpoint
    provider.endpoints[1].recordError(1000);
    provider.endpoints[1].recordError(1000);
    provider.endpoints[1].recordError(1000);
    try std.testing.expectEqual(@as(usize, 1), provider.healthyCount());
}

test "healthyCount - increases when endpoint recovers via success" {
    const urls = [_][]const u8{ "http://a.com", "http://b.com" };
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    // Kill both
    for (provider.endpoints) |*ep| {
        ep.recordError(1000);
        ep.recordError(1000);
        ep.recordError(1000);
    }
    try std.testing.expectEqual(@as(usize, 0), provider.healthyCount());

    // Recovery via success
    provider.endpoints[0].recordSuccess(100);
    try std.testing.expectEqual(@as(usize, 1), provider.healthyCount());
}

test "healthyCount - single endpoint" {
    const urls = [_][]const u8{"http://only.com"};
    var provider = try MultiRpcProvider.init(std.testing.allocator, &urls);
    defer provider.deinit();

    try std.testing.expectEqual(@as(usize, 1), provider.healthyCount());
}
