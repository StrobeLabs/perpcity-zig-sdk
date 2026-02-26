const std = @import("std");
const sdk = @import("perpcity_sdk");
const TxPipeline = sdk.tx_pipeline.TxPipeline;
const TxPipelineConfig = sdk.tx_pipeline.TxPipelineConfig;
const TxRequest = sdk.tx_pipeline.TxRequest;
const PreparedTx = sdk.tx_pipeline.PreparedTx;
const BumpParams = sdk.tx_pipeline.BumpParams;
const HftNonceManager = sdk.nonce.HftNonceManager;
const GasCache = sdk.gas.GasCache;
const GasFees = sdk.gas.GasFees;
const Urgency = sdk.gas.Urgency;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn makeRequest(gas_limit: u64, urgency: Urgency) TxRequest {
    return .{
        .to = [_]u8{0xAA} ** 20,
        .calldata = &[_]u8{},
        .gas_limit = gas_limit,
        .urgency = urgency,
    };
}

fn setupPipeline(
    allocator: std.mem.Allocator,
    nonce_mgr: *HftNonceManager,
    gas_cache: *GasCache,
    config: TxPipelineConfig,
) TxPipeline {
    return TxPipeline.init(allocator, nonce_mgr, gas_cache, config);
}

// =============================================================================
// prepare() acquires nonce and gets gas fees
// =============================================================================

test "prepare - acquires nonce and resolves gas fees" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 10);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000, .default_priority_fee = 1_000_000_000 });
    gas_cache.updateFromBlock(50_000_000_000, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(500_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);

    // Nonce should be acquired (starting at 10)
    try std.testing.expectEqual(@as(u64, 10), prepared.nonce);
    try std.testing.expectEqual(@as(u64, 500_000), prepared.gas_limit);

    // Gas fees should be for normal urgency: maxFee = 2*base + priority
    try std.testing.expectEqual(@as(u64, 50_000_000_000), prepared.gas_fees.base_fee);
    try std.testing.expectEqual(@as(u64, 1_000_000_000), prepared.gas_fees.max_priority_fee);
    try std.testing.expectEqual(@as(u64, 2 * 50_000_000_000 + 1_000_000_000), prepared.gas_fees.max_fee_per_gas);

    // Next nonce should have advanced
    try std.testing.expectEqual(@as(u64, 11), nonce_mgr.peekNextNonce());
}

test "prepare - uses urgency level for gas fees" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000, .default_priority_fee = 1_000_000_000 });
    gas_cache.updateFromBlock(25_000_000_000, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    // High urgency: maxFee = 3*base + 2*priority
    const request = makeRequest(400_000, .high);
    const prepared = try pipeline.prepare(request, 2000);

    try std.testing.expectEqual(@as(u64, 2 * 1_000_000_000), prepared.gas_fees.max_priority_fee);
    try std.testing.expectEqual(@as(u64, 3 * 25_000_000_000 + 2 * 1_000_000_000), prepared.gas_fees.max_fee_per_gas);
}

// =============================================================================
// prepare() returns error when max in-flight exceeded
// =============================================================================

test "prepare - returns TooManyInFlight when limit reached" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{
        .max_in_flight = 2,
    });
    defer pipeline.deinit();

    const request = makeRequest(100_000, .normal);

    // Submit 2 transactions to fill up the limit
    const p1 = try pipeline.prepare(request, 2000);
    const hash1 = [_]u8{0x01} ** 32;
    try pipeline.recordSubmission(hash1, p1, 2000);

    const p2 = try pipeline.prepare(request, 2000);
    const hash2 = [_]u8{0x02} ** 32;
    try pipeline.recordSubmission(hash2, p2, 2000);

    // Third should fail
    const result = pipeline.prepare(request, 2000);
    try std.testing.expectError(error.TooManyInFlight, result);
}

// =============================================================================
// prepare() returns error when gas cache empty
// =============================================================================

