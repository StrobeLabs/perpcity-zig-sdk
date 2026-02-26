const std = @import("std");

/// Rolling window latency tracker with percentile computation.
/// Designed for HFT observability -- tracks RPC and execution latencies
/// with O(1) sample recording and O(n log n) stats computation.
pub const LatencyTracker = struct {
    pub const MAX_SAMPLES: usize = 1024;

    samples: [MAX_SAMPLES]u64 = [_]u64{0} ** MAX_SAMPLES,
    sample_count: usize = 0,
    sample_index: usize = 0,

    // Running stats
    total_requests: u64 = 0,
    total_latency_ns: u64 = 0,
    min_ns: u64 = std.math.maxInt(u64),
    max_ns: u64 = 0,

    /// Record a latency sample in nanoseconds.
    pub fn recordSample(self: *LatencyTracker, latency_ns: u64) void {
        self.samples[self.sample_index] = latency_ns;
        self.sample_index = (self.sample_index + 1) % MAX_SAMPLES;
        if (self.sample_count < MAX_SAMPLES) {
            self.sample_count += 1;
        }
        self.total_requests += 1;
        self.total_latency_ns = self.total_latency_ns +| latency_ns; // saturating add
        if (latency_ns < self.min_ns) self.min_ns = latency_ns;
        if (latency_ns > self.max_ns) self.max_ns = latency_ns;
    }

    pub const Stats = struct {
        count: u64,
        min_ns: u64,
        max_ns: u64,
        avg_ns: u64,
        p50_ns: u64,
        p95_ns: u64,
        p99_ns: u64,
    };

    /// Compute latency statistics over the rolling window.
    pub fn getStats(self: *LatencyTracker) Stats {
        if (self.sample_count == 0) {
            return .{
                .count = 0,
                .min_ns = 0,
                .max_ns = 0,
                .avg_ns = 0,
                .p50_ns = 0,
                .p95_ns = 0,
                .p99_ns = 0,
            };
        }

        // Copy and sort the samples for percentile calculation
        var sorted: [MAX_SAMPLES]u64 = undefined;
        const n = self.sample_count;
        @memcpy(sorted[0..n], self.samples[0..n]);
        std.mem.sort(u64, sorted[0..n], {}, std.sort.asc(u64));

        const avg = self.total_latency_ns / self.total_requests;

        return .{
            .count = self.total_requests,
            .min_ns = self.min_ns,
            .max_ns = self.max_ns,
            .avg_ns = avg,
            .p50_ns = sorted[n * 50 / 100],
            .p95_ns = sorted[n * 95 / 100],
            .p99_ns = sorted[n * 99 / 100],
        };
    }

    /// Reset all stats.
    pub fn reset(self: *LatencyTracker) void {
        self.* = .{};
    }

    /// Record elapsed time between two nanosecond timestamps and store
    /// the result as a sample.  The caller is responsible for obtaining
    /// the timestamps (e.g. via `std.posix.clock_gettime` or platform-
    /// specific monotonic clocks).  This keeps the module free of OS
    /// clock dependencies, which makes it fully deterministic in tests.
    ///
    /// Returns the elapsed time in nanoseconds.
    pub fn recordElapsed(self: *LatencyTracker, start_ns: i128, end_ns: i128) u64 {
        const elapsed = end_ns - start_ns;
        const elapsed_u64: u64 = @intCast(@max(0, elapsed));
        self.recordSample(elapsed_u64);
        return elapsed_u64;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "recordSample updates stats correctly" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);
    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 100), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 100), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 100), tracker.max_ns);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_count);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_index);

    tracker.recordSample(200);
    try std.testing.expectEqual(@as(u64, 2), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 300), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 100), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 200), tracker.max_ns);
    try std.testing.expectEqual(@as(usize, 2), tracker.sample_count);

    tracker.recordSample(50);
    try std.testing.expectEqual(@as(u64, 3), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 350), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 50), tracker.min_ns);
    try std.testing.expectEqual(@as(u64, 200), tracker.max_ns);
}

