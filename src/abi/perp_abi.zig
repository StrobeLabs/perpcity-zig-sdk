const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

// IPerp surface of perpcity-contracts v1.0.0 (src/interfaces/IPerp.sol and
// src/libraries/Structs.sol). Covers the trading, liquidation, keeper, fee
// collection, and view functions plus the events the SDK decodes. The owner and
// governor configuration setters are intentionally not wrapped.

// ---------------------------------------------------------------------------
// Shared struct components (Structs.sol)
// ---------------------------------------------------------------------------

const open_maker_params_components = [_]AbiParam{
    .{ .name = "holder", .abi_type = .address },
    .{ .name = "margin", .abi_type = .uint128 },
    .{ .name = "tickLower", .abi_type = .int24 },
    .{ .name = "tickUpper", .abi_type = .int24 },
    .{ .name = "liquidity", .abi_type = .uint128 },
    .{ .name = "maxAmt0In", .abi_type = .uint256 },
    .{ .name = "maxAmt1In", .abi_type = .uint256 },
    .{ .name = "deadline", .abi_type = .uint64 },
};

const adjust_maker_params_components = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256 },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "liquidityDelta", .abi_type = .int128 },
    .{ .name = "amt0Limit", .abi_type = .uint256 },
    .{ .name = "amt1Limit", .abi_type = .uint256 },
    .{ .name = "deadline", .abi_type = .uint64 },
};

const move_maker_params_components = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256 },
    .{ .name = "tickLower", .abi_type = .int24 },
    .{ .name = "tickUpper", .abi_type = .int24 },
    .{ .name = "liquidity", .abi_type = .uint128 },
    .{ .name = "removeAmt0Min", .abi_type = .uint256 },
    .{ .name = "removeAmt1Min", .abi_type = .uint256 },
    .{ .name = "addAmt0Max", .abi_type = .uint256 },
    .{ .name = "addAmt1Max", .abi_type = .uint256 },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "deadline", .abi_type = .uint64 },
};

const open_taker_params_components = [_]AbiParam{
    .{ .name = "holder", .abi_type = .address },
    .{ .name = "margin", .abi_type = .uint128 },
    .{ .name = "perpDelta", .abi_type = .int256 },
    .{ .name = "amt1Limit", .abi_type = .uint256 },
    .{ .name = "maxTotalFee", .abi_type = .uint256 },
    .{ .name = "deadline", .abi_type = .uint64 },
};

const adjust_taker_params_components = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256 },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "perpDelta", .abi_type = .int256 },
    .{ .name = "amt1Limit", .abi_type = .uint256 },
    .{ .name = "maxTotalFee", .abi_type = .uint256 },
    .{ .name = "reduceOnly", .abi_type = .bool },
    .{ .name = "deadline", .abi_type = .uint64 },
};

const swap_result_components = [_]AbiParam{
    .{ .name = "delta", .abi_type = .int256 }, // BalanceDelta is int256 packed
    .{ .name = "ammPrice", .abi_type = .uint256 },
    .{ .name = "totalFeeAmt", .abi_type = .int256 },
    .{ .name = "lpFeeAmt", .abi_type = .uint256 },
    .{ .name = "protocolFeeAmt", .abi_type = .uint256 },
    .{ .name = "creatorFeeAmt", .abi_type = .uint256 },
    .{ .name = "insuranceFeeAmt", .abi_type = .uint256 },
    .{ .name = "feeFundFeeAmt", .abi_type = .uint256 },
};

const maker_funding_components = [_]AbiParam{
    .{ .name = "belowX96", .abi_type = .int256 },
    .{ .name = "withinInventoryX192", .abi_type = .int256 },
};

const side_pair_components = [_]AbiParam{
    .{ .name = "long", .abi_type = .uint128 },
    .{ .name = "short", .abi_type = .uint128 },
};

