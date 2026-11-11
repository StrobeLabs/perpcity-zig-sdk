const std = @import("std");

/// Ethereum address (20 bytes).
pub const Address = [20]u8;

/// Bytes32, used for transaction hashes and salts.
pub const Bytes32 = [32]u8;

/// Zero address constant.
pub const ZERO_ADDRESS: Address = @splat(0);

/// Zero bytes32 constant.
pub const ZERO_BYTES32: Bytes32 = @splat(0);

/// Deployment addresses for the perpcity-contracts v1.0.0 stack.
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

/// Mirror of `struct Modules` in perpcity-contracts Structs.sol.
pub const Modules = struct {
    beacon: Address,
    fees: Address,
    funding: Address,
    margin_ratios: Address,
    price_impact: Address,
    pricing: Address,
};

/// Mirror of `struct PricePair` in perpcity-contracts Structs.sol.
pub const PricePair = struct {
    amm_price: u128,
    index: u128,
};

/// Module address set held by an individual Perp contract.
pub const PerpConfig = struct {
    perp: Address,
    modules: Modules,
};

/// Maker/Taker margin ratios returned by IMarginRatios.
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

/// Fee rates for a market, as fractions (0.001 = 0.1%).
///
/// The LP fee is dynamic on-chain: `IFees.fees` prices it from the active
/// liquidity and the gap between the spot AMM price and its EMA. `lp_fee` here
/// is the rate at the pool's current liquidity with no volatility surcharge
/// (spot taken as its own EMA), so a swap can pay more; `max_swap_fee` is the
/// module's upper bound on creator + insurance + LP combined. The protocol fee
/// is charged on top of these (`Perp.protocolFee`).
pub const Fees = struct {
    creator_fee: f64,
    insurance_fee: f64,
    lp_fee: f64,
    liquidation_fee: f64,
    max_swap_fee: f64,
};

/// Stored (unsettled) balances of a position. Margin ratios are no longer
/// stored per position; read them from `PerpData.taker_bounds` /
/// `maker_bounds`, or use `PerpCityContext.getPositionPreview` for the
/// contract's own settled equity and liquidatable / backstoppable flags.
pub const LiveDetails = struct {
    margin: f64,
    perp_delta: i256,
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
    last_cuml_funding_x96: i256,
};

pub const UserData = struct {
    wallet_address: Address,
    usdc_balance: f64,
    open_positions: []const OpenPositionData,
};

// ---------------------------------------------------------------------------
// Additional read structs (mirror perpcity-contracts v1.0.0 view returns)
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

/// Mirror of `struct MakerFunding`: a maker's range-funding checkpoints.
pub const MakerFunding = struct {
    below_x96: i256,
    within_inventory_x192: i256,
};

/// Mirror of `struct Rates`: the cached daily rates (scaled by 1e18 per day),
/// the timestamp they began applying, and the Q96 mark cached at that touch.
pub const Rates = struct {
    funding_per_day: i256,
    long_util_fee_per_day: u64,
    short_util_fee_per_day: u64,
    last_touch: u64,
    last_mark: u256,
};

/// Maker (concentrated-liquidity) position detail from `Perp.makerDetails`: the
/// stored (unsettled) range, liquidity, and settlement checkpoints. All zero
/// for a taker position.
pub const MakerDetails = struct {
    perp: Address,
    position_id: u256,
    tick_lower: i32,
    tick_upper: i32,
    liquidity: u128,
    last_lp_fee_growth_inside_x128: u256,
    last_cuml_funding: MakerFunding,
    last_funding_correction_x128: i256,
};

/// Taker position detail from `Perp.takerDetails`: the utilization checkpoints
/// (X96 fixed-point) for the side the position is on. All zero for a maker.
pub const TakerDetails = struct {
    perp: Address,
    position_id: u256,
    last_util_payments_x96: u256,
    last_reserve_util_payments_x96: u256,
};

/// Mirror of `struct PositionPreview` from `Perp.previewPosition`: a position
/// settled to the current block without storage writes, plus its risk flags.
/// Amounts use USDC decimals; `mark_price` is Q96. `settled_margin` and
/// `equity` are signed and can report a deficit.
///
/// The flags describe eligibility, not a guarantee: a liquidation can still
/// revert on physical capacity or price impact.
pub const PositionPreview = struct {
    perp: Address,
    position_id: u256,
    is_maker: bool,
    mark_price: u256,
    settled_margin: i256,
    /// Combined LP and utilization earnings credited on settlement; 0 for takers.
    pending_lp_fees: u256,
    /// Positive is owed by the position.
    pending_funding: i256,
    pending_util: u256,
    /// The reserve-directed part of `pending_util`, not an extra charge.
    pending_reserve_util: u256,
    value: u256,
    unrealized_pnl: i256,
    equity: i256,
    meets_initial_margin: bool,
    /// Whether a full-size liquidation is currently eligible.
    liquidatable: bool,
    backstoppable: bool,
    nominal_liq_fee: u256,
    payable_liq_fee: u256,
};

/// Full-book closing depth from `Perp.physicalCloseCapacity`, in perp atoms.
/// Open interest on each side must stay within it; this is the admission
/// limit, unlike the strict-band `Capacity` used for utilization fees.
pub const PhysicalCloseCapacity = struct {
    long_close: u128,
    short_close: u128,
};

