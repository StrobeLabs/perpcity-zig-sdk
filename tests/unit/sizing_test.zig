const std = @import("std");
const sdk = @import("perpcity_sdk");
const sizing = sdk.sizing;
const conversions = sdk.conversions;
const constants = sdk.constants;

// =============================================================================
// derivePerpDelta
//
// Oracle values match the TS SDK unit tests: perpSize = margin*leverage/price,
// all scaled by 1e6 with integer truncation.
// =============================================================================

test "derivePerpDelta - long is positive (100 margin, 2x, price 50 -> 4.0)" {
    try std.testing.expectEqual(@as(i256, 4_000_000), try sizing.derivePerpDelta(100.0, 2.0, 50.0, true));
}

test "derivePerpDelta - short is the negated long" {
    try std.testing.expectEqual(@as(i256, -4_000_000), try sizing.derivePerpDelta(100.0, 2.0, 50.0, false));
}

test "derivePerpDelta - magnitude is independent of side" {
    const long = try sizing.derivePerpDelta(100.0, 2.0, 50.0, true);
    const short = try sizing.derivePerpDelta(100.0, 2.0, 50.0, false);
    try std.testing.expectEqual(long, -short);
}

test "derivePerpDelta - (50 margin, 3x, price 10) -> 15.0" {
    try std.testing.expectEqual(@as(i256, 15_000_000), try sizing.derivePerpDelta(50.0, 3.0, 10.0, true));
}

test "derivePerpDelta - rejects non-positive margin" {
    try std.testing.expectError(error.MarginMustBePositive, sizing.derivePerpDelta(0.0, 2.0, 50.0, true));
    try std.testing.expectError(error.MarginMustBePositive, sizing.derivePerpDelta(-1.0, 2.0, 50.0, true));
}

test "derivePerpDelta - rejects non-positive leverage" {
    try std.testing.expectError(error.LeverageMustBePositive, sizing.derivePerpDelta(100.0, 0.0, 50.0, true));
}

test "derivePerpDelta - rejects non-positive price" {
    try std.testing.expectError(error.PriceMustBePositive, sizing.derivePerpDelta(100.0, 2.0, 0.0, true));
}

test "derivePerpDelta - rejects a price that truncates to zero (no div-by-zero)" {
    // 1e-7 floors to 0 once scaled by 1e6; must error rather than divide by zero.
    try std.testing.expectError(error.PriceTooSmall, sizing.derivePerpDelta(100.0, 2.0, 0.0000001, true));
}

// =============================================================================
// calculateAlignedTicks
// =============================================================================

test "calculateAlignedTicks - grid-aligned and contains the requested range" {
    const spacing: i32 = 30;
    const r = try sizing.calculateAlignedTicks(1400.0, 1600.0, spacing);

    // Both endpoints land exactly on the tick-spacing grid.
    try std.testing.expectEqual(@as(i32, 0), @rem(r.lower, spacing));
    try std.testing.expectEqual(@as(i32, 0), @rem(r.upper, spacing));
    // Strictly ordered.
    try std.testing.expect(r.lower < r.upper);
    // The aligned range fully contains the raw price ticks (widened outward).
    const raw_lower = try conversions.priceToTick(1400.0, true);
    const raw_upper = try conversions.priceToTick(1600.0, false);
    try std.testing.expect(r.lower <= raw_lower);
    try std.testing.expect(r.upper >= raw_upper);
    // Within representable bounds.
    try std.testing.expect(r.lower >= constants.MIN_TICK);
    try std.testing.expect(r.upper <= constants.MAX_TICK);
}

test "calculateAlignedTicks - spans zero for a range around price 1.0" {
    const spacing: i32 = 30;
    const r = try sizing.calculateAlignedTicks(0.5, 2.0, spacing);
    try std.testing.expectEqual(@as(i32, 0), @rem(r.lower, spacing));
    try std.testing.expectEqual(@as(i32, 0), @rem(r.upper, spacing));
    try std.testing.expect(r.lower < 0); // price 0.5 -> negative tick
    try std.testing.expect(r.upper > 0); // price 2.0 -> positive tick
}

test "calculateAlignedTicks - rejects invalid tick spacing" {
    try std.testing.expectError(error.InvalidTickSpacing, sizing.calculateAlignedTicks(1400.0, 1600.0, 0));
    try std.testing.expectError(error.InvalidTickSpacing, sizing.calculateAlignedTicks(1400.0, 1600.0, -30));
}

test "calculateAlignedTicks - rejects non-positive price" {
    try std.testing.expectError(error.PriceMustBePositive, sizing.calculateAlignedTicks(0.0, 1600.0, 30));
}

test "calculateAlignedTicks - rejects a range below MIN_TICK" {
    try std.testing.expectError(error.TickBelowMin, sizing.calculateAlignedTicks(1e-40, 1.0, 30));
}

test "calculateAlignedTicks - rejects a range above MAX_TICK" {
    try std.testing.expectError(error.TickAboveMax, sizing.calculateAlignedTicks(1.0, 1e40, 30));
}

test "calculateAlignedTicks - rejects a range that collapses after alignment" {
    // price 1.0 maps exactly to tick 0 for both floor and ceil.
    try std.testing.expectError(error.RangeTooNarrow, sizing.calculateAlignedTicks(1.0, 1.0, 30));
}

test "calculateAlignedTicks - rejects an inverted range (lower price > upper price)" {
    // aligned_lower ends up above aligned_upper; the `>=` check must catch it.
    try std.testing.expectError(error.RangeTooNarrow, sizing.calculateAlignedTicks(1600.0, 1400.0, 30));
}