test "prepare - returns GasPriceUnavailable when gas cache is empty" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    // Do NOT call updateFromBlock -- cache is empty

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(100_000, .normal);
    const result = pipeline.prepare(request, 1000);
    try std.testing.expectError(error.GasPriceUnavailable, result);
}

test "prepare - returns GasPriceUnavailable when gas cache is stale" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 1000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    // now_ms = 3000 > 1000 + 1000 TTL => stale
    const request = makeRequest(100_000, .normal);
    const result = pipeline.prepare(request, 3000);
    try std.testing.expectError(error.GasPriceUnavailable, result);
}

test "prepare - releases nonce on GasPriceUnavailable" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 5);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    // Empty cache -- will cause GasPriceUnavailable

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(100_000, .normal);
    const result = pipeline.prepare(request, 1000);
    try std.testing.expectError(error.GasPriceUnavailable, result);

    // Nonce should have been released (rewound back to 5)
    try std.testing.expectEqual(@as(u64, 5), nonce_mgr.peekNextNonce());
}

// =============================================================================
// recordSubmission() tracks the tx
// =============================================================================

test "recordSubmission - tracks transaction in in-flight map" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(300_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    const tx_hash = [_]u8{0xAB} ** 32;

    try pipeline.recordSubmission(tx_hash, prepared, 2000);

    try std.testing.expectEqual(@as(usize, 1), pipeline.inFlightCount());

    // Verify the in-flight entry
    const inflight = pipeline.in_flight.get(tx_hash).?;
    try std.testing.expectEqual(@as(u64, 0), inflight.nonce);
    try std.testing.expectEqual(@as(i64, 2000), inflight.submitted_at_ms);
    try std.testing.expectEqual(@as(u64, 300_000), inflight.request.gas_limit);
}

test "recordSubmission - tracks multiple transactions" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);

    const p1 = try pipeline.prepare(request, 2000);
    try pipeline.recordSubmission([_]u8{0x01} ** 32, p1, 2000);

    const p2 = try pipeline.prepare(request, 2000);
    try pipeline.recordSubmission([_]u8{0x02} ** 32, p2, 2100);

    const p3 = try pipeline.prepare(request, 2000);
    try pipeline.recordSubmission([_]u8{0x03} ** 32, p3, 2200);

    try std.testing.expectEqual(@as(usize, 3), pipeline.inFlightCount());
}

// =============================================================================
// confirmTx() removes from in-flight and confirms nonce
// =============================================================================

test "confirmTx - removes from in-flight and confirms nonce" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    const tx_hash = [_]u8{0xAA} ** 32;

    try pipeline.recordSubmission(tx_hash, prepared, 2000);
    try std.testing.expectEqual(@as(usize, 1), pipeline.inFlightCount());
    try std.testing.expectEqual(@as(usize, 1), nonce_mgr.pendingCount());

    pipeline.confirmTx(tx_hash);

    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
    try std.testing.expectEqual(@as(usize, 0), nonce_mgr.pendingCount());
}

test "confirmTx - no-op for unknown tx hash" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    // Confirming a non-existent hash should be safe
    pipeline.confirmTx([_]u8{0xFF} ** 32);
    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
}

// =============================================================================
// failTx() removes from in-flight and releases nonce
// =============================================================================

test "failTx - removes from in-flight and releases nonce" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    const tx_hash = [_]u8{0xBB} ** 32;

    try pipeline.recordSubmission(tx_hash, prepared, 2000);
    try std.testing.expectEqual(@as(usize, 1), pipeline.inFlightCount());
    try std.testing.expectEqual(@as(usize, 1), nonce_mgr.pendingCount());

    pipeline.failTx(tx_hash);

    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
    try std.testing.expectEqual(@as(usize, 0), nonce_mgr.pendingCount());
}

