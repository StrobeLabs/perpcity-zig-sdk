const std = @import("std");
const nonce_mod = @import("nonce.zig");
const gas_mod = @import("gas.zig");

/// A transaction request describing what to send on-chain.
///
/// The caller builds a `TxRequest` and hands it to the pipeline, which
/// acquires a nonce and resolves gas fees.  Actual signing / sending is
/// the caller's responsibility (e.g. via `PerpCityContext`).
pub const TxRequest = struct {
    to: [20]u8,
    calldata: []const u8,
    value: u256 = 0,
    gas_limit: u64,
    urgency: gas_mod.Urgency = .normal,
};

/// Snapshot of an in-flight (submitted but unconfirmed) transaction.
pub const InFlightTx = struct {
    nonce: u64,
    tx_hash: [32]u8,
    request: TxRequest,
    submitted_at_ms: i64,
    gas_fees: gas_mod.GasFees,
};

/// Lightweight result returned after a successful submission.
pub const TxResult = struct {
    tx_hash: [32]u8,
    nonce: u64,
};

/// A transaction that has been prepared (nonce acquired, gas resolved)
/// but not yet signed and sent.
pub const PreparedTx = struct {
    nonce: u64,
    gas_limit: u64,
    gas_fees: gas_mod.GasFees,
    request: TxRequest,
};

/// Parameters for bumping the gas on a stuck transaction.
pub const BumpParams = struct {
    nonce: u64,
    gas_limit: u64,
    new_max_priority_fee: u64,
    new_max_fee: u64,
    original_tx_hash: [32]u8,
};

/// Configuration for the transaction pipeline.
pub const TxPipelineConfig = struct {
    /// Maximum number of in-flight transactions before `prepare` returns
    /// `error.TooManyInFlight`.
    max_in_flight: usize = 16,
    /// A transaction is considered "stuck" if it has been in-flight for
    /// at least this many milliseconds without confirmation.
    stuck_timeout_ms: i64 = 30_000,
};

pub const TxPipelineError = error{
    TooManyInFlight,
    GasPriceUnavailable,
    OutOfMemory,
};

