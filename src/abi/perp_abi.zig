const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

// ---------------------------------------------------------------------------
// Param struct components -- mirror perpcity-contracts v0.1.0 SharedStructs.sol
// ---------------------------------------------------------------------------

const open_maker_params_components = [_]AbiParam{
    .{ .name = "holder", .abi_type = .address },
    .{ .name = "margin", .abi_type = .uint128 },
    .{ .name = "tickLower", .abi_type = .int24 },
    .{ .name = "tickUpper", .abi_type = .int24 },
    .{ .name = "liquidity", .abi_type = .uint128 },
    .{ .name = "maxAmt0In", .abi_type = .uint256 },
    .{ .name = "maxAmt1In", .abi_type = .uint256 },
};

const adjust_maker_params_components = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256 },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "liquidityDelta", .abi_type = .int128 },
    .{ .name = "amt0Limit", .abi_type = .uint256 },
    .{ .name = "amt1Limit", .abi_type = .uint256 },
};

const open_taker_params_components = [_]AbiParam{
    .{ .name = "holder", .abi_type = .address },
    .{ .name = "margin", .abi_type = .uint128 },
    .{ .name = "perpDelta", .abi_type = .int256 },
    .{ .name = "amt1Limit", .abi_type = .uint256 },
};

const adjust_taker_params_components = [_]AbiParam{
    .{ .name = "posId", .abi_type = .uint256 },
    .{ .name = "marginDelta", .abi_type = .int128 },
    .{ .name = "perpDelta", .abi_type = .int256 },
    .{ .name = "amt1Limit", .abi_type = .uint256 },
};

const swap_result_components = [_]AbiParam{
    .{ .name = "delta", .abi_type = .int256 }, // BalanceDelta is int256 packed
    .{ .name = "ammPrice", .abi_type = .uint256 },
    .{ .name = "totalFeeAmt", .abi_type = .int256 },
    .{ .name = "lpFeeAmt", .abi_type = .uint256 },
    .{ .name = "protocolFeeAmt", .abi_type = .uint256 },
    .{ .name = "creatorFeeAmt", .abi_type = .uint256 },
    .{ .name = "insuranceFeeAmt", .abi_type = .uint256 },
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
    "openMaker((address,uint128,int24,int24,uint128,uint256,uint256))",
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
    "openTaker((address,uint128,int256,uint256))",
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
    "adjustMaker((uint256,int128,int128,uint256,uint256))",
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
    "adjustTaker((uint256,int128,int256,uint256))",
);

pub const liquidate_maker: Function = .{
    .name = "liquidateMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "liquidationFeeRecipient", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const liquidate_maker_selector = keccak.selector("liquidateMaker(uint256,address)");

pub const liquidate_taker: Function = .{
    .name = "liquidateTaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "liquidationFeeRecipient", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const liquidate_taker_selector = keccak.selector("liquidateTaker(uint256,address)");

pub const backstop_maker: Function = .{
    .name = "backstopMaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "positionRecipient", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const backstop_maker_selector = keccak.selector("backstopMaker(uint256,uint128,address)");

pub const backstop_taker: Function = .{
    .name = "backstopTaker",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "positionRecipient", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const backstop_taker_selector = keccak.selector("backstopTaker(uint256,uint128,address)");

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

pub const positions: Function = .{
    .name = "positions",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "delta", .abi_type = .int256 }, // BalanceDelta
        .{ .name = "margin", .abi_type = .uint128 },
        .{ .name = "liqMarginRatio", .abi_type = .uint24 },
        .{ .name = "backstopMarginRatio", .abi_type = .uint24 },
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
        .{ .name = "lastLongUtilEarningsX96", .abi_type = .uint256 },
        .{ .name = "lastShortUtilEarningsX96", .abi_type = .uint256 },
        .{ .name = "capacity", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "long", .abi_type = .uint128 },
            .{ .name = "short", .abi_type = .uint128 },
        } },
        .{ .name = "lastCumlFunding", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "belowX96", .abi_type = .int256 },
            .{ .name = "withinX96", .abi_type = .int256 },
            .{ .name = "divSqrtPriceWithinX96", .abi_type = .int256 },
        } },
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
        .{ .name = "lastLongUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "lastShortUtilPaymentsX96", .abi_type = .uint256 },
    },
};
pub const taker_details_selector = keccak.selector("takerDetails(uint256)");

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
    .outputs = &.{
        .{ .name = "fundingPerDay", .abi_type = .int88 },
        .{ .name = "longUtilFeePerDay", .abi_type = .uint64 },
        .{ .name = "shortUtilFeePerDay", .abi_type = .uint64 },
        .{ .name = "lastTouch", .abi_type = .uint40 },
    },
};
pub const rates_selector = keccak.selector("rates()");

pub const emas: Function = .{
    .name = "emas",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "ammPrice", .abi_type = .uint128 },
        .{ .name = "index", .abi_type = .uint128 },
    },
};
pub const emas_selector = keccak.selector("emas()");

pub const cumulatives: Function = .{
    .name = "cumulatives",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "fundingX96", .abi_type = .int256 },
        .{ .name = "fundingDivSqrtPX96", .abi_type = .int256 },
        .{ .name = "longUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "shortUtilPaymentsX96", .abi_type = .uint256 },
        .{ .name = "longUtilEarningsX96", .abi_type = .uint256 },
        .{ .name = "shortUtilEarningsX96", .abi_type = .uint256 },
    },
};
pub const cumulatives_selector = keccak.selector("cumulatives()");

