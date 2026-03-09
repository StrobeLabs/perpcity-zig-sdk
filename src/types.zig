const std = @import("std");

/// Ethereum address (20 bytes).
pub const Address = [20]u8;

/// Bytes32, used for perp IDs and transaction hashes.
pub const Bytes32 = [32]u8;

/// Zero address constant.
pub const ZERO_ADDRESS: Address = [_]u8{0} ** 20;

/// Zero bytes32 constant.
pub const ZERO_BYTES32: Bytes32 = [_]u8{0} ** 32;

pub const PerpCityDeployments = struct {
    perp_manager: Address,
    usdc: Address,
    fees_module: ?Address = null,
    margin_ratios_module: ?Address = null,
    lockup_period_module: ?Address = null,
    sqrt_price_impact_limit_module: ?Address = null,
};

pub const PoolKey = struct {
    currency0: Address,
    currency1: Address,
    fee: u24,
    tick_spacing: i24,
    hooks: Address,
};

pub const PerpConfig = struct {
    key: PoolKey,
    creator: Address,
    vault: Address,
    beacon: Address,
    fees: Address,
    margin_ratios: Address,
    lockup_period: Address,
    sqrt_price_impact_limit: Address,
};

pub const Bounds = struct {
    min_margin: f64,
    min_taker_leverage: f64,
    max_taker_leverage: f64,
    liquidation_taker_ratio: f64,
};

pub const Fees = struct {
    creator_fee: f64,
    insurance_fee: f64,
    lp_fee: f64,
    liquidation_fee: f64,
};

pub const LiveDetails = struct {
    pnl: f64,
    funding_payment: f64,
    effective_margin: f64,
    is_liquidatable: bool,
};

pub const PerpData = struct {
    id: Bytes32,
    tick_spacing: i24,
    mark: f64,
    beacon: Address,
    bounds: Bounds,
    fees: Fees,
};

pub const OpenPositionData = struct {
    perp_id: Bytes32,
    position_id: u256,
    is_long: ?bool = null,
    is_maker: ?bool = null,
    live_details: LiveDetails,
};

pub const MarginRatios = struct {
    min: u24,
    max: u24,
    liq: u24,
};

pub const PositionRawData = struct {
    perp_id: Bytes32,
    position_id: u256,
    margin: f64,
    entry_perp_delta: i256,
    entry_usd_delta: i256,
    margin_ratios: MarginRatios,
};

pub const UserData = struct {
    wallet_address: Address,
    usdc_balance: f64,
    open_positions: []const OpenPositionData,
};

pub const OpenTakerPositionParams = struct {
    is_long: bool,
    margin: f64,
    leverage: f64,
    unspecified_amount_limit: u128,
};

pub const OpenMakerPositionParams = struct {
    margin: f64,
    price_lower: f64,
    price_upper: f64,
    liquidity: u128,
    max_amt0_in: u128,
    max_amt1_in: u128,
};

pub const CreatePerpParams = struct {
    beacon: Address,
    fees: ?Address = null,
    margin_ratios: ?Address = null,
    lockup_period: ?Address = null,
    sqrt_price_impact_limit: ?Address = null,
};

pub const ClosePositionParams = struct {
    min_amt0_out: u128,
    min_amt1_out: u128,
    max_amt1_in: u128,
};

pub const ClosePositionResult = struct {
    /// null means fully closed, non-null means partial close (new position).
    position: ?OpenPositionData,
    tx_hash: Bytes32,
};

pub const AdjustNotionalParams = struct {
    position_id: u256,
    usd_delta: i128,
    perp_limit: u128,
};

pub const AdjustMarginParams = struct {
    position_id: u256,
    margin_delta: i128,
};

pub const OpenInterest = struct {
    long_oi: u128,
    short_oi: u128,
};