const price_pair_components = [_]AbiParam{
    .{ .name = "ammPrice", .abi_type = .uint128 },
    .{ .name = "index", .abi_type = .uint128 },
};

const rates_components = [_]AbiParam{
    .{ .name = "fundingPerDay", .abi_type = .int88 },
    .{ .name = "longUtilFeePerDay", .abi_type = .uint64 },
    .{ .name = "shortUtilFeePerDay", .abi_type = .uint64 },
    .{ .name = "lastTouch", .abi_type = .uint40 },
    .{ .name = "lastMark", .abi_type = .uint256 },
};

const physical_capacity_components = [_]AbiParam{
    .{ .name = "longCloseX64", .abi_type = .uint256 },
    .{ .name = "shortCloseX64", .abi_type = .uint256 },
};

// ---------------------------------------------------------------------------
// Write functions
// ---------------------------------------------------------------------------

pub const open_maker: Function = .{
    .name = "openMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &open_maker_params_components },
    },
    .outputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
};
pub const open_maker_selector = keccak.selector(
    "openMaker((address,uint128,int24,int24,uint128,uint256,uint256,uint64))",
);

pub const open_taker: Function = .{
    .name = "openTaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &open_taker_params_components },
    },
    .outputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
};
pub const open_taker_selector = keccak.selector(
    "openTaker((address,uint128,int256,uint256,uint256,uint64))",
);

pub const adjust_maker: Function = .{
    .name = "adjustMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &adjust_maker_params_components },
    },
    .outputs = &.{},
};
pub const adjust_maker_selector = keccak.selector(
    "adjustMaker((uint256,int128,int128,uint256,uint256,uint64))",
);

pub const adjust_taker: Function = .{
    .name = "adjustTaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &adjust_taker_params_components },
    },
    .outputs = &.{},
};
pub const adjust_taker_selector = keccak.selector(
    "adjustTaker((uint256,int128,int256,uint256,uint256,bool,uint64))",
);

pub const move_maker: Function = .{
    .name = "moveMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &move_maker_params_components },
    },
    .outputs = &.{},
};
pub const move_maker_selector = keccak.selector(
    "moveMaker((uint256,int24,int24,uint128,uint256,uint256,uint256,uint256,int128,uint64))",
);

pub const liquidate_maker: Function = .{
    .name = "liquidateMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "liquidationFeeRecipient", .abi_type = .address },
        .{ .name = "liquidityAmount", .abi_type = .uint128 },
    },
    .outputs = &.{},
};
pub const liquidate_maker_selector = keccak.selector("liquidateMaker(uint256,address,uint128)");

pub const liquidate_taker: Function = .{
    .name = "liquidateTaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "liquidationFeeRecipient", .abi_type = .address },
        .{ .name = "perpAmount", .abi_type = .uint128 },
    },
    .outputs = &.{},
};
pub const liquidate_taker_selector = keccak.selector("liquidateTaker(uint256,address,uint128)");

pub const backstop_maker: Function = .{
    .name = "backstopMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "positionRecipient", .abi_type = .address },
        .{ .name = "deadline", .abi_type = .uint64 },
    },
    .outputs = &.{},
};
pub const backstop_maker_selector = keccak.selector("backstopMaker(uint256,uint128,address,uint64)");

pub const backstop_taker: Function = .{
    .name = "backstopTaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "positionRecipient", .abi_type = .address },
        .{ .name = "deadline", .abi_type = .uint64 },
    },
    .outputs = &.{},
};
pub const backstop_taker_selector = keccak.selector("backstopTaker(uint256,uint128,address,uint64)");

pub const donate: Function = .{
    .name = "donate",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "amount", .abi_type = .uint128 },
    },
    .outputs = &.{},
};
pub const donate_selector = keccak.selector("donate(uint128)");

pub const touch: Function = .{
    .name = "touch",
    .state_mutability = .nonpayable,
    .inputs = &.{},
    .outputs = &.{},
};
pub const touch_selector = keccak.selector("touch()");

