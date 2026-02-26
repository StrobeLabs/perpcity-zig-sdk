const std = @import("std");

/// A single RPC endpoint with health and latency tracking.
pub const RpcEndpoint = struct {
    url: []const u8,
    is_healthy: bool = true,
    avg_latency_ns: u64 = 0,
    total_requests: u64 = 0,
    consecutive_errors: u32 = 0,
    last_error_time_ms: i64 = 0,

    /// Cooldown period (ms) before an unhealthy endpoint is retried.
    pub const COOLDOWN_MS: i64 = 30_000;

    /// Record a successful request with its latency.
    /// Uses an exponential moving average with alpha = 0.2.
    pub fn recordSuccess(self: *RpcEndpoint, latency_ns: u64) void {
        if (self.total_requests == 0) {
            self.avg_latency_ns = latency_ns;
        } else {
            self.avg_latency_ns = (self.avg_latency_ns * 4 + latency_ns) / 5;
        }
        self.total_requests += 1;
        self.consecutive_errors = 0;
        self.is_healthy = true;
    }

    /// Record a failed request with an explicit timestamp (milliseconds).
    /// After 3 consecutive errors the endpoint is marked unhealthy.
    /// The caller is responsible for supplying the current time, which
    /// keeps this module free of OS-level clock dependencies and makes
    /// it fully deterministic in tests.
    pub fn recordError(self: *RpcEndpoint, now_ms: i64) void {
        self.consecutive_errors += 1;
        self.last_error_time_ms = now_ms;
        if (self.consecutive_errors >= 3) {
            self.is_healthy = false;
        }
    }

    /// Check if the endpoint should be retried at the given time.
    /// Healthy endpoints always return true.  Unhealthy endpoints
    /// return true only after the cooldown period has elapsed.
    pub fn shouldRetry(self: *const RpcEndpoint, now_ms: i64) bool {
        if (self.is_healthy) return true;
        return (now_ms - self.last_error_time_ms) >= COOLDOWN_MS;
    }
};

/// Configuration for creating a `MultiRpcProvider`.
pub const MultiRpcConfig = struct {
    endpoints: []const []const u8,
};

/// A multi-endpoint RPC provider that selects the best endpoint
/// based on health status and latency.
pub const MultiRpcProvider = struct {
    endpoints: []RpcEndpoint,
    primary_index: usize = 0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, urls: []const []const u8) !MultiRpcProvider {
        if (urls.len == 0) return error.NoEndpoints;

        const endpoints = try allocator.alloc(RpcEndpoint, urls.len);
        for (urls, 0..) |url, i| {
            endpoints[i] = .{ .url = url };
        }
        return .{
            .endpoints = endpoints,
            .primary_index = 0,
            .allocator = allocator,
        };
    }

    /// Select the best endpoint at the given time: healthy (or past
    /// cooldown) with the lowest average latency.  Returns `null`
    /// when every endpoint is unhealthy and still within its cooldown
    /// window.
    pub fn selectEndpoint(self: *MultiRpcProvider, now_ms: i64) ?*RpcEndpoint {
        var best: ?*RpcEndpoint = null;
        var best_latency: u64 = std.math.maxInt(u64);

        for (self.endpoints) |*ep| {
            if (!ep.shouldRetry(now_ms)) continue;
            if (best == null or ep.avg_latency_ns < best_latency) {
                best = ep;
                best_latency = ep.avg_latency_ns;
            }
        }
        return best;
    }

    /// Return the number of endpoints currently considered healthy.
    pub fn healthyCount(self: *const MultiRpcProvider) usize {
        var count: usize = 0;
        for (self.endpoints) |ep| {
            if (ep.is_healthy) count += 1;
        }
        return count;
    }

    pub fn deinit(self: *MultiRpcProvider) void {
        self.allocator.free(self.endpoints);
    }
};