test "getStats returns correct percentiles" {
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

test "getStats returns zeros when no samples" {
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

test "reset clears everything" {
    var tracker: LatencyTracker = .{};

    tracker.recordSample(100);
    tracker.recordSample(200);
    tracker.recordSample(300);

    try std.testing.expectEqual(@as(u64, 3), tracker.total_requests);
    try std.testing.expect(tracker.sample_count > 0);

    tracker.reset();

    try std.testing.expectEqual(@as(u64, 0), tracker.total_requests);
    try std.testing.expectEqual(@as(u64, 0), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_count);
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_index);
    try std.testing.expectEqual(@as(u64, 0), tracker.max_ns);
    try std.testing.expectEqual(std.math.maxInt(u64), tracker.min_ns);

    // Stats should return zeros after reset
    const stats = tracker.getStats();
    try std.testing.expectEqual(@as(u64, 0), stats.count);
}

test "recordElapsed computes and stores elapsed time" {
    var tracker: LatencyTracker = .{};

    const start_ns: i128 = 1_000_000;
    const end_ns: i128 = 1_500_000;
    const elapsed = tracker.recordElapsed(start_ns, end_ns);

    try std.testing.expectEqual(@as(u64, 500_000), elapsed);
    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_count);
    try std.testing.expectEqual(@as(u64, 500_000), tracker.samples[0]);
}

test "recordElapsed clamps negative elapsed to zero" {
    var tracker: LatencyTracker = .{};

    // end < start should clamp to 0
    const elapsed = tracker.recordElapsed(2_000_000, 1_000_000);

    try std.testing.expectEqual(@as(u64, 0), elapsed);
    try std.testing.expectEqual(@as(u64, 1), tracker.total_requests);
}

test "rolling window wraps correctly after MAX_SAMPLES" {
    var tracker: LatencyTracker = .{};
    const max = LatencyTracker.MAX_SAMPLES;

    // Fill the entire buffer with value 10
    for (0..max) |_| {
        tracker.recordSample(10);
    }

    try std.testing.expectEqual(max, tracker.sample_count);
    try std.testing.expectEqual(@as(u64, max), tracker.total_requests);
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_index); // wraps to 0

    // Now add one more sample with a different value
    tracker.recordSample(999);

    // sample_count should stay at MAX_SAMPLES (window is full)
    try std.testing.expectEqual(max, tracker.sample_count);
    // total_requests should increment
    try std.testing.expectEqual(@as(u64, max + 1), tracker.total_requests);
    // The new sample overwrote index 0
    try std.testing.expectEqual(@as(u64, 999), tracker.samples[0]);
    // sample_index advanced to 1
    try std.testing.expectEqual(@as(usize, 1), tracker.sample_index);

    // Add enough to wrap fully again
    for (1..max) |_| {
        tracker.recordSample(20);
    }

    // Now the buffer should have: [999, 20, 20, ..., 20]
    // sample_index should be back to 0
    try std.testing.expectEqual(@as(usize, 0), tracker.sample_index);
    try std.testing.expectEqual(max, tracker.sample_count);
    try std.testing.expectEqual(@as(u64, 2 * max), tracker.total_requests);
}

test "getStats with single sample" {
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

test "saturating add prevents overflow on total_latency_ns" {
    var tracker: LatencyTracker = .{};

    // Record a near-max value
    tracker.recordSample(std.math.maxInt(u64) - 1);
    // Record another large value -- should saturate, not overflow
    tracker.recordSample(std.math.maxInt(u64) - 1);

    try std.testing.expectEqual(std.math.maxInt(u64), tracker.total_latency_ns);
    try std.testing.expectEqual(@as(u64, 2), tracker.total_requests);
}

test "getStats percentiles with unordered input" {
    var tracker: LatencyTracker = .{};

    // Insert samples in reverse order
    tracker.recordSample(500);
    tracker.recordSample(400);
    tracker.recordSample(300);
    tracker.recordSample(200);
    tracker.recordSample(100);

    const stats = tracker.getStats();

    // min/max from running stats
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
