const std = @import("std");
const sdk = @import("perpcity_sdk");
const pm = sdk.position_manager;
const PositionManager = pm.PositionManager;
const ManagedPosition = pm.ManagedPosition;
const TriggerType = pm.TriggerType;
const TriggerAction = pm.TriggerAction;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makePerp(byte: u8) [32]u8 {
    return [_]u8{byte} ** 32;
}

fn makeLongPosition(id: u256, entry_price: f64, margin: f64) ManagedPosition {
    return .{
        .perp_id = makePerp(0xAA),
        .position_id = id,
        .is_long = true,
        .is_maker = false,
        .entry_price = entry_price,
        .margin = margin,
    };
}

fn makeShortPosition(id: u256, entry_price: f64, margin: f64) ManagedPosition {
    return .{
        .perp_id = makePerp(0xBB),
        .position_id = id,
        .is_long = false,
        .is_maker = false,
        .entry_price = entry_price,
        .margin = margin,
    };
}

/// Find a trigger action in a slice by position_id.
fn findTrigger(triggers: []const TriggerAction, position_id: u256) ?TriggerAction {
    for (triggers) |t| {
        if (t.position_id == position_id) return t;
    }
    return null;
}

// =============================================================================
// track() and get()
// =============================================================================

test "track and get - stores and retrieves a position" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.stop_loss = 1400.0;
    pos.take_profit = 1700.0;

    try mgr.track(pos);

    const retrieved = mgr.get(1).?;
    try std.testing.expectEqual(@as(u256, 1), retrieved.position_id);
    try std.testing.expectEqual(true, retrieved.is_long);
    try std.testing.expectEqual(@as(f64, 1500.0), retrieved.entry_price);
    try std.testing.expectEqual(@as(f64, 100.0), retrieved.margin);
    try std.testing.expectEqual(@as(?f64, 1400.0), retrieved.stop_loss);
    try std.testing.expectEqual(@as(?f64, 1700.0), retrieved.take_profit);
}

test "get - returns null for non-existent position" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(?ManagedPosition, null), mgr.get(999));
}

test "track - overwrites existing position with same ID" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos1 = makeLongPosition(1, 1500.0, 100.0);
    pos1.stop_loss = 1400.0;
    try mgr.track(pos1);

    var pos2 = makeLongPosition(1, 1600.0, 200.0);
    pos2.stop_loss = 1500.0;
    try mgr.track(pos2);

    try std.testing.expectEqual(@as(usize, 1), mgr.count());
    const retrieved = mgr.get(1).?;
    try std.testing.expectEqual(@as(f64, 1600.0), retrieved.entry_price);
    try std.testing.expectEqual(@as(f64, 200.0), retrieved.margin);
}

// =============================================================================
// untrack()
// =============================================================================

test "untrack - removes tracked position and returns true" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try mgr.track(makeLongPosition(1, 1500.0, 100.0));
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    try std.testing.expect(mgr.untrack(1));
    try std.testing.expectEqual(@as(usize, 0), mgr.count());
    try std.testing.expectEqual(@as(?ManagedPosition, null), mgr.get(1));
}

test "untrack - returns false for non-existent position" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try std.testing.expect(!mgr.untrack(999));
}

// =============================================================================
// checkTriggers: stop loss
// =============================================================================

test "checkTriggers - stop loss hit for long when price drops below" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.stop_loss = 1400.0;
    try mgr.track(pos);

    // Price drops to 1350, below the 1400 stop loss
    const triggers = try mgr.checkTriggers(1350.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.stop_loss, triggers[0].trigger_type);
    try std.testing.expectEqual(@as(u256, 1), triggers[0].position_id);
    try std.testing.expectEqual(@as(f64, 1400.0), triggers[0].trigger_price);
}

test "checkTriggers - stop loss hit for long at exact stop price" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.stop_loss = 1400.0;
    try mgr.track(pos);

    // Price exactly at the stop loss
    const triggers = try mgr.checkTriggers(1400.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.stop_loss, triggers[0].trigger_type);
}

