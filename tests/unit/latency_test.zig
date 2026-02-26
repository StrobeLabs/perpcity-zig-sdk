const std = @import("std");
const sdk = @import("perpcity_sdk");
const LatencyTracker = sdk.latency.LatencyTracker;

// =============================================================================
// recordSample updates stats correctly
// =============================================================================

test "recordSample - first sample sets min, max, and total" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);

    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 100), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 100), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 100), tracker.max_ns);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_count);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_index);
}

test "recordSample - multiple samples update min and max correctly" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(200);
    tracker.recordSample(50);
    tracker.recordSample(500);

    try std.testing.expectEqual(@as(u64, 3), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 750), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 50), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 500), tracker.max_ns);
    try std.testing.expectEqual(@as(usize, 3), tracker.sample_count);
}

test "recordSample - saturating add prevents overflow" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(std.math.maxInt(u64) - 1);
    tracker.recordSample(std.math.maxInt(u64) - 1);

    // Should saturate at maxInt(u64), not wrap around
    try std.testing.expectEqual(std.math.maxInt(u64), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 2), tracker.total_requests);
}

test "recordSample - zero latency is valid" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(0);

    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 0), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 0), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 0), tracker.max_ns);
}

// =============================================================================
// getStats returns correct percentiles
// =============================================================================

test "getStats - returns zeros when no samples recorded" {
    var tracker: LatencyTracker = .{};
    const stats = tracker.getStats();

    try std.testing.expectEqual(@as(u64, 0), stats.count);
    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.p50_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.p95_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.p99_ns);
}

test "getStats - single sample returns that value for all percentiles" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(42);

    const stats = tracker.getStats();

    try std.testing.expectEqual(@as(u64, 1), stats.count);
    try std.testing.expectEqual(@as(u64, 42), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 42), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 42), stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 42), stats.p50_ns);
    try std.testing.expectEqual(@as(u64, 42), stats.p95_ns);
    try std.testing.expectEqual(@as(u64, 42), stats.p99_ns);
}

test "getStats - 100 sequential samples computes correct percentiles" {
    var tracker: LatencyTracker = .{};

    // Insert 100 samples: 1, 2, 3, ..., 100
    for (1..101) |i| {
        tracker.recordSample(@intCast(i));
    }

    const stats = tracker.getStats();

    try std.testing.expectEqual(@as(u64, 100), stats.count);
    try std.testing.expectEqual(@as(u64, 1), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 100), stats.max_ns);
    // avg = (1+2+...+100)/100 = 5050/100 = 50
    try std.testing.expectEqual(@as(u64, 50), stats.avg_ns);
    // p50 = sorted[100*50/100] = sorted[50] = 51
    try std.testing.expectEqual(@as(u64, 51), stats.p50_ns);
    // p95 = sorted[100*95/100] = sorted[95] = 96
    try std.testing.expectEqual(@as(u64, 96), stats.p95_ns);
    // p99 = sorted[100*99/100] = sorted[99] = 100
    try std.testing.expectEqual(@as(u64, 100), stats.p99_ns);
}

test "getStats - unordered input produces correct sorted percentiles" {
    var tracker: LatencyTracker = .{};

    // Insert in reverse order
    tracker.recordSample(500);
    tracker.recordSample(400);
    tracker.recordSample(300);
    tracker.recordSample(200);
    tracker.recordSample(100);

    const stats = tracker.getStats();

    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 500), stats.max_ns);
    // Sorted: [100, 200, 300, 400, 500]
    // p50 = sorted[5*50/100] = sorted[2] = 300
    try std.testing.expectEqual(@as(u64, 300), stats.p50_ns);
    // p95 = sorted[5*95/100] = sorted[4] = 500
    try std.testing.expectEqual(@as(u64, 500), stats.p95_ns);
    // p99 = sorted[5*99/100] = sorted[4] = 500
    try std.testing.expectEqual(@as(u64, 500), stats.p99_ns);
}

test "getStats - two samples computes correct average" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);
    tracker.recordSample(300);

    const stats = tracker.getStats();

    try std.testing.expectEqual(@as(u64, 2), stats.count);
    try std.testing.expectEqual(@as(u64, 200), stats.avg_ns);
    try std.testing.expectEqual(@as(u64, 100), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 300), stats.max_ns);
}

// =============================================================================
// reset clears everything
// =============================================================================

test "reset - clears all running stats" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);
    tracker.recordSample(200);
    tracker.recordSample(300);

    tracker.reset();

    try std.testing.expectEqual(@as(u64, 0), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 0), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_count);
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_index);
    try std.testing.expectEqual(@as(u64, 0), tracker.max_ns);
    try std.testing.expectEqual(std.math.maxInt(u64), tracker.min_ns);
}