pub const sync_protocol_fee: Function = .{
    .name = "syncProtocolFee",
    .state_mutability = .nonpayable,
    .inputs = &.{},
    .outputs = &.{},
};
pub const sync_protocol_fee_selector = keccak.selector("syncProtocolFee()");

pub const collect_creator_fees: Function = .{
    .name = "collectCreatorFees",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "recipient", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const collect_creator_fees_selector = keccak.selector("collectCreatorFees(address)");

pub const collect_protocol_fees: Function = .{
    .name = "collectProtocolFees",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "recipient", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const collect_protocol_fees_selector = keccak.selector("collectProtocolFees(address)");

// ---------------------------------------------------------------------------
// Read functions
// ---------------------------------------------------------------------------

// Position: risk ratios are no longer stored per position; read them live from
// the margin-ratios module.
pub const positions: Function = .{
    .name = "positions",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "delta", .abi_type = .int256 }, // BalanceDelta
        .{ .name = "margin", .abi_type = .uint128 },
        .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
    },
};
pub const positions_selector = keccak.selector("positions(uint256)");

pub const maker_details: Function = .{
    .name = "makerDetails",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "tickLower", .abi_type = .int24 },
        .{ .name = "tickUpper", .abi_type = .int24 },
        .{ .name = "liquidity", .abi_type = .uint128 },
        .{ .name = "lastLpFeeGrowthInsideX128", .abi_type = .uint256 },
        .{ .name = "lastCumlFunding", .abi_type = .tuple, .components = &maker_funding_components },
        .{ .name = "lastFundingCorrectionX128", .abi_type = .int256 },
    },
};
pub const maker_details_selector = keccak.selector("makerDetails(uint256)");

pub const taker_details: Function = .{
    .name = "takerDetails",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "lastUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "lastReserveUtilPaymentsX96", .abi_type = .uint256 },
    },
};
pub const taker_details_selector = keccak.selector("takerDetails(uint256)");

/// Recorded owner of a position; the zero address means the id is inactive
/// (never opened, closed, or fully liquidated). Does not revert.
pub const position_owner: Function = .{
    .name = "positionOwner",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .address },
    },
};
pub const position_owner_selector = keccak.selector("positionOwner(uint256)");

/// Settled balances and risk flags; reverts `PositionDoesNotExist` for an
/// inactive id.
pub const preview_position: Function = .{
    .name = "previewPosition",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "isMaker", .abi_type = .bool },
        .{ .name = "markPrice", .abi_type = .uint256 },
        .{ .name = "settledMargin", .abi_type = .int256 },
        .{ .name = "pendingLpFees", .abi_type = .uint256 },
        .{ .name = "pendingFunding", .abi_type = .int256 },
        .{ .name = "pendingUtil", .abi_type = .uint256 },
        .{ .name = "pendingReserveUtil", .abi_type = .uint256 },
        .{ .name = "value", .abi_type = .uint256 },
        .{ .name = "unrealizedPnl", .abi_type = .int256 },
        .{ .name = "equity", .abi_type = .int256 },
        .{ .name = "meetsInitialMargin", .abi_type = .bool },
        .{ .name = "liquidatable", .abi_type = .bool },
        .{ .name = "backstoppable", .abi_type = .bool },
        .{ .name = "nominalLiqFee", .abi_type = .uint256 },
        .{ .name = "payableLiqFee", .abi_type = .uint256 },
    },
};
pub const preview_position_selector = keccak.selector("previewPosition(uint256)");

pub const next_pos_id: Function = .{
    .name = "nextPosId",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const next_pos_id_selector = keccak.selector("nextPosId()");

pub const open_interest: Function = .{
    .name = "openInterest",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "long", .abi_type = .uint128 },
        .{ .name = "short", .abi_type = .uint128 },
    },
};
pub const open_interest_selector = keccak.selector("openInterest()");