test "checkTriggers - stop loss hit for short when price rises above" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeShortPosition(2, 1500.0, 100.0);
    pos.stop_loss = 1600.0;
    try mgr.track(pos);

    // Price rises to 1650, above the 1600 stop loss for short
    const triggers = try mgr.checkTriggers(1650.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.stop_loss, triggers[0].trigger_type);
    try std.testing.expectEqual(@as(u256, 2), triggers[0].position_id);
    try std.testing.expectEqual(@as(f64, 1600.0), triggers[0].trigger_price);
}

// =============================================================================
// checkTriggers: take profit
// =============================================================================

test "checkTriggers - take profit hit for long when price rises above" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.take_profit = 1700.0;
    try mgr.track(pos);

    // Price rises to 1750, above the 1700 take profit
    const triggers = try mgr.checkTriggers(1750.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.take_profit, triggers[0].trigger_type);
    try std.testing.expectEqual(@as(u256, 1), triggers[0].position_id);
    try std.testing.expectEqual(@as(f64, 1700.0), triggers[0].trigger_price);
}

test "checkTriggers - take profit hit for short when price drops below" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeShortPosition(2, 1500.0, 100.0);
    pos.take_profit = 1300.0;
    try mgr.track(pos);

    // Price drops to 1250, below the 1300 take profit for short
    const triggers = try mgr.checkTriggers(1250.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.take_profit, triggers[0].trigger_type);
    try std.testing.expectEqual(@as(u256, 2), triggers[0].position_id);
    try std.testing.expectEqual(@as(f64, 1300.0), triggers[0].trigger_price);
}

// =============================================================================
// checkTriggers: trailing stop
// =============================================================================

test "checkTriggers - trailing stop updates high-water mark and triggers on retrace" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.05; // 5%
    try mgr.track(pos);

    // Price rises to 1600 -- should set high-water mark, no trigger
    {
        const triggers = try mgr.checkTriggers(1600.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 0), triggers.len);
    }

    // Verify high-water mark was set
    {
        const p = mgr.get(1).?;
        try std.testing.expectEqual(@as(?f64, 1600.0), p.trailing_stop_high);
    }

    // Price rises further to 1700
    {
        const triggers = try mgr.checkTriggers(1700.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 0), triggers.len);
    }

    // Verify high-water mark updated
    {
        const p = mgr.get(1).?;
        try std.testing.expectEqual(@as(?f64, 1700.0), p.trailing_stop_high);
    }

    // Now price drops to 1600 -- trailing stop at 1700 * 0.95 = 1615, not hit
    {
        const triggers = try mgr.checkTriggers(1620.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 0), triggers.len);
    }

    // Price drops to 1610 -- still above 1615
    {
        const triggers = try mgr.checkTriggers(1616.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 0), triggers.len);
    }

    // Price drops to 1610 -- below 1615, triggers trailing stop
    {
        const triggers = try mgr.checkTriggers(1610.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 1), triggers.len);
        try std.testing.expectEqual(TriggerType.trailing_stop, triggers[0].trigger_type);
        try std.testing.expectEqual(@as(u256, 1), triggers[0].position_id);
        // trailing stop price = 1700 * 0.95 = 1615
        try std.testing.expectEqual(@as(f64, 1700.0 * 0.95), triggers[0].trigger_price);
    }
}

test "checkTriggers - trailing stop for short tracks lowest price and triggers on rise" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeShortPosition(2, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.04; // 4%
    try mgr.track(pos);

    // Price drops to 1400 -- sets low-water mark
    {
        const triggers = try mgr.checkTriggers(1400.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 0), triggers.len);
    }

    // Price drops further to 1300
    {
        const triggers = try mgr.checkTriggers(1300.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 0), triggers.len);
    }

    // Verify low-water mark updated
    {
        const p = mgr.get(2).?;
        try std.testing.expectEqual(@as(?f64, 1300.0), p.trailing_stop_high);
    }

    // Price rises to 1352 -- trailing stop at 1300 * 1.04 = 1352, exactly at boundary
    {
        const triggers = try mgr.checkTriggers(1352.0);
        defer std.testing.allocator.free(triggers);
        try std.testing.expectEqual(@as(usize, 1), triggers.len);
        try std.testing.expectEqual(TriggerType.trailing_stop, triggers[0].trigger_type);
        try std.testing.expectEqual(@as(f64, 1300.0 * 1.04), triggers[0].trigger_price);
    }
}

