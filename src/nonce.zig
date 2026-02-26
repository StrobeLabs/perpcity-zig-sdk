const std = @import("std");

/// High-performance local nonce manager for HFT bots.
///
/// Avoids calling `eth_getTransactionCount` on every transaction by fetching
/// the nonce once at startup and managing it locally. Nonce acquisition is
/// lock-free (atomic fetch-add); only the pending-transaction bookkeeping
/// requires a mutex.
pub const HftNonceManager = struct {
    /// Next nonce to use (atomic for thread safety).
    next_nonce: std.atomic.Value(u64),

    /// Pending (unconfirmed) transactions tracked by nonce.
    pending: std.AutoHashMap(u64, PendingTx),

    /// Protects the `pending` hash map.
    /// Uses `std.Thread.Mutex` with a spin-lock pattern.
    mutex: std.Thread.Mutex,

    pub const PendingTx = struct {
        tx_hash: [32]u8,
        nonce: u64,
        submitted_at_ms: i64,
    };

    /// Acquire the mutex.
    fn spinLock(self: *HftNonceManager) void {
        self.mutex.lock();
    }

    /// Initialize with a known starting nonce.
    ///
    /// The caller is responsible for fetching the on-chain nonce count
    /// (e.g. via `provider.getAddressTransactionCount`) and passing it here.
    /// This keeps the nonce manager decoupled from any specific RPC client.
    pub fn init(allocator: std.mem.Allocator, starting_nonce: u64) HftNonceManager {
        return .{
            .next_nonce = std.atomic.Value(u64).init(starting_nonce),
            .pending = std.AutoHashMap(u64, PendingTx).init(allocator),
            .mutex = .{},
        };
    }

    /// Acquire the next nonce without any RPC call. Lock-free via atomic
    /// fetch-add -- safe for concurrent use from multiple threads.
    pub fn acquireNonce(self: *HftNonceManager) u64 {
        return self.next_nonce.fetchAdd(1, .seq_cst);
    }

    /// Track a submitted transaction for receipt monitoring.
    pub fn trackSubmission(self: *HftNonceManager, nonce_val: u64, tx_hash: [32]u8) !void {
        self.spinLock();
        defer self.mutex.unlock();
        try self.pending.put(nonce_val, .{
            .tx_hash = tx_hash,
            .nonce = nonce_val,
            .submitted_at_ms = 0, // Caller tracks timestamps externally.
        });
    }

    /// Mark a nonce as confirmed (remove from pending).
    pub fn confirmNonce(self: *HftNonceManager, nonce_val: u64) void {
        self.spinLock();
        defer self.mutex.unlock();
        _ = self.pending.remove(nonce_val);
    }

    /// Release a nonce for reuse (e.g. on tx failure or drop).
    ///
    /// Only rewinds the atomic counter if this was the most recently acquired
    /// nonce (i.e. `nonce_val == next_nonce - 1`). This prevents gaps in the
    /// nonce sequence without requiring a full resync. Also removes the nonce
    /// from the pending map if it was tracked.
    pub fn releaseNonce(self: *HftNonceManager, nonce_val: u64) void {
        // Attempt to rewind: only succeeds if no other nonce was acquired since.
        _ = self.next_nonce.cmpxchgStrong(nonce_val + 1, nonce_val, .seq_cst, .seq_cst);

        self.spinLock();
        defer self.mutex.unlock();
        _ = self.pending.remove(nonce_val);
    }

    /// Resync with chain state by resetting to a known nonce value.
    ///
    /// Use only for error recovery. The caller should fetch the current
    /// on-chain nonce count and pass it here. Clears all pending state.
    pub fn resync(self: *HftNonceManager, on_chain_nonce: u64) void {
        self.next_nonce.store(on_chain_nonce, .seq_cst);

        self.spinLock();
        defer self.mutex.unlock();
        self.pending.clearRetainingCapacity();
    }

    /// Get count of pending (unconfirmed) transactions.
    pub fn pendingCount(self: *HftNonceManager) usize {
        self.spinLock();
        defer self.mutex.unlock();
        return self.pending.count();
    }

    /// Return the current value of next_nonce without incrementing.
    pub fn peekNextNonce(self: *HftNonceManager) u64 {
        return self.next_nonce.load(.seq_cst);
    }

    pub fn deinit(self: *HftNonceManager) void {
        self.pending.deinit();
    }
};

// ---------------------------------------------------------------------------
// Unit tests
// ---------------------------------------------------------------------------

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
    const tx_hash = [_]u8{0xAB} ** 32;

    try mgr.trackSubmission(n, tx_hash);
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

    const hash_a = [_]u8{0x01} ** 32;
    const hash_b = [_]u8{0x02} ** 32;
    const hash_c = [_]u8{0x03} ** 32;

    try mgr.trackSubmission(n0, hash_a);
    try mgr.trackSubmission(n1, hash_b);
    try mgr.trackSubmission(n2, hash_c);
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