/// Strict-band closing capacity used for utilization fees; not an open-interest
/// limit. See `physical_close_capacity` for the admission limit.
pub const capacity: Function = .{
    .name = "capacity",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "long", .abi_type = .uint128 },
        .{ .name = "short", .abi_type = .uint128 },
    },
};
pub const capacity_selector = keccak.selector("capacity()");

pub const physical_close_capacity: Function = .{
    .name = "physicalCloseCapacity",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "longClose", .abi_type = .uint128 },
        .{ .name = "shortClose", .abi_type = .uint128 },
    },
};
pub const physical_close_capacity_selector = keccak.selector("physicalCloseCapacity()");

pub const fee_fund: Function = .{
    .name = "feeFund",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "insurance", .abi_type = .uint80 },
        .{ .name = "creatorFees", .abi_type = .uint80 },
        .{ .name = "protocolFees", .abi_type = .uint80 },
    },
};
pub const fee_fund_selector = keccak.selector("feeFund()");

pub const rates: Function = .{
    .name = "rates",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &rates_components,
};
pub const rates_selector = keccak.selector("rates()");

pub const cumulatives: Function = .{
    .name = "cumulatives",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "fundingX96", .abi_type = .int256 },
        .{ .name = "fundingDivSqrtPX192", .abi_type = .int256 },
        .{ .name = "lpFeeGrowthGlobalX128", .abi_type = .uint256 },
        .{ .name = "longUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "shortUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "longReserveUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "shortReserveUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "fundingCorrectionX128", .abi_type = .int256 },
    },
};
pub const cumulatives_selector = keccak.selector("cumulatives()");

pub const funding_state: Function = .{
    .name = "fundingState",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "baseX96", .abi_type = .int256 },
        .{ .name = "inventoryX96", .abi_type = .int256 },
        .{ .name = "makerLiquidity", .abi_type = .uint256 },
    },
};
pub const funding_state_selector = keccak.selector("fundingState()");

pub const utilization_band: Function = .{
    .name = "utilizationBand",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "lower", .abi_type = .uint128 },
        .{ .name = "upper", .abi_type = .uint128 },
    },
};
pub const utilization_band_selector = keccak.selector("utilizationBand()");

pub const pool_state: Function = .{
    .name = "poolState",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "tick", .abi_type = .int24 },
        .{ .name = "sqrtPrice", .abi_type = .uint160 },
        .{ .name = "ammPrice", .abi_type = .uint256 },
        .{ .name = "liquidity", .abi_type = .uint128 },
    },
};
pub const pool_state_selector = keccak.selector("poolState()");

pub const solvency_state: Function = .{
    .name = "solvencyState",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "badDebt", .abi_type = .uint128 },
        .{ .name = "totalMargin", .abi_type = .uint128 },
    },
};
pub const solvency_state_selector = keccak.selector("solvencyState()");

pub const modules: Function = .{
    .name = "modules",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "beacon", .abi_type = .address },
        .{ .name = "fees", .abi_type = .address },
        .{ .name = "funding", .abi_type = .address },
        .{ .name = "marginRatios", .abi_type = .address },
        .{ .name = "priceImpact", .abi_type = .address },
        .{ .name = "pricing", .abi_type = .address },
    },
};
pub const modules_selector = keccak.selector("modules()");

pub const protocol_fee: Function = .{
    .name = "protocolFee",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const protocol_fee_selector = keccak.selector("protocolFee()");

pub const accounted_tvl: Function = .{
    .name = "accountedTvl",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "tvl", .abi_type = .uint256 },
    },
};
pub const accounted_tvl_selector = keccak.selector("accountedTvl()");

pub const tvl_cap: Function = .{
    .name = "tvlCap",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const tvl_cap_selector = keccak.selector("tvlCap()");

pub const ema_window: Function = .{
    .name = "emaWindow",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const ema_window_selector = keccak.selector("emaWindow()");

pub const latency: Function = .{
    .name = "latency",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint32 },
    },
};
pub const latency_selector = keccak.selector("latency()");

