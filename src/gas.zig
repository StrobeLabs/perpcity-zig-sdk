const std = @import("std");

/// Pre-computed gas limits for PerpCity contract calls.
///
/// Avoids calling `estimateGas` on every transaction by using known gas
/// limits with a safety margin baked in.  These values are empirically
/// derived from Base L2 mainnet observations and include ~20% headroom.
pub const GasLimits = struct {
    pub const APPROVE: u64 = 60_000;
    pub const OPEN_TAKER_POS: u64 = 500_000;
    pub const OPEN_MAKER_POS: u64 = 600_000;
    pub const CLOSE_POSITION: u64 = 400_000;
    pub const ADJUST_NOTIONAL: u64 = 350_000;
    pub const ADJUST_MARGIN: u64 = 250_000;
};

/// Cached EIP-1559 gas fee parameters.
pub const GasFees = struct {
    base_fee: u64,
    max_priority_fee: u64,
    max_fee_per_gas: u64,
    updated_at_ms: i64,
};

/// Configuration for creating a `GasCache`.
pub const GasCacheConfig = struct {
    /// Time-to-live in milliseconds for cached gas fees.
    /// Default is 2000ms (one Base L2 block).
    ttl_ms: i64 = 2000,
    /// Default priority fee (tip) in wei.  1 gwei by default.
    default_priority_fee: u64 = 1_000_000_000,
};

/// Transaction urgency level.
///
/// Controls how aggressively the max fee and priority fee are set
/// relative to the cached base fee.
pub const Urgency = enum {
    /// maxFee = baseFee + priorityFee
    low,
    /// maxFee = 2*baseFee + priorityFee  (default EIP-1559 strategy)
    normal,
    /// maxFee = 3*baseFee + 2*priorityFee
    high,
    /// maxFee = 4*baseFee + 5*priorityFee
    critical,
};

/// Gas price cache with configurable TTL.
///
/// Caches the latest base fee from block headers and computes EIP-1559
/// fee parameters for different urgency levels.  Designed for HFT on
/// Base L2 where blocks arrive every 2 seconds -- avoids an
/// `eth_gasPrice` RPC call on every trade.
///
/// All methods that need the current time accept an explicit `now_ms`
/// parameter, keeping the module free of OS-level clock dependencies
/// and making it fully deterministic in tests.
pub const GasCache = struct {
    current: ?GasFees,
    ttl_ms: i64,
    default_priority_fee: u64,

    /// Create a new `GasCache` from the given configuration.
    pub fn init(config: GasCacheConfig) GasCache {
        return .{
            .current = null,
            .ttl_ms = config.ttl_ms,
            .default_priority_fee = config.default_priority_fee,
        };
    }

    /// Check if cached gas fees are still valid at the given time.
    /// Returns `false` when there is no cached value or the cache
    /// has expired.
    pub fn isValid(self: *const GasCache, now_ms: i64) bool {
        const fees = self.current orelse return false;
        return (now_ms - fees.updated_at_ms) < self.ttl_ms;
    }

    /// Get cached fees, or `null` if stale / not yet populated.
    pub fn get(self: *const GasCache, now_ms: i64) ?GasFees {
        if (self.isValid(now_ms)) {
            return self.current;
        }
        return null;
    }

    /// Update the cache from a new block's base fee.
    ///
    /// Computes the "normal" urgency EIP-1559 fee parameters and
    /// stores them as the current cached value.
    pub fn updateFromBlock(self: *GasCache, base_fee: u64, now_ms: i64) void {
        const priority = self.default_priority_fee;
        self.current = .{
            .base_fee = base_fee,
            .max_priority_fee = priority,
            .max_fee_per_gas = 2 * base_fee + priority,
            .updated_at_ms = now_ms,
        };
    }

    /// Compute gas fees for a specific urgency level.
    ///
    /// Returns `null` when the cache is stale or not yet populated.
    /// The priority fee and max fee are scaled according to urgency:
    ///   - low:      maxFee = baseFee + priorityFee
    ///   - normal:   maxFee = 2*baseFee + priorityFee
    ///   - high:     maxFee = 3*baseFee + 2*priorityFee
    ///   - critical: maxFee = 4*baseFee + 5*priorityFee
    pub fn feesForUrgency(self: *const GasCache, urgency: Urgency, now_ms: i64) ?GasFees {
        const cached = self.get(now_ms) orelse return null;

        const base = cached.base_fee;
        const prio = self.default_priority_fee;

        const effective_priority: u64 = switch (urgency) {
            .low => prio,
            .normal => prio,
            .high => 2 * prio,
            .critical => 5 * prio,
        };

        const max_fee: u64 = switch (urgency) {
            .low => base + prio,
            .normal => 2 * base + prio,
            .high => 3 * base + 2 * prio,
            .critical => 4 * base + 5 * prio,
        };

        return .{
            .base_fee = base,
            .max_priority_fee = effective_priority,
            .max_fee_per_gas = max_fee,
            .updated_at_ms = cached.updated_at_ms,
        };
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "GasLimits constants are reasonable" {
    try std.testing.expect(GasLimits.APPROVE > 0);
    try std.testing.expect(GasLimits.OPEN_TAKER_POS > GasLimits.APPROVE);
    try std.testing.expect(GasLimits.OPEN_MAKER_POS > GasLimits.OPEN_TAKER_POS);
    try std.testing.expect(GasLimits.CLOSE_POSITION > GasLimits.ADJUST_MARGIN);
    try std.testing.expectEqual(@as(u64, 60_000), GasLimits.APPROVE);
    try std.testing.expectEqual(@as(u64, 500_000), GasLimits.OPEN_TAKER_POS);
    try std.testing.expectEqual(@as(u64, 600_000), GasLimits.OPEN_MAKER_POS);
    try std.testing.expectEqual(@as(u64, 400_000), GasLimits.CLOSE_POSITION);
    try std.testing.expectEqual(@as(u64, 350_000), GasLimits.ADJUST_NOTIONAL);
    try std.testing.expectEqual(@as(u64, 250_000), GasLimits.ADJUST_MARGIN);
}

test "GasCache init sets defaults" {
    const cache = GasCache.init(.{});

    try std.testing.expectEqual(@as(?GasFees, null), cache.current);
    try std.testing.expectEqual(@as(i64, 2000), cache.ttl_ms);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), cache.default_priority_fee);
}

