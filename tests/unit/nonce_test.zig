const std = @import("std");
const sdk = @import("perpcity_sdk");
const HftNonceManager = sdk.nonce.HftNonceManager;

// =============================================================================
// Single-threaded behavior
// =============================================================================

test "acquireNonce returns sequential nonces" {
    var mgr = HftNonceManager.init(std.testing.allocator, 5);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(u64, 5), mgr.acquireNonce());
    try std.testing.expectEqual(@as(u64, 6), mgr.acquireNonce());
    try std.testing.expectEqual(@as(u64, 7), mgr.acquireNonce());
    try std.testing.expectEqual(@as(u64, 8), mgr.peekNextNonce());
}

test "releaseNonce rewinds only the last acquired nonce" {
    var mgr = HftNonceManager.init(std.testing.allocator, 10);
    defer mgr.deinit();

    const n0 = mgr.acquireNonce(); // 10
    const n1 = mgr.acquireNonce(); // 11

    // Releasing n0 should NOT rewind because n1 was acquired after it.
    mgr.releaseNonce(n0);
    try std.testing.expectEqual(@as(u64, 12), mgr.peekNextNonce());

    // Releasing n1 (the last acquired) should rewind next_nonce from 12 to 11.
    mgr.releaseNonce(n1);
    try std.testing.expectEqual(@as(u64, 11), mgr.peekNextNonce());

    // Acquiring again should give us 11 (the rewound nonce).
    try std.testing.expectEqual(@as(u64, 11), mgr.acquireNonce());
}

test "confirmNonce removes from pending" {
    var mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer mgr.deinit();

    const n = mgr.acquireNonce();
    try mgr.trackSubmission(n, [_]u8{0xAB} ** 32);
    try std.testing.expectEqual(@as(usize, 1), mgr.pendingCount());

    mgr.confirmNonce(n);
    try std.testing.expectEqual(@as(usize, 0), mgr.pendingCount());
}

test "pendingCount tracks multiple submissions" {
    var mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 0), mgr.pendingCount());

    const n0 = mgr.acquireNonce();
    const n1 = mgr.acquireNonce();
    const n2 = mgr.acquireNonce();

    try mgr.trackSubmission(n0, [_]u8{0x01} ** 32);
    try mgr.trackSubmission(n1, [_]u8{0x02} ** 32);
    try mgr.trackSubmission(n2, [_]u8{0x03} ** 32);
    try std.testing.expectEqual(@as(usize, 3), mgr.pendingCount());

    mgr.confirmNonce(n1);
    try std.testing.expectEqual(@as(usize, 2), mgr.pendingCount());

    mgr.confirmNonce(n0);
    mgr.confirmNonce(n2);
    try std.testing.expectEqual(@as(usize, 0), mgr.pendingCount());
}

test "resync resets nonce and clears pending" {
    var mgr = HftNonceManager.init(std.testing.allocator, 100);
    defer mgr.deinit();

    const n = mgr.acquireNonce();
    try mgr.trackSubmission(n, [_]u8{0xFF} ** 32);
    try std.testing.expectEqual(@as(usize, 1), mgr.pendingCount());

    mgr.resync(200);
    try std.testing.expectEqual(@as(u64, 200), mgr.peekNextNonce());
    try std.testing.expectEqual(@as(usize, 0), mgr.pendingCount());
}

test "releaseNonce also removes from pending" {
    var mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer mgr.deinit();

    const n = mgr.acquireNonce();
    try mgr.trackSubmission(n, [_]u8{0xCC} ** 32);
    try std.testing.expectEqual(@as(usize, 1), mgr.pendingCount());

    mgr.releaseNonce(n);
    try std.testing.expectEqual(@as(usize, 0), mgr.pendingCount());
}

// =============================================================================
// Concurrency stress tests
//
// These exercise the lock-free counter and the mutex-guarded pending map under
// real OS-thread contention, validating the thread-safety claim (and that the
// std.Io.Mutex + global_single_threaded io handle locks correctly cross-thread).
// =============================================================================

const StressWorkers = struct {
    /// Fill `out` with acquired nonces (one atomic fetch-add per slot).
    fn acquireInto(m: *HftNonceManager, out: []u64) void {
        for (out) |*slot| slot.* = m.acquireNonce();
    }

    /// Track then immediately confirm `count` nonces starting at `base`,
    /// hammering the mutex-guarded pending map from multiple threads.
    fn trackAndConfirm(m: *HftNonceManager, base: u64, count: u64) void {
        var i: u64 = 0;
        while (i < count) : (i += 1) {
            const n = base + i;
            m.trackSubmission(n, [_]u8{0} ** 32) catch {};
            m.confirmNonce(n);
        }
    }
};

test "acquireNonce yields unique, gapless nonces under concurrent load" {
    var mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer mgr.deinit();

    const thread_count = 8;
    const per_thread = 512;
    var results: [thread_count][per_thread]u64 = undefined;
    var threads: [thread_count]std.Thread = undefined;

    for (&threads, 0..) |*t, i| {
        t.* = try std.Thread.spawn(.{}, StressWorkers.acquireInto, .{ &mgr, results[i][0..] });
    }
    for (&threads) |t| t.join();

    // Every acquired nonce must be unique; together they cover [0, total).
    var seen = std.AutoHashMap(u64, void).init(std.testing.allocator);
    defer seen.deinit();
    for (results) |arr| {
        for (arr) |n| {
            const gop = try seen.getOrPut(n);
            try std.testing.expect(!gop.found_existing);
        }
    }
    try std.testing.expectEqual(@as(usize, thread_count * per_thread), seen.count());
    try std.testing.expectEqual(@as(u64, thread_count * per_thread), mgr.peekNextNonce());
}

test "concurrent trackSubmission/confirmNonce keep the pending map consistent" {
    var mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer mgr.deinit();

    const thread_count = 8;
    const per_thread: u64 = 500;
    var threads: [thread_count]std.Thread = undefined;

    for (&threads, 0..) |*t, i| {
        const base = @as(u64, @intCast(i)) * per_thread;
        t.* = try std.Thread.spawn(.{}, StressWorkers.trackAndConfirm, .{ &mgr, base, per_thread });
    }
    for (&threads) |t| t.join();

    // Every tracked nonce was confirmed on its own disjoint range, so the map
    // must be empty and uncorrupted.
    try std.testing.expectEqual(@as(usize, 0), mgr.pendingCount());
}