pub const owner: Function = .{
    .name = "owner",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .address },
    },
};
pub const owner_selector = keccak.selector("owner()");

pub const governor: Function = .{
    .name = "governor",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .address },
    },
};
pub const governor_selector = keccak.selector("governor()");

/// The accounted-payout controller; the zero address means payouts are sent
/// directly. See `withdrawal_controller_abi.zig`.
pub const withdrawal_controller: Function = .{
    .name = "withdrawalController",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .address },
    },
};
pub const withdrawal_controller_selector = keccak.selector("withdrawalController()");

pub const permissionless_donations_enabled: Function = .{
    .name = "permissionlessDonationsEnabled",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .bool },
    },
};
pub const permissionless_donations_enabled_selector = keccak.selector("permissionlessDonationsEnabled()");

/// Validated beacon index (Q96) using the market's latency; reverts when the
/// observation is unreadable, stale, or outside the allowed index range.
pub const read_beacon_index: Function = .{
    .name = "readBeaconIndex",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "beacon", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint128 },
    },
};
pub const read_beacon_index_selector = keccak.selector("readBeaconIndex(address)");

// ---------------------------------------------------------------------------
// Events
//
// `posId` is indexed on every position event, and `owner` / `feeRecipient` are
// indexed where present, so those live in `topics[1..]`; everything else is in
// the log data. Liquidations emit the lifecycle event (Adjusted / Closed /
// Converted) followed by a dedicated `MakerLiquidated` / `TakerLiquidated`.
// ---------------------------------------------------------------------------

pub const maker_opened_event: Event = .{
    .name = "MakerOpened",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "owner", .abi_type = .address, .indexed = true },
        .{ .name = "tickLower", .abi_type = .int24 },
        .{ .name = "tickUpper", .abi_type = .int24 },
        .{ .name = "liquidity", .abi_type = .uint128 },
        .{ .name = "delta", .abi_type = .int256 },
        .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
        .{ .name = "lastCumlFunding", .abi_type = .tuple, .components = &maker_funding_components },
    },
};
pub const maker_opened_topic = keccak.hash(
    "MakerOpened(uint256,address,int24,int24,uint128,int256,int256,(int256,int256))",
);

// MakerAdjusted, MakerClosed, and MakerConverted share one layout.
const maker_lifecycle_inputs = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256, .indexed = true },
    .{ .name = "owner", .abi_type = .address, .indexed = true },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "liquidityDelta", .abi_type = .int128 },
    .{ .name = "funding", .abi_type = .int256 },
    .{ .name = "lpFees", .abi_type = .uint256 },
    .{ .name = "delta", .abi_type = .int256 },
    .{ .name = "margin", .abi_type = .uint128 },
    .{ .name = "liquidity", .abi_type = .uint128 },
    .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
    .{ .name = "lastCumlFunding", .abi_type = .tuple, .components = &maker_funding_components },
};

pub const maker_adjusted_event: Event = .{ .name = "MakerAdjusted", .inputs = &maker_lifecycle_inputs };
pub const maker_adjusted_topic = keccak.hash(
    "MakerAdjusted(uint256,address,int128,int128,int256,uint256,int256,uint128,uint128,int256,(int256,int256))",
);

pub const maker_closed_event: Event = .{ .name = "MakerClosed", .inputs = &maker_lifecycle_inputs };
pub const maker_closed_topic = keccak.hash(
    "MakerClosed(uint256,address,int128,int128,int256,uint256,int256,uint128,uint128,int256,(int256,int256))",
);

pub const maker_converted_event: Event = .{ .name = "MakerConverted", .inputs = &maker_lifecycle_inputs };
pub const maker_converted_topic = keccak.hash(
    "MakerConverted(uint256,address,int128,int128,int256,uint256,int256,uint128,uint128,int256,(int256,int256))",
);

