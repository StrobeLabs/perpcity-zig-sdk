//! Pre-trade sizing helpers: derive a signed perp delta from margin/leverage,
//! and align a price range to the pool's tick spacing. Pure math, no eth
//! dependency -- usable off-chain for order construction and risk checks.

const std = @import("std");
const constants = @import("constants.zig");
const conversions = @import("conversions.zig");

pub const SizingError = error{
    MarginMustBePositive,
    LeverageMustBePositive,
    PriceMustBePositive,
    AmountTooLarge,
    InvalidTickSpacing,
    TickBelowMin,
    TickAboveMax,
    RangeTooNarrow,
};

/// Derive the signed perp delta (currency0 amount, 1e6-scaled) required to open
/// a position of `margin` USDC at `leverage`, given the current `price`.
/// A positive result is a long; negative is a short.
///
/// Mirrors the TS SDK `derivePerpDelta`: `perpSize = margin * leverage / price`,
/// with each input scaled to 1e6 fixed-point and integer-truncated at each step
/// so the result matches the on-chain accounting exactly.
pub fn derivePerpDelta(margin: f64, leverage: f64, price: f64, is_long: bool) SizingError!i256 {
    if (margin <= 0.0) return error.MarginMustBePositive;
    if (leverage <= 0.0) return error.LeverageMustBePositive;
    if (price <= 0.0) return error.PriceMustBePositive;

    // Each is floor(x * 1e6); all inputs are validated positive above.
    const margin_scaled: i256 = conversions.scale6Decimals(margin) catch return error.AmountTooLarge;
    const leverage_scaled: i256 = conversions.scale6Decimals(leverage) catch return error.AmountTooLarge;
    const price_scaled: i256 = conversions.scale6Decimals(price) catch return error.AmountTooLarge;

    // notional = margin * leverage / 1e6 ; perpSize = notional * 1e6 / price.
    // @divTrunc truncates toward zero, matching bigint division for positives.
    const notional = @divTrunc(margin_scaled * leverage_scaled, 1_000_000);
    const perp_size = @divTrunc(notional * 1_000_000, price_scaled);
    return if (is_long) perp_size else -perp_size;
}

pub const AlignedTicks = struct {
    lower: i32,
    upper: i32,
};

/// Align a `[price_lower, price_upper]` range to `tick_spacing`, widening
/// outward (lower rounds down, upper rounds up) so the resulting ticks are valid
/// pool ticks that fully contain the requested range. Mirrors the TS SDK
/// `calculateAlignedTicks`.
pub fn calculateAlignedTicks(
    price_lower: f64,
    price_upper: f64,
    tick_spacing: i32,
) SizingError!AlignedTicks {
    if (tick_spacing <= 0) return error.InvalidTickSpacing;

    const tick_lower = conversions.priceToTick(price_lower, true) catch return error.PriceMustBePositive;
    const tick_upper = conversions.priceToTick(price_upper, false) catch return error.PriceMustBePositive;

    // Round onto the tick-spacing grid: lower toward -inf, upper toward +inf.
    // @divFloor rounds toward negative infinity; ceil(a/b) for b > 0 is
    // -@divFloor(-a, b).
    const aligned_lower = @divFloor(tick_lower, tick_spacing) * tick_spacing;
    const aligned_upper = (-@divFloor(-tick_upper, tick_spacing)) * tick_spacing;

    if (aligned_lower < constants.MIN_TICK) return error.TickBelowMin;
    if (aligned_upper > constants.MAX_TICK) return error.TickAboveMax;
    if (aligned_lower == aligned_upper) return error.RangeTooNarrow;

    return .{ .lower = aligned_lower, .upper = aligned_upper };
}