/// A beacon observation from `IBeacon.index()`: the Q96 index and the block
/// timestamp (seconds) at which it was written.
pub const IndexObservation = struct {
    index: u256,
    updated_at: u64,
};

/// Accounted-TVL headroom of a market, in USDC decimals. Fresh USDC ingress
/// (opens, margin adds, donations, backstops) that would push `tvl` above
/// `cap` reverts `TvlCapExceeded`.
pub const TvlState = struct {
    tvl: u256,
    cap: u256,
};

/// An escrowed payout in a market's WithdrawalController (`claims(claimId)`).
/// `created_at` is in seconds; the claim is releasable once the controller's
/// current challenge window has elapsed since then.
pub const Claim = struct {
    original_amount: u128,
    current_amount: u128,
    recipient: Address,
    created_at: u64,
    /// `ClaimStatus`: 0 none, 1 pending, 2 completed, 3 cancelled.
    status: u8,
    paused: bool,
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
// Write call parameters (mirror Structs.sol)
// ---------------------------------------------------------------------------

/// Deadline value meaning "never expires". Every position-changing call takes
/// a `deadline` (unix seconds); the contract reverts `DeadlineExpired` once
/// `block.timestamp` is past it. Prefer a real deadline for anything that can
/// sit in a mempool.
pub const NO_DEADLINE: u64 = std.math.maxInt(u64);

/// `max_total_fee` value meaning "no cap on the swap fee".
pub const NO_FEE_CAP: u256 = std.math.maxInt(u256);

/// Mirror of `struct WithdrawalConfig`: the creator-supplied instant-payout
/// rate limit (USDC decimals) and the claim release delay (seconds, must be
/// nonzero) for a new market's WithdrawalController.
pub const WithdrawalConfig = struct {
    capacity: u128,
    refill_per_second: u128,
    challenge_window: u48,
};

pub const CreatePerpParams = struct {
    owner: Address,
    /// The market's delayed authority (should be a timelock); must be nonzero.
    governor: Address,
    modules: Modules,
    ema_window: u24,
    /// Maximum accepted beacon-observation age in seconds. The beacon must
    /// hold an observation at most this old when the market is created.
    latency: u32,
    salt: Bytes32 = ZERO_BYTES32,
    withdrawal_config: WithdrawalConfig,
};

pub const OpenMakerPositionParams = struct {
    /// Margin in human units (USDC, e.g., 100.0 = 100 USDC).
    margin: f64,
    price_lower: f64,
    price_upper: f64,
    liquidity: u128,
    max_amt0_in: u256,
    max_amt1_in: u256,
    /// Latest accepted block timestamp, in unix seconds.
    deadline: u64 = NO_DEADLINE,
};

pub const OpenTakerPositionParams = struct {
    /// Margin in human units (USDC). Swap fees are deducted from it.
    margin: f64,
    /// Signed perp amount. Positive = long, negative = short.
    perp_delta: i256,
    /// Slippage limit on the USD side of the swap.
    amt1_limit: u256,
    /// Maximum total swap fee, in USDC decimals.
    max_total_fee: u256 = NO_FEE_CAP,
    /// Latest accepted block timestamp, in unix seconds.
    deadline: u64 = NO_DEADLINE,
};

pub const AdjustMakerParams = struct {
    position_id: u256,
    /// Scaled by 1e6 (USDC 6-decimals).
    margin_delta: i128,
    liquidity_delta: i128,
    amt0_limit: u256,
    amt1_limit: u256,
    /// Latest accepted block timestamp, in unix seconds.
    deadline: u64 = NO_DEADLINE,
};

/// Atomic maker range replacement on the same position id (`moveMaker`).
pub const MoveMakerParams = struct {
    position_id: u256,
    tick_lower: i24,
    tick_upper: i24,
    /// The replacement range's final liquidity; must be nonzero.
    liquidity: u128,
    remove_amt0_min: u256,
    remove_amt1_min: u256,
    add_amt0_max: u256,
    add_amt1_max: u256,
    /// Scaled by 1e6 (USDC 6-decimals).
    margin_delta: i128 = 0,
    /// Latest accepted block timestamp, in unix seconds.
    deadline: u64 = NO_DEADLINE,
};

pub const AdjustTakerParams = struct {
    position_id: u256,
    /// Scaled by 1e6 (USDC 6-decimals).
    margin_delta: i128,
    perp_delta: i256,
    amt1_limit: u256,
    /// Maximum total swap fee, in USDC decimals.
    max_total_fee: u256 = NO_FEE_CAP,
    /// When true the adjustment may neither grow absolute exposure nor flip
    /// side. Set it on closes: a partial liquidation landing first would
    /// otherwise turn the same `perp_delta` into an opposite position.
    reduce_only: bool = false,
    /// Latest accepted block timestamp, in unix seconds.
    deadline: u64 = NO_DEADLINE,
};

pub const LiquidateParams = struct {
    position_id: u256,
    fee_recipient: Address,
    /// How much to liquidate: the absolute perp amount for a taker, or the
    /// liquidity to remove for a maker. Must be nonzero and no larger than the
    /// position; pass the full size for a full liquidation.
    amount: u128,
};

pub const BackstopParams = struct {
    position_id: u256,
    /// Margin in scaled (1e6) units.
    margin_in: u128,
    position_recipient: Address,
    /// Latest accepted block timestamp, in unix seconds.
    deadline: u64 = NO_DEADLINE,
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