pub const maker_backstopped_event: Event = .{
    .name = "MakerBackstopped",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "posRecipient", .abi_type = .address },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "lpFees", .abi_type = .uint256 },
        .{ .name = "margin", .abi_type = .uint128 },
        .{ .name = "delta", .abi_type = .int256 },
        .{ .name = "liquidity", .abi_type = .uint128 },
        .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
        .{ .name = "lastCumlFunding", .abi_type = .tuple, .components = &maker_funding_components },
    },
};
pub const maker_backstopped_topic = keccak.hash(
    "MakerBackstopped(uint256,uint128,address,int256,uint256,uint128,int256,uint128,int256,(int256,int256))",
);

pub const maker_liquidated_event: Event = .{
    .name = "MakerLiquidated",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "feeRecipient", .abi_type = .address, .indexed = true },
        .{ .name = "liquidityAmount", .abi_type = .uint128 },
        .{ .name = "liqFee", .abi_type = .uint256 },
    },
};
pub const maker_liquidated_topic = keccak.hash("MakerLiquidated(uint256,address,uint128,uint256)");

pub const maker_moved_event: Event = .{
    .name = "MakerMoved",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "owner", .abi_type = .address, .indexed = true },
        .{ .name = "oldTickLower", .abi_type = .int24 },
        .{ .name = "oldTickUpper", .abi_type = .int24 },
        .{ .name = "newTickLower", .abi_type = .int24 },
        .{ .name = "newTickUpper", .abi_type = .int24 },
        .{ .name = "oldLiquidity", .abi_type = .uint128 },
        .{ .name = "newLiquidity", .abi_type = .uint128 },
        .{ .name = "marginDelta", .abi_type = .int128 },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "lpFees", .abi_type = .uint256 },
    },
};
pub const maker_moved_topic = keccak.hash(
    "MakerMoved(uint256,address,int24,int24,int24,int24,uint128,uint128,int128,int256,uint256)",
);

pub const taker_opened_event: Event = .{
    .name = "TakerOpened",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "owner", .abi_type = .address, .indexed = true },
        .{ .name = "margin", .abi_type = .uint128 },
        .{ .name = "sr", .abi_type = .tuple, .components = &swap_result_components },
        .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
    },
};
pub const taker_opened_topic = keccak.hash(
    "TakerOpened(uint256,address,uint128,(int256,uint256,int256,uint256,uint256,uint256,uint256,uint256),int256)",
);

// TakerAdjusted and TakerClosed share one layout.
const taker_lifecycle_inputs = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256, .indexed = true },
    .{ .name = "owner", .abi_type = .address, .indexed = true },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "sr", .abi_type = .tuple, .components = &swap_result_components },
    .{ .name = "funding", .abi_type = .int256 },
    .{ .name = "utilFees", .abi_type = .uint256 },
    .{ .name = "delta", .abi_type = .int256 },
    .{ .name = "margin", .abi_type = .uint128 },
    .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
};

pub const taker_adjusted_event: Event = .{ .name = "TakerAdjusted", .inputs = &taker_lifecycle_inputs };
pub const taker_adjusted_topic = keccak.hash(
    "TakerAdjusted(uint256,address,int128,(int256,uint256,int256,uint256,uint256,uint256,uint256,uint256),int256,uint256,int256,uint128,int256)",
);

pub const taker_closed_event: Event = .{ .name = "TakerClosed", .inputs = &taker_lifecycle_inputs };
pub const taker_closed_topic = keccak.hash(
    "TakerClosed(uint256,address,int128,(int256,uint256,int256,uint256,uint256,uint256,uint256,uint256),int256,uint256,int256,uint128,int256)",
);

