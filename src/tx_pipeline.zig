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
pub const TxPipeline = struct {
    nonce_mgr: *nonce_mod.HftNonceManager,
    gas_cache: *gas_mod.GasCache,
    config: TxPipelineConfig,

    /// In-flight transactions indexed by tx hash.
    in_flight: std.AutoHashMap([32]u8, InFlightTx),
    allocator: std.mem.Allocator,

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
        };
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
        if (self.inFlightCount() >= self.config.max_in_flight)
            return error.TooManyInFlight;

        const acquired_nonce = self.nonce_mgr.acquireNonce();
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
        try self.nonce_mgr.trackSubmission(prepared.nonce, tx_hash);
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
        if (self.in_flight.get(tx_hash)) |inflight| {
            self.nonce_mgr.confirmNonce(inflight.nonce);
        }
        _ = self.in_flight.remove(tx_hash);
    }

    /// Record that a transaction failed (e.g. reverted, dropped).
    ///
    /// Removes the transaction from the in-flight map and releases the
    /// nonce for potential reuse.
    pub fn failTx(self: *TxPipeline, tx_hash: [32]u8) void {
        if (self.in_flight.get(tx_hash)) |inflight| {
            self.nonce_mgr.releaseNonce(inflight.nonce);
        }
        _ = self.in_flight.remove(tx_hash);
    }

    /// Return the tx hashes of transactions that have been in-flight
    /// longer than `config.stuck_timeout_ms`.
    ///
    /// The caller owns the returned slice and must free it with
    /// `self.allocator`.
    pub fn getStuckTxs(self: *TxPipeline, now_ms: i64) ![][32]u8 {
        var stuck: std.ArrayList([32]u8) = .empty;
        errdefer stuck.deinit(self.allocator);
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
    /// the tx hash is not found in the in-flight map.
    pub fn prepareBump(self: *TxPipeline, tx_hash: [32]u8, multiplier: u64) ?BumpParams {
        const inflight = self.in_flight.get(tx_hash) orelse return null;
        return .{
            .nonce = inflight.nonce,
            .gas_limit = inflight.request.gas_limit,
            .new_max_priority_fee = inflight.gas_fees.max_priority_fee * multiplier,
            .new_max_fee = inflight.gas_fees.max_fee_per_gas * multiplier,
            .original_tx_hash = tx_hash,
        };
    }

    /// Number of transactions currently in-flight.
    pub fn inFlightCount(self: *const TxPipeline) usize {
        return self.in_flight.count();
    }

    pub fn deinit(self: *TxPipeline) void {
        self.in_flight.deinit();
    }
};