/// High-throughput transaction pipeline.
///
/// Combines an `HftNonceManager` (lock-free nonce acquisition) with a
/// `GasCache` (cached EIP-1559 fee resolution) to prepare transactions
/// for submission without any RPC calls on the hot path.
///
/// The pipeline tracks in-flight transactions, detects stuck ones, and
/// supports gas-bump re-submissions.  Actual transaction signing and
/// sending are performed by the caller.
///
/// Thread-safety: multiple bot threads may drive the same pipeline
/// concurrently. The `in_flight` map is non-atomic shared mutable state, so
/// every access to it is serialized behind `mutex` (a `std.Io.Mutex`, the same
/// pattern as `nonce.HftNonceManager` and `gas.GasCache`).
///
/// Lock-ordering / deadlock avoidance: the pipeline composes two other
/// independently-locked structures (`nonce_mgr`, `gas_cache`). Each structure
/// guards only its own state, and a pipeline method never holds `mutex` while
/// acquiring another structure's mutex -- it copies the values it needs out
/// from under `mutex`, releases it, and only then crosses into `nonce_mgr` /
/// `gas_cache`. The single subtlety is `prepare`, which holds `mutex` across
/// the capacity check and `nonce_mgr.acquireNonce()`; that call is lock-free
/// (an atomic fetch-add that touches no mutex), so no nested mutex is ever
/// held and the check-and-acquire is atomic without risking deadlock.
pub const TxPipeline = struct {
    nonce_mgr: *nonce_mod.HftNonceManager,
    gas_cache: *gas_mod.GasCache,
    config: TxPipelineConfig,

    /// In-flight transactions indexed by tx hash.
    in_flight: std.AutoHashMap([32]u8, InFlightTx),
    allocator: std.mem.Allocator,

    /// Protects `in_flight`. `std.Io.Mutex` is a futex-based blocking mutex
    /// (atomic fast path, OS futex wait only under contention). See the
    /// struct-level doc comment for the lock-ordering rules.
    mutex: std.Io.Mutex,

    /// `Io` handle backing the mutex. `global_single_threaded` still issues a
    /// real OS futex wait under contention, so cross-thread locking is correct
    /// for the default multi-threaded build. Same as `nonce.HftNonceManager`.
    io: std.Io,

    /// Create a new pipeline backed by the given nonce manager and gas cache.
    pub fn init(
        allocator: std.mem.Allocator,
        nonce_mgr: *nonce_mod.HftNonceManager,
        gas_cache: *gas_mod.GasCache,
        config: TxPipelineConfig,
    ) TxPipeline {
        return .{
            .nonce_mgr = nonce_mgr,
            .gas_cache = gas_cache,
            .config = config,
            .in_flight = std.AutoHashMap([32]u8, InFlightTx).init(allocator),
            .allocator = allocator,
            .mutex = .init,
            .io = std.Io.Threaded.global_single_threaded.io(),
        };
    }

    /// Acquire the mutex guarding `in_flight`.
    fn lock(self: *TxPipeline) void {
        self.mutex.lockUncancelable(self.io);
    }

    /// Release the mutex guarding `in_flight`.
    fn unlock(self: *TxPipeline) void {
        self.mutex.unlock(self.io);
    }

    /// Prepare a transaction for submission.
    ///
    /// Acquires a nonce from the nonce manager and resolves gas fees from
    /// the gas cache.  Returns a `PreparedTx` that the caller can use to
    /// sign and send the transaction.
    ///
    /// Errors:
    ///   - `TooManyInFlight` when the in-flight count has reached the
    ///     configured maximum.
    ///   - `GasPriceUnavailable` when the gas cache is empty or stale.
    pub fn prepare(self: *TxPipeline, request: TxRequest, now_ms: i64) TxPipelineError!PreparedTx {
        // Capacity check and nonce acquire are done under `mutex` so they are
        // atomic w.r.t. concurrent `prepare`/`recordSubmission` calls (closes
        // the check-then-acquire TOCTOU). `acquireNonce` is a lock-free atomic
        // fetch-add, so holding `mutex` across it acquires no second mutex.
        self.lock();
        if (self.in_flight.count() >= self.config.max_in_flight) {
            self.unlock();
            return error.TooManyInFlight;
        }
        const acquired_nonce = self.nonce_mgr.acquireNonce();
        self.unlock();

        // Gas resolution crosses into `gas_cache` (its own mutex); do it after
        // releasing `mutex` so no two structure mutexes are ever nested.
        const gas_fees = self.gas_cache.feesForUrgency(request.urgency, now_ms) orelse {
            // Release the nonce since we cannot complete preparation.
            self.nonce_mgr.releaseNonce(acquired_nonce);
            return error.GasPriceUnavailable;
        };

        return .{
            .nonce = acquired_nonce,
            .gas_limit = request.gas_limit,
            .gas_fees = gas_fees,
            .request = request,
        };
    }

    /// Record that a prepared transaction was successfully submitted.
    ///
    /// Tracks the submission in both the nonce manager (for pending-tx
    /// bookkeeping) and the pipeline's in-flight map.
    pub fn recordSubmission(self: *TxPipeline, tx_hash: [32]u8, prepared: PreparedTx, now_ms: i64) !void {
        // Track in the nonce manager first (its own mutex), then take `mutex`
        // for the in-flight insert -- the two locks are held sequentially,
        // never nested.
        try self.nonce_mgr.trackSubmission(prepared.nonce, tx_hash);
        self.lock();
        defer self.unlock();
        try self.in_flight.put(tx_hash, .{
            .nonce = prepared.nonce,
            .tx_hash = tx_hash,
            .request = prepared.request,
            .submitted_at_ms = now_ms,
            .gas_fees = prepared.gas_fees,
        });
    }

    /// Record that a transaction was confirmed on-chain.
    ///
    /// Removes the transaction from the in-flight map and confirms the
    /// nonce in the nonce manager (removing it from pending).
    pub fn confirmTx(self: *TxPipeline, tx_hash: [32]u8) void {
        // Remove under `mutex` and copy out the nonce, then cross into the
        // nonce manager without holding `mutex`.
        self.lock();
        const removed = self.in_flight.fetchRemove(tx_hash);
        self.unlock();
        if (removed) |kv| {
            self.nonce_mgr.confirmNonce(kv.value.nonce);
        }
    }

    /// Record that a transaction failed (e.g. reverted, dropped).
    ///
    /// Removes the transaction from the in-flight map and releases the
    /// nonce for potential reuse.
    pub fn failTx(self: *TxPipeline, tx_hash: [32]u8) void {
        self.lock();
        const removed = self.in_flight.fetchRemove(tx_hash);
        self.unlock();
        if (removed) |kv| {
            self.nonce_mgr.releaseNonce(kv.value.nonce);
        }
    }

    /// Return the tx hashes of transactions that have been in-flight
    /// longer than `config.stuck_timeout_ms`.
    ///
    /// The caller owns the returned slice and must free it with
    /// `self.allocator`.
    pub fn getStuckTxs(self: *TxPipeline, now_ms: i64) ![][32]u8 {
        var stuck: std.ArrayList([32]u8) = .empty;
        errdefer stuck.deinit(self.allocator);
        // Hold `mutex` for the whole scan: it both prevents a data race on the
        // map and keeps the iterator from being invalidated by a concurrent
        // insert/remove. Allocation happens under the lock but touches no other
        // guarded structure, so there is no lock-ordering hazard.
        self.lock();
        defer self.unlock();
        var it = self.in_flight.iterator();
        while (it.next()) |entry| {
            if ((now_ms - entry.value_ptr.submitted_at_ms) >= self.config.stuck_timeout_ms) {
                try stuck.append(self.allocator, entry.key_ptr.*);
            }
        }
        return stuck.toOwnedSlice(self.allocator);
    }

    /// Prepare a gas bump for a stuck transaction.
    ///
    /// Multiplies both `max_priority_fee` and `max_fee_per_gas` from the
    /// original submission by the given `multiplier`.  Returns `null` if
    /// the tx hash is not found in the in-flight map.  The multiplications
    /// saturate so an aggressive `multiplier` cannot panic in Safe builds.
    pub fn prepareBump(self: *TxPipeline, tx_hash: [32]u8, multiplier: u64) ?BumpParams {
        self.lock();
        const inflight = self.in_flight.get(tx_hash);
        self.unlock();
        const tx = inflight orelse return null;
        return .{
            .nonce = tx.nonce,
            .gas_limit = tx.request.gas_limit,
            .new_max_priority_fee = tx.gas_fees.max_priority_fee *| multiplier,
            .new_max_fee = tx.gas_fees.max_fee_per_gas *| multiplier,
            .original_tx_hash = tx_hash,
        };
    }

    /// Number of transactions currently in-flight.
    pub fn inFlightCount(self: *TxPipeline) usize {
        self.lock();
        defer self.unlock();
        return self.in_flight.count();
    }

    pub fn deinit(self: *TxPipeline) void {
        self.in_flight.deinit();
    }
};
