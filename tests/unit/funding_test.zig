const std = @import("std");
const sdk = @import("perpcity_sdk");
const funding = sdk.funding;
const constants = sdk.constants;

// Q96 as a signed value; a per-second X96 rate of exactly Q96 represents 1.0/sec.
const Q96_I: i256 = @intCast(constants.Q96);

// =============================================================================
// fundingPerSecondX96ToRatePerMinute
// =============================================================================

test "perMinute - Q96/sec -> 60 per minute" {
    try std.testing.expectApproxEqAbs(@as(f64, 60.0), try funding.fundingPerSecondX96ToRatePerMinute(Q96_I), 1e-9);
}

test "perMinute - negative rate is negated" {
    try std.testing.expectApproxEqAbs(@as(f64, -60.0), try funding.fundingPerSecondX96ToRatePerMinute(-Q96_I), 1e-9);
}

test "perMinute - half of Q96/sec -> 30 per minute" {
    try std.testing.expectApproxEqAbs(@as(f64, 30.0), try funding.fundingPerSecondX96ToRatePerMinute(@divTrunc(Q96_I, 2)), 1e-9);
}

test "perMinute - zero is zero" {
    try std.testing.expectEqual(@as(f64, 0.0), try funding.fundingPerSecondX96ToRatePerMinute(0));
}

// =============================================================================
// fundingPerSecondX96ToRatePerDay
// =============================================================================

test "perDay - Q96/sec -> 86400 per day" {
    try std.testing.expectApproxEqAbs(@as(f64, 86_400.0), try funding.fundingPerSecondX96ToRatePerDay(Q96_I), 1e-6);
}

test "perDay - negative rate is negated" {
    try std.testing.expectApproxEqAbs(@as(f64, -86_400.0), try funding.fundingPerSecondX96ToRatePerDay(-Q96_I), 1e-6);
}

// =============================================================================
// fundingDiffX96ToRatePerPeriod
// =============================================================================

test "perPeriod - diff Q96 over 1s, period 60s -> 60" {
    try std.testing.expectApproxEqAbs(@as(f64, 60.0), try funding.fundingDiffX96ToRatePerPeriod(Q96_I, 1, 60), 1e-9);
}

test "perPeriod - diff Q96 over 60s, period 60s -> 1" {
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), try funding.fundingDiffX96ToRatePerPeriod(Q96_I, 60, 60), 1e-9);
}

test "perPeriod - zero interval is rejected" {
    try std.testing.expectError(error.IntervalMustBePositive, funding.fundingDiffX96ToRatePerPeriod(Q96_I, 0, 60));
}

// =============================================================================
// overflow guard
// =============================================================================

test "scaled result that overflows i128 returns ValueTooLarge instead of panicking" {
    const big: i256 = try std.math.powi(i256, 10, 45);
    try std.testing.expectError(error.ValueTooLarge, funding.fundingPerSecondX96ToRatePerDay(big));
}

test "intermediate multiply overflow returns ValueTooLarge instead of trapping" {
    // maxInt(i256) * SECONDS_PER_DAY overflows the i256 multiply itself; the
    // checked multiply must surface an error rather than trap.
    try std.testing.expectError(error.ValueTooLarge, funding.fundingPerSecondX96ToRatePerDay(std.math.maxInt(i256)));
    try std.testing.expectError(error.ValueTooLarge, funding.fundingDiffX96ToRatePerPeriod(std.math.maxInt(i256), 1, 60));
}