// =============================================================================
// checkTriggers: no triggers in safe zone
// =============================================================================

test "checkTriggers - no triggers when price is in safe zone" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.stop_loss = 1400.0;
    pos.take_profit = 1700.0;
    pos.trailing_stop_pct = 0.05;
    try mgr.track(pos);

    // Price is 1550 -- above stop loss, below take profit, no trailing stop high yet
    // First call sets trailing_stop_high to 1550. Trailing stop price = 1550*0.95 = 1472.5
    // 1550 > 1472.5 so trailing stop not hit either.
    const triggers = try mgr.checkTriggers(1550.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 0), triggers.len);
}

test "checkTriggers - no triggers on empty manager" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const triggers = try mgr.checkTriggers(1500.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 0), triggers.len);
}

// =============================================================================
// checkTriggers: stop loss takes priority over take profit
// =============================================================================

test "checkTriggers - stop loss takes priority over take profit" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    // Contrived scenario: set stop_loss and take_profit to the same value.
    // For a long, if price <= stop_loss AND price >= take_profit at the same time,
    // stop loss should be reported (it is checked first and continues).
    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.stop_loss = 1500.0;
    pos.take_profit = 1500.0;
    try mgr.track(pos);

    const triggers = try mgr.checkTriggers(1500.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.stop_loss, triggers[0].trigger_type);
}

test "checkTriggers - stop loss for short takes priority over take profit" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    // For short: stop_loss triggers when price >= sl, take profit when price <= tp.
    // Set both to same value.
    var pos = makeShortPosition(2, 1500.0, 100.0);
    pos.stop_loss = 1500.0;
    pos.take_profit = 1500.0;
    try mgr.track(pos);

    const triggers = try mgr.checkTriggers(1500.0);
    defer std.testing.allocator.free(triggers);

    try std.testing.expectEqual(@as(usize, 1), triggers.len);
    try std.testing.expectEqual(TriggerType.stop_loss, triggers[0].trigger_type);
}

// =============================================================================
// allPositionIds and count
// =============================================================================

test "count - returns zero on empty manager" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 0), mgr.count());
}

test "count - tracks number of managed positions" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try mgr.track(makeLongPosition(1, 1500.0, 100.0));
    try std.testing.expectEqual(@as(usize, 1), mgr.count());

    try mgr.track(makeShortPosition(2, 1500.0, 100.0));
    try std.testing.expectEqual(@as(usize, 2), mgr.count());

    _ = mgr.untrack(1);
    try std.testing.expectEqual(@as(usize, 1), mgr.count());
}

test "allPositionIds - returns empty slice when no positions" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    const ids = try mgr.allPositionIds();
    defer std.testing.allocator.free(ids);

    try std.testing.expectEqual(@as(usize, 0), ids.len);
}

test "allPositionIds - returns all tracked position IDs" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try mgr.track(makeLongPosition(10, 1500.0, 100.0));
    try mgr.track(makeShortPosition(20, 1500.0, 100.0));
    try mgr.track(makeLongPosition(30, 1600.0, 200.0));

    const ids = try mgr.allPositionIds();
    defer std.testing.allocator.free(ids);

    try std.testing.expectEqual(@as(usize, 3), ids.len);

    // Sort for deterministic comparison (hash map order is not guaranteed)
    std.mem.sort(u256, ids, {}, std.sort.asc(u256));

    try std.testing.expectEqual(@as(u256, 10), ids[0]);
    try std.testing.expectEqual(@as(u256, 20), ids[1]);
    try std.testing.expectEqual(@as(u256, 30), ids[2]);
}

