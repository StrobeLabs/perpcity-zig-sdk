const std = @import("std");
const multi_rpc = @import("multi_rpc.zig");

pub const RpcEndpoint = multi_rpc.RpcEndpoint;
pub const MultiRpcProvider = multi_rpc.MultiRpcProvider;

/// Configuration for the connection manager.
pub const ConnectionConfig = struct {
    /// Primary HTTP RPC URL.
    http_url: []const u8,
    /// Optional WebSocket URL for subscriptions.
    ws_url: ?[]const u8 = null,
    /// Additional HTTP endpoints for failover.
    fallback_urls: []const []const u8 = &.{},
};

/// Manages a set of RPC connections, choosing the best one based on
/// health and latency, and optionally tracking a WebSocket URL.
pub const ConnectionManager = struct {
    config: ConnectionConfig,
    rpc_provider: multi_rpc.MultiRpcProvider,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: ConnectionConfig) !ConnectionManager {
        // Build a list of all HTTP URLs: primary first, then fallbacks.
        const total = 1 + config.fallback_urls.len;
        const urls_buf = try allocator.alloc([]const u8, total);
        defer allocator.free(urls_buf);

        urls_buf[0] = config.http_url;
        for (config.fallback_urls, 0..) |url, i| {
            urls_buf[1 + i] = url;
        }

        const provider = try multi_rpc.MultiRpcProvider.init(allocator, urls_buf);

        return .{
            .config = config,
            .rpc_provider = provider,
            .allocator = allocator,
        };
    }

    /// Get the URL of the best available RPC endpoint at the given time.
    pub fn getBestUrl(self: *ConnectionManager, now_ms: i64) ?[]const u8 {
        const ep = self.rpc_provider.selectEndpoint(now_ms) orelse return null;
        return ep.url;
    }

    /// Get the WebSocket URL (if configured).
    pub fn getWsUrl(self: *const ConnectionManager) ?[]const u8 {
        return self.config.ws_url;
    }

    /// Return the number of healthy HTTP endpoints.
    pub fn healthyCount(self: *const ConnectionManager) usize {
        return self.rpc_provider.healthyCount();
    }

    pub fn deinit(self: *ConnectionManager) void {
        self.rpc_provider.deinit();
    }
};
