//! Funding-rate conversions from X96 fixed-point accumulators to human rates.
//! Pure math, no eth dependency. Mirrors the TS SDK `funding.ts`.
//!
//! The X96 inputs are funding accumulators / per-second rates scaled by `2^96`.
//! Each conversion scales by 1e18 before dividing so that small differentials
//! are not truncated away, then narrows back to an `f64`.

const std = @import("std");
const constants = @import("constants.zig");

/// Fixed-point precision applied before the final division (1e18).
const PRECISION: i256 = 1_000_000_000_000_000_000;
const SECONDS_PER_MINUTE: i256 = 60;
const SECONDS_PER_DAY: i256 = 86_400;

pub const FundingError = error{
    IntervalMustBePositive,
    ValueTooLarge,
};

/// Convert a funding diff accumulated over `interval` seconds (X96 fixed-point,
/// signed) into the rate over `period_seconds`:
/// `rate = (diff / interval) * period`.
pub fn fundingDiffX96ToRatePerPeriod(
    funding_diff_x96: i256,
    interval: u64,
    period_seconds: u64,
) FundingError!f64 {
    if (interval == 0) return error.IntervalMustBePositive;
    const q96: i256 = @intCast(constants.Q96);
    // Checked so a large diff cannot overflow the i256 multiply and trap.
    const numerator = try checkedMul(try checkedMul(funding_diff_x96, @intCast(period_seconds)), PRECISION);
    // q96 (2^96) * interval (<= 2^64) <= 2^160, so this cannot overflow i256.
    const denominator = q96 * @as(i256, @intCast(interval));
    return scaledToF64(@divTrunc(numerator, denominator));
}

/// Convert a per-second funding rate (X96 fixed-point, signed) to a per-minute
/// rate.
pub fn fundingPerSecondX96ToRatePerMinute(funding_per_second_x96: i256) FundingError!f64 {
    const q96: i256 = @intCast(constants.Q96);
    const numerator = try checkedMul(try checkedMul(funding_per_second_x96, SECONDS_PER_MINUTE), PRECISION);
    return scaledToF64(@divTrunc(numerator, q96));
}

/// Convert a per-second funding rate (X96 fixed-point, signed) to a per-day
/// rate.
pub fn fundingPerSecondX96ToRatePerDay(funding_per_second_x96: i256) FundingError!f64 {
    const q96: i256 = @intCast(constants.Q96);
    const numerator = try checkedMul(try checkedMul(funding_per_second_x96, SECONDS_PER_DAY), PRECISION);
    return scaledToF64(@divTrunc(numerator, q96));
}

/// Multiply two `i256` values, returning `error.ValueTooLarge` on overflow
/// instead of trapping.
fn checkedMul(a: i256, b: i256) FundingError!i256 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) return error.ValueTooLarge;
    return result[0];
}

/// Convert an `i256` pre-scaled by `PRECISION` (1e18) back to an `f64`. Narrows
/// through `i128` first to avoid the LLVM aarch64 `i256 -> f64` codegen bug, and
/// returns `error.ValueTooLarge` rather than panicking if the value does not fit.
fn scaledToF64(scaled: i256) FundingError!f64 {
    if (scaled > std.math.maxInt(i128) or scaled < std.math.minInt(i128)) {
        return error.ValueTooLarge;
    }
    const narrowed: i128 = @intCast(scaled);
    return @as(f64, @floatFromInt(narrowed)) / 1e18;
}