test "GasCache init accepts custom config" {
    const cache = GasCache.init(.{
        .ttl_ms = 500,
        .default_priority_fee = 2_000_000_000,
    });

    try std.testing.expectEqual(@as(i64, 500), cache.ttl_ms);
    try std.testing.expectEqual(@as(u64, 2_000_000_000), cache.default_priority_fee);
}

test "GasCache isValid returns false when empty" {
    const cache = GasCache.init(.{});
    try std.testing.expect(!cache.isValid(1000));
}

test "GasCache isValid returns true within TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expect(cache.isValid(1000));
    try std.testing.expect(cache.isValid(2999));
}

test "GasCache isValid returns false after TTL expires" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expect(!cache.isValid(3000));
    try std.testing.expect(!cache.isValid(5000));
}

test "GasCache get returns null when empty" {
    const cache = GasCache.init(.{});
    try std.testing.expectEqual(@as(?GasFees, null), cache.get(1000));
}

test "GasCache get returns fees within TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    const fees = cache.get(2000);
    try std.testing.expect(fees != null);
    try std.testing.expectEqual(@as(u64, 100), fees.?.base_fee);
}

test "GasCache get returns null after TTL" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expectEqual(@as(?GasFees, null), cache.get(3000));
}

test "GasCache updateFromBlock stores normal urgency fees" {
    var cache = GasCache.init(.{ .default_priority_fee = 1_000_000_000 });
    cache.updateFromBlock(50_000_000_000, 5000);

    const fees = cache.current.?;
    try std.testing.expectEqual(@as(u64, 50_000_000_000), fees.base_fee);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), fees.max_priority_fee);
    // normal: 2*base + priority
    try std.testing.expectEqual(@as(u64, 2 * 50_000_000_000 + 1_000_000_000), fees.max_fee_per_gas);
    try std.testing.expectEqual(@as(i64, 5000), fees.updated_at_ms);
}

test "GasCache updateFromBlock replaces previous value" {
    var cache = GasCache.init(.{});
    cache.updateFromBlock(100, 1000);
    cache.updateFromBlock(200, 2000);

    const fees = cache.current.?;
    try std.testing.expectEqual(@as(u64, 200), fees.base_fee);
    try std.testing.expectEqual(@as(i64, 2000), fees.updated_at_ms);
}

test "feesForUrgency returns null when cache is empty" {
    const cache = GasCache.init(.{});
    try std.testing.expectEqual(@as(?GasFees, null), cache.feesForUrgency(.normal, 1000));
}

test "feesForUrgency returns null when cache is stale" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    try std.testing.expectEqual(@as(?GasFees, null), cache.feesForUrgency(.normal, 3000));
}

test "feesForUrgency low: maxFee = baseFee + priorityFee" {
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

test "feesForUrgency normal: maxFee = 2*baseFee + priorityFee" {
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

test "feesForUrgency high: maxFee = 3*baseFee + 2*priorityFee" {
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

test "feesForUrgency critical: maxFee = 4*baseFee + 5*priorityFee" {
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

test "feesForUrgency preserves updated_at_ms from cache" {
    var cache = GasCache.init(.{ .ttl_ms = 5000 });
    cache.updateFromBlock(100, 42_000);

    const fees = cache.feesForUrgency(.normal, 43_000).?;
    try std.testing.expectEqual(@as(i64, 42_000), fees.updated_at_ms);
}

test "cache expiry boundary - exactly at TTL boundary is expired" {
    var cache = GasCache.init(.{ .ttl_ms = 2000 });
    cache.updateFromBlock(100, 1000);

    // At exactly ttl_ms after update, the cache should be expired.
    // isValid checks: (now - updated_at) < ttl, so 3000 - 1000 = 2000 is NOT < 2000.
    try std.testing.expect(!cache.isValid(3000));
    // One ms before should still be valid.
    try std.testing.expect(cache.isValid(2999));
}