pub const taker_backstopped_event: Event = .{
    .name = "TakerBackstopped",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "posRecipient", .abi_type = .address },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "utilFees", .abi_type = .uint256 },
        .{ .name = "delta", .abi_type = .int256 },
        .{ .name = "margin", .abi_type = .uint128 },
        .{ .name = "lastCumlFundingX96", .abi_type = .int256 },
    },
};
pub const taker_backstopped_topic = keccak.hash(
    "TakerBackstopped(uint256,uint128,address,int256,uint256,int256,uint128,int256)",
);

pub const taker_liquidated_event: Event = .{
    .name = "TakerLiquidated",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "feeRecipient", .abi_type = .address, .indexed = true },
        .{ .name = "perpAmount", .abi_type = .uint128 },
        .{ .name = "liqFee", .abi_type = .uint256 },
    },
};
pub const taker_liquidated_topic = keccak.hash("TakerLiquidated(uint256,address,uint128,uint256)");

pub const position_owner_updated_event: Event = .{
    .name = "PositionOwnerUpdated",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "oldOwner", .abi_type = .address, .indexed = true },
        .{ .name = "newOwner", .abi_type = .address, .indexed = true },
    },
};
pub const position_owner_updated_topic = keccak.hash("PositionOwnerUpdated(uint256,address,address)");

pub const quote_folded_event: Event = .{
    .name = "QuoteFolded",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "amount", .abi_type = .int256 },
    },
};
pub const quote_folded_topic = keccak.hash("QuoteFolded(uint256,int256)");

pub const donated_event: Event = .{
    .name = "Donated",
    .inputs = &.{
        .{ .name = "donor", .abi_type = .address },
        .{ .name = "amount", .abi_type = .uint128 },
        .{ .name = "badDebt", .abi_type = .uint128 },
        .{ .name = "insurance", .abi_type = .uint80 },
    },
};
pub const donated_topic = keccak.hash("Donated(address,uint128,uint128,uint80)");

pub const open_interest_updated_event: Event = .{
    .name = "OpenInterestUpdated",
    .inputs = &.{
        .{ .name = "oi", .abi_type = .tuple, .components = &side_pair_components },
    },
};
pub const open_interest_updated_topic = keccak.hash("OpenInterestUpdated((uint128,uint128))");

pub const capacity_updated_event: Event = .{
    .name = "CapacityUpdated",
    .inputs = &.{
        .{ .name = "cap", .abi_type = .tuple, .components = &side_pair_components },
    },
};
pub const capacity_updated_topic = keccak.hash("CapacityUpdated((uint128,uint128))");

pub const physical_capacity_updated_event: Event = .{
    .name = "PhysicalCapacityUpdated",
    .inputs = &.{
        .{ .name = "physicalCap", .abi_type = .tuple, .components = &physical_capacity_components },
    },
};
pub const physical_capacity_updated_topic = keccak.hash("PhysicalCapacityUpdated((uint256,uint256))");

pub const rates_and_emas_refreshed_event: Event = .{
    .name = "RatesAndEmasRefreshed",
    .inputs = &.{
        .{ .name = "rates", .abi_type = .tuple, .components = &rates_components },
        .{ .name = "index", .abi_type = .uint128 },
        .{ .name = "emas", .abi_type = .tuple, .components = &price_pair_components },
    },
};
pub const rates_and_emas_refreshed_topic = keccak.hash(
    "RatesAndEmasRefreshed((int88,uint64,uint64,uint40,uint256),uint128,(uint128,uint128))",
);

pub const bad_debt_accounted_event: Event = .{
    .name = "BadDebtAccounted",
    .inputs = &.{
        .{ .name = "badDebt", .abi_type = .uint256 },
        .{ .name = "insuranceConsumed", .abi_type = .uint256 },
        .{ .name = "insuranceAfter", .abi_type = .uint256 },
        .{ .name = "badDebtAfter", .abi_type = .uint128 },
    },
};
pub const bad_debt_accounted_topic = keccak.hash("BadDebtAccounted(uint256,uint256,uint256,uint128)");
