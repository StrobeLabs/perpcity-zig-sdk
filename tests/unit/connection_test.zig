const std = @import("std");
const sdk = @import("perpcity_sdk");
const connection = sdk.connection;
const ConnectionManager = connection.ConnectionManager;
const ConnectionConfig = connection.ConnectionConfig;

// =============================================================================
// ConnectionManager.init / deinit
// =============================================================================

test "ConnectionManager.init - creates provider with primary URL" {
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.example.com",
    });
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 1), mgr.healthyCount());
}

test "ConnectionManager.init - includes fallback URLs" {
    const fallbacks = [_][]const u8{ "http://fallback1.com", "http://fallback2.com" };
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.com",
        .fallback_urls = &fallbacks,
    });
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 3), mgr.healthyCount());
}

// =============================================================================
// ConnectionManager.getBestUrl
// =============================================================================

test "getBestUrl - returns primary when all are fresh" {
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.com",
    });
    defer mgr.deinit();

    const url = mgr.getBestUrl(0);
    try std.testing.expect(url != null);
    try std.testing.expectEqualStrings("http://primary.com", url.?);
}

test "getBestUrl - returns lowest latency endpoint" {
    const fallbacks = [_][]const u8{"http://fast-fallback.com"};
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://slow-primary.com",
        .fallback_urls = &fallbacks,
    });
    defer mgr.deinit();

    // Primary is slow
    mgr.rpc_provider.endpoints[0].recordSuccess(10_000_000);
    // Fallback is fast
    mgr.rpc_provider.endpoints[1].recordSuccess(1_000_000);

    const url = mgr.getBestUrl(100_000);
    try std.testing.expect(url != null);
    try std.testing.expectEqualStrings("http://fast-fallback.com", url.?);
}

test "getBestUrl - skips unhealthy primary and picks fallback" {
    const fallbacks = [_][]const u8{"http://fallback.com"};
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.com",
        .fallback_urls = &fallbacks,
    });
    defer mgr.deinit();

    // Kill primary
    const err_time: i64 = 50_000;
    mgr.rpc_provider.endpoints[0].recordError(err_time);
    mgr.rpc_provider.endpoints[0].recordError(err_time);
    mgr.rpc_provider.endpoints[0].recordError(err_time);

    mgr.rpc_provider.endpoints[1].recordSuccess(1_000);

    // Query within primary's cooldown
    const url = mgr.getBestUrl(err_time + 5_000);
    try std.testing.expect(url != null);
    try std.testing.expectEqualStrings("http://fallback.com", url.?);
}

// =============================================================================
// ConnectionManager.getWsUrl
// =============================================================================

test "getWsUrl - returns null when not configured" {
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.com",
    });
    defer mgr.deinit();

    try std.testing.expectEqual(@as(?[]const u8, null), mgr.getWsUrl());
}

test "getWsUrl - returns configured URL" {
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.com",
        .ws_url = "ws://primary.com/ws",
    });
    defer mgr.deinit();

    const ws = mgr.getWsUrl();
    try std.testing.expect(ws != null);
    try std.testing.expectEqualStrings("ws://primary.com/ws", ws.?);
}

// =============================================================================
// ConnectionManager.healthyCount
// =============================================================================

test "healthyCount - matches underlying provider" {
    const fallbacks = [_][]const u8{ "http://fb1.com", "http://fb2.com" };
    var mgr = try ConnectionManager.init(std.testing.allocator, .{
        .http_url = "http://primary.com",
        .fallback_urls = &fallbacks,
    });
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 3), mgr.healthyCount());

    // Kill one
    mgr.rpc_provider.endpoints[1].recordError(1000);
    mgr.rpc_provider.endpoints[1].recordError(1000);
    mgr.rpc_provider.endpoints[1].recordError(1000);

    try std.testing.expectEqual(@as(usize, 2), mgr.healthyCount());
}
