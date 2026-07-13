const std = @import("std");

/// Ethereum address (20 bytes).
pub const Address = [20]u8;

/// Bytes32, used for transaction hashes and salts.
pub const Bytes32 = [32]u8;

/// Zero address constant.
pub const ZERO_ADDRESS: Address = [_]u8{0} ** 20;

/// Zero bytes32 constant.
pub const ZERO_BYTES32: Bytes32 = [_]u8{0} ** 32;

/// Deployment addresses for the perpcity-contracts v0.1.0 stack.
///
/// Each perp market is a separate contract deployed by the factory; market
/// addresses are not stored here. Callers pass per-market `Perp` addresses
/// explicitly to the wrapper functions.
pub const PerpCityDeployments = struct {
    perp_factory: Address,
    module_registry: Address,
    protocol_fee_manager: Address,
    usdc: Address,
    fees_module: ?Address = null,
    margin_ratios_module: ?Address = null,
    funding_module: ?Address = null,
    pricing_module: ?Address = null,
    price_impact_module: ?Address = null,
};

/// Mirror of `struct Modules` in perpcity-contracts SharedStructs.sol.
pub const Modules = struct {
    beacon: Address,
    fees: Address,
    funding: Address,
    margin_ratios: Address,
    price_impact: Address,
    pricing: Address,
};

/// Mirror of `struct PricePair` in perpcity-contracts SharedStructs.sol.
pub const PricePair = struct {
    amm_price: u128,
    index: u128,
};

/// Module address set held by an individual Perp contract.
pub const PerpConfig = struct {
    perp: Address,
    modules: Modules,
};

/// Maker/Taker margin ratios returned by IMarginRatios v0.1.0.
/// All ratios are scaled by 1e6.
pub const MarginRatios = struct {
    init: u24,
    liq: u24,
    backstop: u24,
};

/// Bounds applied to a position role. `init` is the minimum margin ratio at
/// open time; `liq` is the liquidation threshold; `backstop` is the threshold
/// below which a backstop can take over the position.
pub const Bounds = struct {
    init_margin_ratio: f64,
    liq_margin_ratio: f64,
    backstop_margin_ratio: f64,
    max_leverage: f64,
};

/// Volume-based fees returned by IFees.fees().
pub const Fees = struct {
    creator_fee: f64,
    insurance_fee: f64,
    lp_fee: f64,
    liquidation_fee: f64,
};

pub const LiveDetails = struct {
    margin: f64,
    perp_delta: i256,
    liq_margin_ratio: u24,
    backstop_margin_ratio: u24,
};

/// Per-market metadata derived from on-chain reads.
pub const PerpData = struct {
    perp: Address,
    mark: f64,
    beacon: Address,
    taker_bounds: Bounds,
    maker_bounds: Bounds,
    fees: Fees,
};

pub const OpenInterest = struct {
    long: u128,
    short: u128,
};

pub const Capacity = struct {
    long: u128,
    short: u128,
};

pub const OpenPositionData = struct {
    perp: Address,
    position_id: u256,
    is_maker: bool,
    live_details: LiveDetails,
};

pub const PositionRawData = struct {
    perp: Address,
    position_id: u256,
    /// Packed BalanceDelta: amount0 in high 128 bits, amount1 in low 128 bits.
    delta: i256,
    margin: u128,
    liq_margin_ratio: u24,
    backstop_margin_ratio: u24,
    last_cuml_funding_x96: i256,
};

pub const UserData = struct {
    wallet_address: Address,
    usdc_balance: f64,
    open_positions: []const OpenPositionData,
};

// ---------------------------------------------------------------------------
// Additional read structs (mirror perpcity-contracts v0.1.0 view returns)
// ---------------------------------------------------------------------------

/// Funding rate for a perp, derived from `Rates.fundingPerDay` (an int88 scaled
/// by 1e18 per day). Matches the TypeScript SDK `getFundingRate`: rates are
/// surfaced as a percentage. `rate_per_day` is a percent-per-day figure and
/// `rate_per_minute` is that divided by 1440.
pub const FundingRate = struct {
    /// Funding as a percent per day (raw / 1e18 * 100).
    rate_per_day: f64,
    /// Funding as a percent per minute (rate_per_day / 1440).
    rate_per_minute: f64,
    /// Raw signed `Rates.fundingPerDay`, scaled by 1e18 per day.
    funding_per_day_raw: i256,
};

