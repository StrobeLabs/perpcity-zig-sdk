const std = @import("std");

/// High-performance local nonce manager for HFT bots.
///
/// Avoids calling `eth_getTransactionCount` on every transaction by fetching
/// the nonce once at startup and managing it locally. Nonce acquisition is
/// lock-free (atomic fetch-add); only the pending-transaction bookkeeping
/// requires a mutex.
///
/// Thread-safety: `acquireNonce` and the pending-map operations
/// (`trackSubmission`/`confirmNonce`/`releaseNonce`/`resync`/`pendingCount`)
/// are safe to call concurrently from multiple threads.
pub const HftNonceManager = struct {
    /// Next nonce to use (atomic).
    next_nonce: std.atomic.Value(u64),

    /// Pending (unconfirmed) transactions tracked by nonce.
    pending: std.AutoHashMap(u64, PendingTx),

    /// Protects the `pending` map. `std.Io.Mutex` is a futex-based blocking
    /// mutex: an atomic fast path, falling back to an OS futex wait/wake only
    /// under contention. Zig 0.16 moved synchronization onto `std.Io`, so the
    /// contended path needs an `Io` handle (below).
    mutex: std.Io.Mutex,

    /// `Io` handle backing the mutex. `global_single_threaded` refers only to
    /// the absence of an async worker pool -- its `futexWaitUncancelable` still
    /// issues a real OS futex wait (it routes to `std.Thread.futexWaitUncancelable`),
    /// so cross-thread locking is correct for the default multi-threaded build.
    /// A `-fsingle-threaded` build has no contending threads, so only the atomic
    /// fast path is ever taken. Equivalent to `eth.runtime.blockingIo()`.
    io: std.Io,

    pub const PendingTx = struct {
        tx_hash: [32]u8,
        nonce: u64,
        submitted_at_ms: i64,
    };

    /// Acquire the mutex guarding `pending`.
    fn lock(self: *HftNonceManager) void {
        self.mutex.lockUncancelable(self.io);
    }

    /// Release the mutex guarding `pending`.
    fn unlock(self: *HftNonceManager) void {
        self.mutex.unlock(self.io);
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
            .mutex = .init,
            .io = std.Io.Threaded.global_single_threaded.io(),
        };
    }

    /// Acquire the next nonce without any RPC call. Lock-free via atomic
    /// fetch-add -- safe for concurrent use from multiple threads.
    ///
    /// The counter is used purely to hand out unique, sequential nonces, so all
    /// of its operations use `.monotonic`: they need atomic uniqueness, not
    /// ordering against other memory (the `pending` map has its own mutex).
    pub fn acquireNonce(self: *HftNonceManager) u64 {
        return self.next_nonce.fetchAdd(1, .monotonic);
    }

    /// Track a submitted transaction for receipt monitoring.
    pub fn trackSubmission(self: *HftNonceManager, nonce_val: u64, tx_hash: [32]u8) !void {
        self.lock();
        defer self.unlock();
        try self.pending.put(nonce_val, .{
            .tx_hash = tx_hash,
            .nonce = nonce_val,
            .submitted_at_ms = 0, // Caller tracks timestamps externally.
        });
    }

    /// Mark a nonce as confirmed (remove from pending).
    pub fn confirmNonce(self: *HftNonceManager, nonce_val: u64) void {
        self.lock();
        defer self.unlock();
        _ = self.pending.remove(nonce_val);
    }

    /// Release a nonce (e.g. on tx failure or drop).
    ///
    /// Rewinds the atomic counter only if `nonce_val` was the most recently
    /// acquired nonce (`nonce_val == next_nonce - 1`); otherwise the counter is
    /// left unchanged.
    ///
    /// NOTE: releasing a *middle* nonce therefore leaves a gap in the sequence.
    /// Because EVM requires strictly sequential nonces, any already-submitted
    /// higher-nonce transaction will stall on-chain until that gap is filled, so
    /// the caller must `resync` (or otherwise refill the gap) after a middle
    /// release. A gap-filling free-list is intentionally not implemented here.
    /// Also removes the nonce from the pending map if it was tracked.
    pub fn releaseNonce(self: *HftNonceManager, nonce_val: u64) void {
        // Attempt to rewind: only succeeds if no other nonce was acquired since.
        _ = self.next_nonce.cmpxchgStrong(nonce_val + 1, nonce_val, .monotonic, .monotonic);

        self.lock();
        defer self.unlock();
        _ = self.pending.remove(nonce_val);
    }

    /// Resync with chain state by resetting to a known nonce value.
    ///
    /// Use only for error recovery. The caller should fetch the current
    /// on-chain nonce count and pass it here. Clears all pending state.
    pub fn resync(self: *HftNonceManager, on_chain_nonce: u64) void {
        self.next_nonce.store(on_chain_nonce, .monotonic);

        self.lock();
        defer self.unlock();
        self.pending.clearRetainingCapacity();
    }

    /// Get count of pending (unconfirmed) transactions.
    pub fn pendingCount(self: *HftNonceManager) usize {
        self.lock();
        defer self.unlock();
        return self.pending.count();
    }

    /// Return the current value of next_nonce without incrementing.
    pub fn peekNextNonce(self: *HftNonceManager) u64 {
        return self.next_nonce.load(.monotonic);
    }

    pub fn deinit(self: *HftNonceManager) void {
        self.pending.deinit();
    }
};