pub const pool_state: Function = .{
    .name = "poolState",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "tick", .abi_type = .int24 },
        .{ .name = "sqrtPriceX96", .abi_type = .uint160 },
        .{ .name = "ammPriceX96", .abi_type = .uint256 },
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

// ERC721 position-ownership views. Positions are ERC721 NFTs minted by the Perp
// (Solady ERC721 base). The Perp is NOT ERC721Enumerable, so on-chain
// enumeration is unavailable; discover position IDs via events (see events.zig)
// and use these to confirm live ownership on-chain.
pub const owner_of: Function = .{
    .name = "ownerOf",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "id", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "owner", .abi_type = .address },
    },
};
pub const owner_of_selector = keccak.selector("ownerOf(uint256)");

pub const balance_of: Function = .{
    .name = "balanceOf",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "owner", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "result", .abi_type = .uint256 },
    },
};
pub const balance_of_selector = keccak.selector("balanceOf(address)");

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

pub const maker_opened_event: Event = .{
    .name = "MakerOpened",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
};
pub const maker_opened_topic = keccak.hash("MakerOpened(uint256)");

pub const maker_adjusted_event: Event = .{
    .name = "MakerAdjusted",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "longUtilFees", .abi_type = .uint256 },
        .{ .name = "shortUtilFees", .abi_type = .uint256 },
        .{ .name = "lpFees", .abi_type = .uint256 },
    },
};
pub const maker_adjusted_topic = keccak.hash("MakerAdjusted(uint256,int256,uint256,uint256,uint256)");

pub const maker_closed_event: Event = .{
    .name = "MakerClosed",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "longUtilFees", .abi_type = .uint256 },
        .{ .name = "shortUtilFees", .abi_type = .uint256 },
        .{ .name = "lpFees", .abi_type = .uint256 },
        .{ .name = "liqFee", .abi_type = .uint256 },
        .{ .name = "isLiquidation", .abi_type = .bool },
    },
};
pub const maker_closed_topic = keccak.hash(
    "MakerClosed(uint256,int256,uint256,uint256,uint256,uint256,bool)",
);

pub const maker_converted_event: Event = .{
    .name = "MakerConverted",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "longUtilFees", .abi_type = .uint256 },
        .{ .name = "shortUtilFees", .abi_type = .uint256 },
        .{ .name = "lpFees", .abi_type = .uint256 },
        .{ .name = "liqFee", .abi_type = .uint256 },
        .{ .name = "isLiquidation", .abi_type = .bool },
    },
};
pub const maker_converted_topic = keccak.hash(
    "MakerConverted(uint256,int256,uint256,uint256,uint256,uint256,bool)",
);

pub const maker_backstopped_event: Event = .{
    .name = "MakerBackstopped",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "posRecipient", .abi_type = .address },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "longUtilFees", .abi_type = .uint256 },
        .{ .name = "shortUtilFees", .abi_type = .uint256 },
        .{ .name = "lpFees", .abi_type = .uint256 },
    },
};
pub const maker_backstopped_topic = keccak.hash(
    "MakerBackstopped(uint256,uint128,address,int256,uint256,uint256,uint256)",
);

pub const taker_opened_event: Event = .{
    .name = "TakerOpened",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "sr", .abi_type = .tuple, .components = &swap_result_components },
    },
};
pub const taker_opened_topic = keccak.hash(
    "TakerOpened(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256))",
);

pub const taker_adjusted_event: Event = .{
    .name = "TakerAdjusted",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "sr", .abi_type = .tuple, .components = &swap_result_components },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "utilFees", .abi_type = .uint256 },
    },
};
pub const taker_adjusted_topic = keccak.hash(
    "TakerAdjusted(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256),int256,uint256)",
);

pub const taker_closed_event: Event = .{
    .name = "TakerClosed",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "sr", .abi_type = .tuple, .components = &swap_result_components },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "utilFees", .abi_type = .uint256 },
        .{ .name = "liqFee", .abi_type = .uint256 },
        .{ .name = "isLiquidation", .abi_type = .bool },
    },
};
pub const taker_closed_topic = keccak.hash(
    "TakerClosed(uint256,(int256,uint256,int256,uint256,uint256,uint256,uint256),int256,uint256,uint256,bool)",
);

pub const taker_backstopped_event: Event = .{
    .name = "TakerBackstopped",
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
        .{ .name = "marginIn", .abi_type = .uint128 },
        .{ .name = "posRecipient", .abi_type = .address },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "utilFees", .abi_type = .uint256 },
    },
};
pub const taker_backstopped_topic = keccak.hash(
    "TakerBackstopped(uint256,uint128,address,int256,uint256)",
);

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
        .{ .name = "oi", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "long", .abi_type = .uint128 },
            .{ .name = "short", .abi_type = .uint128 },
        } },
    },
};
pub const open_interest_updated_topic = keccak.hash("OpenInterestUpdated((uint128,uint128))");

pub const capacity_updated_event: Event = .{
    .name = "CapacityUpdated",
    .inputs = &.{
        .{ .name = "cap", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "long", .abi_type = .uint128 },
            .{ .name = "short", .abi_type = .uint128 },
        } },
    },
};
pub const capacity_updated_topic = keccak.hash("CapacityUpdated((uint128,uint128))");
