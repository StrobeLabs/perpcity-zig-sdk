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
    perp_id: [32]u8,
    trigger_price: f64,
};

pub const ManagedPosition = struct {
    perp_id: [32]u8,
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
/// Thread safety: NOT thread-safe. Callers must synchronize access externally
/// if used from multiple threads.
pub const PositionManager = struct {
    positions: std.AutoHashMap(u256, ManagedPosition),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) PositionManager {
        return .{
            .positions = std.AutoHashMap(u256, ManagedPosition).init(allocator),
            .allocator = allocator,
        };
    }

    /// Register a position to be managed.
    pub fn track(self: *PositionManager, pos: ManagedPosition) !void {
        try self.positions.put(pos.position_id, pos);
    }

    /// Stop tracking a position. Returns true if it was tracked, false otherwise.
    pub fn untrack(self: *PositionManager, position_id: u256) bool {
        return self.positions.remove(position_id);
    }

    /// Get a managed position by ID. Returns a copy.
    pub fn get(self: *const PositionManager, position_id: u256) ?ManagedPosition {
        return self.positions.get(position_id);
    }

    /// Get a mutable pointer to a managed position.
    pub fn getMut(self: *PositionManager, position_id: u256) ?*ManagedPosition {
        return self.positions.getPtr(position_id);
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
                        .perp_id = pos.perp_id,
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
                        .perp_id = pos.perp_id,
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
                        .perp_id = pos.perp_id,
                        .trigger_price = tsp,
                    });
                }
            }
        }

        return triggered.toOwnedSlice(self.allocator);
    }

    /// Get IDs of all tracked positions.
    /// The caller owns the returned slice and must free it with `self.allocator`.
    pub fn allPositionIds(self: *PositionManager) ![]u256 {
        var ids: std.ArrayList(u256) = .empty;
        errdefer ids.deinit(self.allocator);

        var it = self.positions.keyIterator();
        while (it.next()) |key_ptr| {
            try ids.append(self.allocator, key_ptr.*);
        }

        return ids.toOwnedSlice(self.allocator);
    }

    /// Count of tracked positions.
    pub fn count(self: *const PositionManager) usize {
        return self.positions.count();
    }

    pub fn deinit(self: *PositionManager) void {
        self.positions.deinit();
    }
};