// =============================================================================
// ManagedPosition.trailingStopPrice calculation
// =============================================================================

test "trailingStopPrice - returns null when trailing_stop_pct is null" {
    const pos = makeLongPosition(1, 1500.0, 100.0);
    try std.testing.expectEqual(@as(?f64, null), pos.trailingStopPrice());
}

test "trailingStopPrice - returns null when trailing_stop_high is null" {
    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.05;
    // trailing_stop_high is null by default
    try std.testing.expectEqual(@as(?f64, null), pos.trailingStopPrice());
}

test "trailingStopPrice - calculates correctly for long" {
    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.05; // 5%
    pos.trailing_stop_high = 2000.0;

    // 2000 * (1 - 0.05) = 2000 * 0.95 = 1900
    const tsp = pos.trailingStopPrice().?;
    try std.testing.expect(@abs(tsp - 1900.0) < 0.001);
}

test "trailingStopPrice - calculates correctly for short" {
    var pos = makeShortPosition(2, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.03; // 3%
    pos.trailing_stop_high = 1200.0; // low water mark for shorts

    // 1200 * (1 + 0.03) = 1200 * 1.03 = 1236
    const tsp = pos.trailingStopPrice().?;
    try std.testing.expect(@abs(tsp - 1236.0) < 0.001);
}

// =============================================================================
// ManagedPosition.updateTrailingHigh
// =============================================================================

test "updateTrailingHigh - no-op when trailing_stop_pct is null" {
    var pos = makeLongPosition(1, 1500.0, 100.0);
    // trailing_stop_pct is null by default
    pos.updateTrailingHigh(2000.0);
    try std.testing.expectEqual(@as(?f64, null), pos.trailing_stop_high);
}

test "updateTrailingHigh - sets initial high for long" {
    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.05;
    pos.updateTrailingHigh(1600.0);
    try std.testing.expectEqual(@as(?f64, 1600.0), pos.trailing_stop_high);
}

test "updateTrailingHigh - updates only when higher for long" {
    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.05;
    pos.trailing_stop_high = 1600.0;

    pos.updateTrailingHigh(1550.0); // lower, should not update
    try std.testing.expectEqual(@as(?f64, 1600.0), pos.trailing_stop_high);

    pos.updateTrailingHigh(1700.0); // higher, should update
    try std.testing.expectEqual(@as(?f64, 1700.0), pos.trailing_stop_high);
}

test "updateTrailingHigh - tracks lowest price for short" {
    var pos = makeShortPosition(2, 1500.0, 100.0);
    pos.trailing_stop_pct = 0.05;
    pos.updateTrailingHigh(1400.0);
    try std.testing.expectEqual(@as(?f64, 1400.0), pos.trailing_stop_high);

    pos.updateTrailingHigh(1450.0); // higher, should not update for short
    try std.testing.expectEqual(@as(?f64, 1400.0), pos.trailing_stop_high);

    pos.updateTrailingHigh(1350.0); // lower, should update for short
    try std.testing.expectEqual(@as(?f64, 1350.0), pos.trailing_stop_high);
}

// =============================================================================
// getMut
// =============================================================================

test "getMut - returns mutable pointer to position" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    var pos = makeLongPosition(1, 1500.0, 100.0);
    pos.stop_loss = 1400.0;
    try mgr.track(pos);

    // Modify via getMut
    const ptr = mgr.getMut(1).?;
    ptr.stop_loss = 1350.0;

    // Verify modification persisted
    const retrieved = mgr.get(1).?;
    try std.testing.expectEqual(@as(?f64, 1350.0), retrieved.stop_loss);
}

test "getMut - returns null for non-existent position" {
    var mgr = PositionManager.init(std.testing.allocator);
    defer mgr.deinit();

    try std.testing.expect(mgr.getMut(999) == null);
}