test "failTx - releases nonce so it can be reused" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    const tx_hash = [_]u8{0xCC} ** 32;

    try pipeline.recordSubmission(tx_hash, prepared, 2000);

    // Nonce 0 was acquired; next would be 1
    try std.testing.expectEqual(@as(u64, 1), nonce_mgr.peekNextNonce());

    pipeline.failTx(tx_hash);

    // releaseNonce should rewind since nonce 0 was the last acquired
    try std.testing.expectEqual(@as(u64, 0), nonce_mgr.peekNextNonce());
}

test "failTx - no-op for unknown tx hash" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    // Failing a non-existent hash should be safe
    pipeline.failTx([_]u8{0xFF} ** 32);
    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
}

// =============================================================================
// getStuckTxs() identifies old transactions
// =============================================================================

test "getStuckTxs - returns empty when no transactions are stuck" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 50000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{
        .stuck_timeout_ms = 30_000,
    });
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    try pipeline.recordSubmission([_]u8{0x01} ** 32, prepared, 2000);

    // Check at 10_000ms -- not stuck yet (only 8s elapsed, timeout is 30s)
    const stuck = try pipeline.getStuckTxs(10_000);
    defer std.testing.allocator.free(stuck);

    try std.testing.expectEqual(@as(usize, 0), stuck.len);
}

test "getStuckTxs - identifies transactions past timeout" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 100_000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{
        .stuck_timeout_ms = 5_000,
    });
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);

    // Submit at t=1000
    const p1 = try pipeline.prepare(request, 2000);
    try pipeline.recordSubmission([_]u8{0x01} ** 32, p1, 1000);

    // Submit at t=4000
    const p2 = try pipeline.prepare(request, 4500);
    try pipeline.recordSubmission([_]u8{0x02} ** 32, p2, 4000);

    // At t=6000: first tx is stuck (6000-1000=5000 >= 5000), second is not (6000-4000=2000 < 5000)
    const stuck = try pipeline.getStuckTxs(6000);
    defer std.testing.allocator.free(stuck);

    try std.testing.expectEqual(@as(usize, 1), stuck.len);
    try std.testing.expectEqual([_]u8{0x01} ** 32, stuck[0]);
}

test "getStuckTxs - returns empty when no in-flight transactions" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const stuck = try pipeline.getStuckTxs(100_000);
    defer std.testing.allocator.free(stuck);

    try std.testing.expectEqual(@as(usize, 0), stuck.len);
}

test "getStuckTxs - exact boundary is considered stuck" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 100_000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{
        .stuck_timeout_ms = 5_000,
    });
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);
    const p1 = try pipeline.prepare(request, 2000);
    try pipeline.recordSubmission([_]u8{0x01} ** 32, p1, 1000);

    // Exactly at boundary: 6000 - 1000 = 5000 >= 5000
    const stuck = try pipeline.getStuckTxs(6000);
    defer std.testing.allocator.free(stuck);

    try std.testing.expectEqual(@as(usize, 1), stuck.len);
}

// =============================================================================
// prepareBump() returns multiplied gas fees
// =============================================================================

test "prepareBump - returns multiplied gas fees for in-flight tx" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000, .default_priority_fee = 1_000_000_000 });
    gas_cache.updateFromBlock(50_000_000_000, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(500_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    const tx_hash = [_]u8{0xDD} ** 32;
    try pipeline.recordSubmission(tx_hash, prepared, 2000);

    const bump = pipeline.prepareBump(tx_hash, 2).?;

    try std.testing.expectEqual(@as(u64, 0), bump.nonce);
    try std.testing.expectEqual(@as(u64, 500_000), bump.gas_limit);
    // Original priority fee = 1 gwei, multiplied by 2 = 2 gwei
    try std.testing.expectEqual(@as(u64, 1_000_000_000 * 2), bump.new_max_priority_fee);
    // Original max fee = 2*50gwei + 1gwei = 101 gwei, multiplied by 2 = 202 gwei
    try std.testing.expectEqual(@as(u64, (2 * 50_000_000_000 + 1_000_000_000) * 2), bump.new_max_fee);
    try std.testing.expectEqual(tx_hash, bump.original_tx_hash);
}

test "prepareBump - returns null for unknown tx hash" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const bump = pipeline.prepareBump([_]u8{0xFF} ** 32, 2);
    try std.testing.expectEqual(@as(?BumpParams, null), bump);
}