test "reset - getStats returns zeros after reset" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);
    tracker.recordSample(200);
    tracker.reset();

    const stats = tracker.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.count);
    try std.testing.expectEqual(@as(u64, 0), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.max_ns);
    try std.testing.expectEqual(@as(u64, 0), stats.avg_ns);
}

test "reset - tracker is usable after reset" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);
    tracker.reset();
    tracker.recordSample(42);

    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 42), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 42), tracker.max_ns);

    const stats = tracker.getStats();
    try std.testing.expectEqual(@as(u64, 1), stats.count);
    try std.testing.expectEqual(@as(u64, 42), stats.avg_ns);
}

// =============================================================================
// recordElapsed computes and stores elapsed time
// =============================================================================

test "recordElapsed - computes and stores elapsed time" {
    var tracker: LatencyTracker = .{};

    const elapsed = tracker.recordElapsed(1_000_000, 1_500_000);

    try std.testing.expectEqual(@as(u64, 500_000), elapsed);
    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_count);
    try std.testing.expectEqual(@as(u64, 500_000), tracker.samples[0]);
}

test "recordElapsed - clamps negative elapsed to zero" {
    var tracker: LatencyTracker = .{};

    const elapsed = tracker.recordElapsed(2_000_000, 1_000_000);

    try std.testing.expectEqual(@as(u64, 0), elapsed);
    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
}

test "recordElapsed - elapsed is stored as the latest sample" {
    var tracker: LatencyTracker = .{};

    // Record a manual sample first
    tracker.recordSample(999);

    const elapsed = tracker.recordElapsed(100, 5100);

    try std.testing.expectEqual(@as(u64, 2), tracker.total_requests);
    // The measured sample is at index 1
    try std.testing.expectEqual(elapsed, tracker.samples[1]);
    // The manual sample is still at index 0
    try std.testing.expectEqual(@as(u64, 999), tracker.samples[0]);
}

// =============================================================================
// Rolling window wraps correctly after MAX_SAMPLES
// =============================================================================

test "rolling window - sample_index wraps to 0 after MAX_SAMPLES" {
    var tracker: LatencyTracker = .{};
    const max = LatencyTracker.MAX_SAMPLES;

    for (0..max) |_| {
        tracker.recordSample(10);
    }

    try std.testing.expectEqual(max, tracker.sample_count);
    try std.testing.expectEqual(@as(u64, max), tracker.total_requests);
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_index);
}

test "rolling window - sample_count caps at MAX_SAMPLES" {
    var tracker: LatencyTracker = .{};
    const max = LatencyTracker.MAX_SAMPLES;

    // Overfill by 100
    for (0..max + 100) |_| {
        tracker.recordSample(10);
    }

    // sample_count should not exceed MAX_SAMPLES
    try std.testing.expectEqual(max, tracker.sample_count);
    // But total_requests tracks all
    try std.testing.expectEqual(@as(u64, max + 100), tracker.total_requests);
}

test "rolling window - new samples overwrite oldest" {
    var tracker: LatencyTracker = .{};
    const max = LatencyTracker.MAX_SAMPLES;

    // Fill buffer with 10
    for (0..max) |_| {
        tracker.recordSample(10);
    }

    // Now overwrite index 0 with a new value
    tracker.recordSample(999);

    try std.testing.expectEqual(@as(u64, 999), tracker.samples[0]);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_index);
    try std.testing.expectEqual(max, tracker.sample_count);
}

test "rolling window - full wrap around restores index to 0" {
    var tracker: LatencyTracker = .{};
    const max = LatencyTracker.MAX_SAMPLES;

    // Fill completely twice
    for (0..max * 2) |_| {
        tracker.recordSample(10);
    }

    try std.testing.expectEqual(@as(usize, 0), tracker.sample_index);
    try std.testing.expectEqual(max, tracker.sample_count);
    try std.testing.expectEqual(@as(u64, max * 2), tracker.total_requests);
}

test "rolling window - stats reflect window contents after wrap" {
    var tracker: LatencyTracker = .{};
    const max = LatencyTracker.MAX_SAMPLES;

    // Fill buffer with value 10
    for (0..max) |_| {
        tracker.recordSample(10);
    }

    // Replace all with value 20
    for (0..max) |_| {
        tracker.recordSample(20);
    }

    const stats = tracker.getStats();

    // The rolling window now contains only 20s
    // p50 should be 20
    try std.testing.expectEqual(@as(u64, 20), stats.p50_ns);
    // min_ns/max_ns are running totals, so min is still 10
    try std.testing.expectEqual(@as(u64, 10), stats.min_ns);
    try std.testing.expectEqual(@as(u64, 20), stats.max_ns);
}
