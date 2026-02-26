const std = @import("std");

/// Generic cached-value container with TTL-based expiry.
pub fn CachedValue(comptime T: type) type {
    return struct {
        value: T,
        expires_at: i64, // unix timestamp (seconds)

        const Self = @This();

        pub fn isValid(self: Self, now_ts: i64) bool {
            return now_ts < self.expires_at;
        }
    };
}

/// Fee parameters cached from on-chain fee contracts.
pub const CachedFees = struct {
    creator_fee: f64,
    insurance_fee: f64,
    lp_fee: f64,
    liquidation_fee: f64,
};

/// Margin-ratio parameters cached from on-chain margin contracts.
pub const CachedBounds = struct {
    min_margin: f64,
    min_taker_leverage: f64,
    max_taker_leverage: f64,
    liquidation_taker_ratio: f64,
};

/// TTL configuration for the state cache layers.
pub const StateCacheConfig = struct {
    /// TTL for slowly changing data (fees, bounds) in seconds.
    slow_ttl: i64 = 60,
    /// TTL for fast-changing data (mark prices, funding rates, balances) in seconds.
    fast_ttl: i64 = 2,
};

/// Multi-layer state cache for HFT workloads.
///
/// Layer 2 (slow): fees and bounds -- 60s TTL by default.
/// Layer 3 (fast): mark prices and funding rates -- 2s TTL (1 block) by default.
/// Layer 4 (user): USDC balance -- 2s TTL by default.
pub const StateCache = struct {
    allocator: std.mem.Allocator,

    // Layer 2: Slowly changing (fees, bounds)
    fees: std.AutoHashMap([20]u8, CachedValue(CachedFees)),
    bounds: std.AutoHashMap([20]u8, CachedValue(CachedBounds)),

    // Layer 3: Fast-changing (mark prices, funding)
    mark_prices: std.AutoHashMap([32]u8, CachedValue(f64)),
    funding_rates: std.AutoHashMap([32]u8, CachedValue(i256)),

    // Layer 4: User data
    usdc_balance: ?CachedValue(f64),

    // TTL configuration
    slow_ttl: i64,
    fast_ttl: i64,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: StateCacheConfig) Self {
        return Self{
            .allocator = allocator,
            .fees = std.AutoHashMap([20]u8, CachedValue(CachedFees)).init(allocator),
            .bounds = std.AutoHashMap([20]u8, CachedValue(CachedBounds)).init(allocator),
            .mark_prices = std.AutoHashMap([32]u8, CachedValue(f64)).init(allocator),
            .funding_rates = std.AutoHashMap([32]u8, CachedValue(i256)).init(allocator),
            .usdc_balance = null,
            .slow_ttl = config.slow_ttl,
            .fast_ttl = config.fast_ttl,
        };
    }

    pub fn deinit(self: *Self) void {
        self.fees.deinit();
        self.bounds.deinit();
        self.mark_prices.deinit();
        self.funding_rates.deinit();
    }

    // -----------------------------------------------------------------
    // Layer 2: Fees
    // -----------------------------------------------------------------

    pub fn getFees(self: *Self, fees_addr: [20]u8, now_ts: i64) ?CachedFees {
        const entry = self.fees.get(fees_addr) orelse return null;
        if (!entry.isValid(now_ts)) return null;
        return entry.value;
    }

    pub fn putFees(self: *Self, fees_addr: [20]u8, value: CachedFees, now_ts: i64) !void {
        try self.fees.put(fees_addr, .{
            .value = value,
            .expires_at = now_ts + self.slow_ttl,
        });
    }

    // -----------------------------------------------------------------
    // Layer 2: Bounds
    // -----------------------------------------------------------------

    pub fn getBounds(self: *Self, bounds_addr: [20]u8, now_ts: i64) ?CachedBounds {
        const entry = self.bounds.get(bounds_addr) orelse return null;
        if (!entry.isValid(now_ts)) return null;
        return entry.value;
    }

    pub fn putBounds(self: *Self, bounds_addr: [20]u8, value: CachedBounds, now_ts: i64) !void {
        try self.bounds.put(bounds_addr, .{
            .value = value,
            .expires_at = now_ts + self.slow_ttl,
        });
    }

    // -----------------------------------------------------------------
    // Layer 3: Mark prices
    // -----------------------------------------------------------------

    pub fn getMarkPrice(self: *Self, perp_id: [32]u8, now_ts: i64) ?f64 {
        const entry = self.mark_prices.get(perp_id) orelse return null;
        if (!entry.isValid(now_ts)) return null;
        return entry.value;
    }

    pub fn putMarkPrice(self: *Self, perp_id: [32]u8, price: f64, now_ts: i64) !void {
        try self.mark_prices.put(perp_id, .{
            .value = price,
            .expires_at = now_ts + self.fast_ttl,
        });
    }

    // -----------------------------------------------------------------
    // Layer 3: Funding rates
    // -----------------------------------------------------------------

    pub fn getFundingRate(self: *Self, perp_id: [32]u8, now_ts: i64) ?i256 {
        const entry = self.funding_rates.get(perp_id) orelse return null;
        if (!entry.isValid(now_ts)) return null;
        return entry.value;
    }

    pub fn putFundingRate(self: *Self, perp_id: [32]u8, rate: i256, now_ts: i64) !void {
        try self.funding_rates.put(perp_id, .{
            .value = rate,
            .expires_at = now_ts + self.fast_ttl,
        });
    }

    // -----------------------------------------------------------------
    // Layer 4: USDC balance
    // -----------------------------------------------------------------

    pub fn getUsdcBalance(self: *Self, now_ts: i64) ?f64 {
        const entry = self.usdc_balance orelse return null;
        if (!entry.isValid(now_ts)) return null;
        return entry.value;
    }

    pub fn putUsdcBalance(self: *Self, balance: f64, now_ts: i64) void {
        self.usdc_balance = .{
            .value = balance,
            .expires_at = now_ts + self.fast_ttl,
        };
    }

    // -----------------------------------------------------------------
    // Invalidation
    // -----------------------------------------------------------------

    /// Invalidate all fast-changing data (call on new block).
    /// Clears mark prices, funding rates, and USDC balance but preserves
    /// the slow layer (fees, bounds).
    pub fn invalidateFastLayer(self: *Self) void {
        self.mark_prices.clearRetainingCapacity();
        self.funding_rates.clearRetainingCapacity();
        self.usdc_balance = null;
    }
};