test "prepareBump - preserves original nonce" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 42);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);
    const prepared = try pipeline.prepare(request, 2000);
    const tx_hash = [_]u8{0xEE} ** 32;
    try pipeline.recordSubmission(tx_hash, prepared, 2000);

    const bump = pipeline.prepareBump(tx_hash, 3).?;
    try std.testing.expectEqual(@as(u64, 42), bump.nonce);
}

// =============================================================================
// inFlightCount() tracks correctly
// =============================================================================

test "inFlightCount - starts at zero" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
}

test "inFlightCount - increments on submission and decrements on confirm" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 0);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 5000 });
    gas_cache.updateFromBlock(100, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{});
    defer pipeline.deinit();

    const request = makeRequest(200_000, .normal);

    const p1 = try pipeline.prepare(request, 2000);
    const hash1 = [_]u8{0x01} ** 32;
    try pipeline.recordSubmission(hash1, p1, 2000);
    try std.testing.expectEqual(@as(usize, 1), pipeline.inFlightCount());

    const p2 = try pipeline.prepare(request, 2000);
    const hash2 = [_]u8{0x02} ** 32;
    try pipeline.recordSubmission(hash2, p2, 2000);
    try std.testing.expectEqual(@as(usize, 2), pipeline.inFlightCount());

    pipeline.confirmTx(hash1);
    try std.testing.expectEqual(@as(usize, 1), pipeline.inFlightCount());

    pipeline.failTx(hash2);
    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
}

// =============================================================================
// End-to-end pipeline flow
// =============================================================================

test "end-to-end - prepare, submit, confirm lifecycle" {
    var nonce_mgr = HftNonceManager.init(std.testing.allocator, 100);
    defer nonce_mgr.deinit();

    var gas_cache = GasCache.init(.{ .ttl_ms = 10_000, .default_priority_fee = 1_000_000_000 });
    gas_cache.updateFromBlock(25_000_000_000, 1000);

    var pipeline = setupPipeline(std.testing.allocator, &nonce_mgr, &gas_cache, .{
        .max_in_flight = 4,
        .stuck_timeout_ms = 5_000,
    });
    defer pipeline.deinit();

    const request = makeRequest(500_000, .critical);

    // 1. Prepare
    const prepared = try pipeline.prepare(request, 2000);
    try std.testing.expectEqual(@as(u64, 100), prepared.nonce);
    // Critical: maxFee = 4*base + 5*priority
    try std.testing.expectEqual(@as(u64, 4 * 25_000_000_000 + 5 * 1_000_000_000), prepared.gas_fees.max_fee_per_gas);

    // 2. Submit
    const tx_hash = [_]u8{0xDE} ** 32;
    try pipeline.recordSubmission(tx_hash, prepared, 2000);
    try std.testing.expectEqual(@as(usize, 1), pipeline.inFlightCount());
    try std.testing.expectEqual(@as(usize, 1), nonce_mgr.pendingCount());

    // 3. Not stuck yet
    const stuck = try pipeline.getStuckTxs(3000);
    defer std.testing.allocator.free(stuck);
    try std.testing.expectEqual(@as(usize, 0), stuck.len);

    // 4. Confirm
    pipeline.confirmTx(tx_hash);
    try std.testing.expectEqual(@as(usize, 0), pipeline.inFlightCount());
    try std.testing.expectEqual(@as(usize, 0), nonce_mgr.pendingCount());
    try std.testing.expectEqual(@as(u64, 101), nonce_mgr.peekNextNonce());
}
