const std = @import("std");
const types = @import("types.zig");

pub const TriggerType = enum {
    stop_loss,
    take_profit,
    trailing_stop,
};

pub const TriggerAction = struct {
    trigger_type: TriggerType,
    position_id: u256,
    perp: [20]u8,
    trigger_price: f64,
};

/// Composite key: per-market position IDs collide across markets, so callers
/// must scope by `(perp, position_id)`.
pub const PositionKey = struct {
    perp: [20]u8,
    position_id: u256,
};

pub const ManagedPosition = struct {
    perp: [20]u8,
    position_id: u256,
    is_long: bool,
    is_maker: bool,
    entry_price: f64,
    margin: f64,

    // Trigger prices (null = disabled)
    stop_loss: ?f64 = null,
    take_profit: ?f64 = null,
    trailing_stop_pct: ?f64 = null, // e.g., 0.02 = 2%
    trailing_stop_high: ?f64 = null, // highest price seen (for trailing stop)

    pub fn key(self: *const ManagedPosition) PositionKey {
        return .{ .perp = self.perp, .position_id = self.position_id };
    }

    /// Update the trailing stop high-water mark.
    /// For longs, tracks the highest price seen.
    /// For shorts, tracks the lowest price seen.
    pub fn updateTrailingHigh(self: *ManagedPosition, current_price: f64) void {
        if (self.trailing_stop_pct == null) return;
        if (self.is_long) {
            if (self.trailing_stop_high == null or current_price > self.trailing_stop_high.?) {
                self.trailing_stop_high = current_price;
            }
        } else {
            // For shorts, track the lowest price
            if (self.trailing_stop_high == null or current_price < self.trailing_stop_high.?) {
                self.trailing_stop_high = current_price;
            }
        }
    }

    /// Get the effective trailing stop price.
    /// For longs: high * (1 - pct) -- triggers when price drops below.
    /// For shorts: low * (1 + pct) -- triggers when price rises above.
    pub fn trailingStopPrice(self: *const ManagedPosition) ?f64 {
        const pct = self.trailing_stop_pct orelse return null;
        const high = self.trailing_stop_high orelse return null;
        if (self.is_long) {
            return high * (1.0 - pct);
        } else {
            return high * (1.0 + pct);
        }
    }
};

/// Higher-level position manager with stop-loss, take-profit, and trailing
/// stop triggers for HFT bots.
///
/// Positions are keyed by `(perp, position_id)` because each Perp market has
/// its own monotonically increasing ID space starting at 1.
///
/// Thread safety: NOT thread-safe. Callers must synchronize access externally
/// if used from multiple threads.
pub const PositionManager = struct {
    positions: std.AutoHashMap(PositionKey, ManagedPosition),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PositionManager {
        return .{
            .positions = std.AutoHashMap(PositionKey, ManagedPosition).init(allocator),
            .allocator = allocator,
        };
    }

    /// Register a position to be managed.
    pub fn track(self: *PositionManager, pos: ManagedPosition) !void {
        try self.positions.put(pos.key(), pos);
    }

    /// Stop tracking a position. Returns true if it was tracked, false otherwise.
    pub fn untrack(self: *PositionManager, perp: [20]u8, position_id: u256) bool {
        return self.positions.remove(.{ .perp = perp, .position_id = position_id });
    }

    /// Get a managed position by (perp, id). Returns a copy.
    pub fn get(self: *const PositionManager, perp: [20]u8, position_id: u256) ?ManagedPosition {
        return self.positions.get(.{ .perp = perp, .position_id = position_id });
    }

    /// Get a mutable pointer to a managed position.
    pub fn getMut(self: *PositionManager, perp: [20]u8, position_id: u256) ?*ManagedPosition {
        return self.positions.getPtr(.{ .perp = perp, .position_id = position_id });
    }

    /// Check all positions against the current price and return triggered actions.
    /// The caller is responsible for executing the close transactions.
    /// The caller owns the returned slice and must free it with `self.allocator`.
    pub fn checkTriggers(self: *PositionManager, current_price: f64) ![]TriggerAction {
        var triggered: std.ArrayList(TriggerAction) = .empty;
        errdefer triggered.deinit(self.allocator);

        var it = self.positions.iterator();
        while (it.next()) |entry| {
            var pos = entry.value_ptr;
            pos.updateTrailingHigh(current_price);

            // Check stop loss
            if (pos.stop_loss) |sl| {
                const hit = if (pos.is_long) current_price <= sl else current_price >= sl;
                if (hit) {
                    try triggered.append(self.allocator, .{
                        .trigger_type = .stop_loss,
                        .position_id = pos.position_id,
                        .perp = pos.perp,
                        .trigger_price = sl,
                    });
                    continue; // Don't check other triggers if stop loss hit
                }
            }

            // Check take profit
            if (pos.take_profit) |tp| {
                const hit = if (pos.is_long) current_price >= tp else current_price <= tp;
                if (hit) {
                    try triggered.append(self.allocator, .{
                        .trigger_type = .take_profit,
                        .position_id = pos.position_id,
                        .perp = pos.perp,
                        .trigger_price = tp,
                    });
                    continue;
                }
            }

            // Check trailing stop
            if (pos.trailingStopPrice()) |tsp| {
                const hit = if (pos.is_long) current_price <= tsp else current_price >= tsp;
                if (hit) {
                    try triggered.append(self.allocator, .{
                        .trigger_type = .trailing_stop,
                        .position_id = pos.position_id,
                        .perp = pos.perp,
                        .trigger_price = tsp,
                    });
                }
            }
        }

        return triggered.toOwnedSlice(self.allocator);
    }

    /// Get keys for all tracked positions.
    /// The caller owns the returned slice and must free it with `self.allocator`.
    pub fn allPositionKeys(self: *PositionManager) ![]PositionKey {
        var keys: std.ArrayList(PositionKey) = .empty;
        errdefer keys.deinit(self.allocator);

        var it = self.positions.keyIterator();
        while (it.next()) |key_ptr| {
            try keys.append(self.allocator, key_ptr.*);
        }

        return keys.toOwnedSlice(self.allocator);
    }

    /// Count of tracked positions.
    pub fn count(self: *const PositionManager) usize {
        return self.positions.count();
    }

    pub fn deinit(self: *PositionManager) void {
        self.positions.deinit();
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "PositionManager - distinct perps with the same pos_id coexist" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const perp_a: [20]u8 = [_]u8{0xAA} ** 20;
    const perp_b: [20]u8 = [_]u8{0xBB} ** 20;

    try mgr.track(.{ .perp = perp_a, .position_id = 1, .is_long = true, .is_maker = false, .entry_price = 100, .margin = 10 });
    try mgr.track(.{ .perp = perp_b, .position_id = 1, .is_long = false, .is_maker = false, .entry_price = 200, .margin = 20 });

    try std.testing.expectEqual(@as(usize, 2), mgr.count());
    try std.testing.expectEqual(true, mgr.get(perp_a, 1).?.is_long);
    try std.testing.expectEqual(false, mgr.get(perp_b, 1).?.is_long);

    try std.testing.expect(mgr.untrack(perp_a, 1));
    try std.testing.expectEqual(@as(usize, 1), mgr.count());
    try std.testing.expectEqual(@as(?ManagedPosition, null), mgr.get(perp_a, 1));
}