/// Maker (concentrated-liquidity) position detail from `Perp.makerDetails`.
/// Only the leading, version-stable fields (tick range + liquidity) are
/// exposed; the trailing fee/funding checkpoints are omitted.
pub const MakerDetails = struct {
    perp: Address,
    position_id: u256,
    tick_lower: i32,
    tick_upper: i32,
    liquidity: u128,
};

/// Taker position detail from `Perp.takerDetails`: the utilization-fee payment
/// checkpoints (X96 fixed-point).
pub const TakerDetails = struct {
    perp: Address,
    position_id: u256,
    last_long_util_payments_x96: u256,
    last_short_util_payments_x96: u256,
};

/// Market solvency state from `Perp.solvencyState`, used for bad-debt
/// socialization. Both fields use USDC decimals.
pub const SolvencyState = struct {
    perp: Address,
    bad_debt: u128,
    total_margin: u128,
};

/// Accrued fee balances from `Perp.feeFund`. Each field is a uint80 in USDC
/// decimals; widened to u128 for ergonomics.
pub const FeeFund = struct {
    perp: Address,
    insurance: u128,
    creator_fees: u128,
    protocol_fees: u128,
};

// ---------------------------------------------------------------------------
// Write call parameters (mirror SharedStructs.sol)
// ---------------------------------------------------------------------------

pub const CreatePerpParams = struct {
    owner: Address,
    name: []const u8,
    symbol: []const u8,
    token_uri: []const u8,
    modules: Modules,
    ema_window: u24,
    salt: Bytes32 = ZERO_BYTES32,
};

pub const OpenMakerPositionParams = struct {
    /// Margin in human units (USDC, e.g., 100.0 = 100 USDC).
    margin: f64,
    price_lower: f64,
    price_upper: f64,
    liquidity: u128,
    max_amt0_in: u256,
    max_amt1_in: u256,
};

pub const OpenTakerPositionParams = struct {
    /// Margin in human units (USDC).
    margin: f64,
    /// Signed perp amount. Positive = long, negative = short.
    perp_delta: i256,
    /// Slippage limit on the USD side of the swap.
    amt1_limit: u256,
};

pub const AdjustMakerParams = struct {
    position_id: u256,
    /// Scaled by 1e6 (USDC 6-decimals).
    margin_delta: i128,
    liquidity_delta: i128,
    amt0_limit: u256,
    amt1_limit: u256,
};

pub const AdjustTakerParams = struct {
    position_id: u256,
    /// Scaled by 1e6 (USDC 6-decimals).
    margin_delta: i128,
    perp_delta: i256,
    amt1_limit: u256,
};

pub const LiquidateParams = struct {
    position_id: u256,
    fee_recipient: Address,
};

pub const BackstopParams = struct {
    position_id: u256,
    /// Margin in scaled (1e6) units.
    margin_in: u128,
    position_recipient: Address,
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "ZERO_ADDRESS is all zeros" {
    for (ZERO_ADDRESS) |b| try std.testing.expectEqual(@as(u8, 0), b);
}

test "ZERO_BYTES32 is all zeros" {
    for (ZERO_BYTES32) |b| try std.testing.expectEqual(@as(u8, 0), b);
}

test "PerpCityDeployments optional module fields default to null" {
    const d: PerpCityDeployments = .{
        .perp_factory = ZERO_ADDRESS,
        .module_registry = ZERO_ADDRESS,
        .protocol_fee_manager = ZERO_ADDRESS,
        .usdc = ZERO_ADDRESS,
    };
    try std.testing.expectEqual(@as(?Address, null), d.fees_module);
    try std.testing.expectEqual(@as(?Address, null), d.margin_ratios_module);
    try std.testing.expectEqual(@as(?Address, null), d.funding_module);
    try std.testing.expectEqual(@as(?Address, null), d.pricing_module);
    try std.testing.expectEqual(@as(?Address, null), d.price_impact_module);
}

test "MarginRatios fields are 1e6-scaled" {
    const r: MarginRatios = .{ .init = 100_000, .liq = 50_000, .backstop = 20_000 };
    try std.testing.expectEqual(@as(u24, 100_000), r.init);
    try std.testing.expectEqual(@as(u24, 50_000), r.liq);
    try std.testing.expectEqual(@as(u24, 20_000), r.backstop);
}
