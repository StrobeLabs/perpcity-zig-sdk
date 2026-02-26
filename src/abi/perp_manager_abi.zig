const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

// -- Read functions --

pub const cfgs: Function = .{
    .name = "cfgs",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
    },
    .outputs = &.{
        .{ .name = "key", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "currency0", .abi_type = .address },
            .{ .name = "currency1", .abi_type = .address },
            .{ .name = "fee", .abi_type = .uint24 },
            .{ .name = "tickSpacing", .abi_type = .int24 },
            .{ .name = "hooks", .abi_type = .address },
        } },
        .{ .name = "creator", .abi_type = .address },
        .{ .name = "vault", .abi_type = .address },
        .{ .name = "beacon", .abi_type = .address },
        .{ .name = "fees", .abi_type = .address },
        .{ .name = "marginRatios", .abi_type = .address },
        .{ .name = "lockupPeriod", .abi_type = .address },
        .{ .name = "sqrtPriceImpactLimit", .abi_type = .address },
    },
};
pub const cfgs_selector = keccak.comptimeSelector("cfgs(bytes32)");

pub const positions: Function = .{
    .name = "positions",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
        .{ .name = "margin", .abi_type = .uint256 },
        .{ .name = "entryPerpDelta", .abi_type = .int256 },
        .{ .name = "entryUsdDelta", .abi_type = .int256 },
        .{ .name = "entryCumlFundingX96", .abi_type = .int256 },
        .{ .name = "entryCumlBadDebtX96", .abi_type = .uint256 },
        .{ .name = "entryCumlUtilizationX96", .abi_type = .uint256 },
        .{ .name = "marginRatios", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "min", .abi_type = .uint24 },
            .{ .name = "max", .abi_type = .uint24 },
            .{ .name = "liq", .abi_type = .uint24 },
        } },
        .{ .name = "makerDetails", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "tickLower", .abi_type = .int24 },
            .{ .name = "tickUpper", .abi_type = .int24 },
            .{ .name = "liquidity", .abi_type = .uint128 },
        } },
    },
};
pub const positions_selector = keccak.comptimeSelector("positions(uint256)");

pub const quote_close_position: Function = .{
    .name = "quoteClosePosition",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "posId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "unexpectedReason", .abi_type = .bytes },
        .{ .name = "pnl", .abi_type = .int256 },
        .{ .name = "funding", .abi_type = .int256 },
        .{ .name = "netMargin", .abi_type = .uint256 },
        .{ .name = "wasLiquidated", .abi_type = .bool },
    },
};
pub const quote_close_position_selector = keccak.comptimeSelector("quoteClosePosition(uint256)");

pub const time_weighted_avg_sqrt_price_x96: Function = .{
    .name = "timeWeightedAvgSqrtPriceX96",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
        .{ .name = "lookbackWindow", .abi_type = .uint32 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const time_weighted_avg_sqrt_price_x96_selector = keccak.comptimeSelector("timeWeightedAvgSqrtPriceX96(bytes32,uint32)");

pub const protocol_fee: Function = .{
    .name = "protocolFee",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const protocol_fee_selector = keccak.comptimeSelector("protocolFee()");

// -- Write functions --

pub const create_perp: Function = .{
    .name = "createPerp",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "beacon", .abi_type = .address },
            .{ .name = "fees", .abi_type = .address },
            .{ .name = "marginRatios", .abi_type = .address },
            .{ .name = "lockupPeriod", .abi_type = .address },
            .{ .name = "sqrtPriceImpactLimit", .abi_type = .address },
            .{ .name = "startingSqrtPriceX96", .abi_type = .uint160 },
        } },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .bytes32 },
    },
};
pub const create_perp_selector = keccak.comptimeSelector("createPerp((address,address,address,address,address,uint160))");

pub const open_taker_pos: Function = .{
    .name = "openTakerPos",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "holder", .abi_type = .address },
            .{ .name = "isLong", .abi_type = .bool },
            .{ .name = "margin", .abi_type = .uint128 },
            .{ .name = "marginRatio", .abi_type = .uint24 },
            .{ .name = "unspecifiedAmountLimit", .abi_type = .uint128 },
        } },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const open_taker_pos_selector = keccak.comptimeSelector("openTakerPos(bytes32,(address,bool,uint128,uint24,uint128))");

pub const open_maker_pos: Function = .{
    .name = "openMakerPos",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "holder", .abi_type = .address },
            .{ .name = "margin", .abi_type = .uint128 },
            .{ .name = "liquidity", .abi_type = .uint120 },
            .{ .name = "tickLower", .abi_type = .int24 },
            .{ .name = "tickUpper", .abi_type = .int24 },
            .{ .name = "maxAmt0In", .abi_type = .uint128 },
            .{ .name = "maxAmt1In", .abi_type = .uint128 },
        } },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const open_maker_pos_selector = keccak.comptimeSelector("openMakerPos(bytes32,(address,uint128,uint120,int24,int24,uint128,uint128))");

pub const close_position: Function = .{
    .name = "closePosition",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "posId", .abi_type = .uint256 },
            .{ .name = "minAmt0Out", .abi_type = .uint128 },
            .{ .name = "minAmt1Out", .abi_type = .uint128 },
            .{ .name = "maxAmt1In", .abi_type = .uint128 },
        } },
    },
    .outputs = &.{},
};
pub const close_position_selector = keccak.comptimeSelector("closePosition((uint256,uint128,uint128,uint128))");

pub const adjust_notional: Function = .{
    .name = "adjustNotional",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "posId", .abi_type = .uint256 },
            .{ .name = "usdDelta", .abi_type = .int256 },
            .{ .name = "perpLimit", .abi_type = .uint128 },
        } },
    },
    .outputs = &.{},
};
pub const adjust_notional_selector = keccak.comptimeSelector("adjustNotional((uint256,int256,uint128))");

pub const adjust_margin: Function = .{
    .name = "adjustMargin",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "posId", .abi_type = .uint256 },
            .{ .name = "marginDelta", .abi_type = .int256 },
        } },
    },
    .outputs = &.{},
};
pub const adjust_margin_selector = keccak.comptimeSelector("adjustMargin((uint256,int256))");

pub const funding_per_second_x96: Function = .{
    .name = "fundingPerSecondX96",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .int256 },
    },
};
pub const funding_per_second_x96_selector = keccak.comptimeSelector("fundingPerSecondX96(bytes32)");

pub const util_fee_per_sec_x96: Function = .{
    .name = "utilFeePerSecX96",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const util_fee_per_sec_x96_selector = keccak.comptimeSelector("utilFeePerSecX96(bytes32)");

pub const insurance: Function = .{
    .name = "insurance",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint128 },
    },
};
pub const insurance_selector = keccak.comptimeSelector("insurance(bytes32)");

pub const taker_open_interest: Function = .{
    .name = "takerOpenInterest",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
    },
    .outputs = &.{
        .{ .name = "longOI", .abi_type = .uint128 },
        .{ .name = "shortOI", .abi_type = .uint128 },
    },
};
pub const taker_open_interest_selector = keccak.comptimeSelector("takerOpenInterest(bytes32)");

pub const quote_open_taker_position: Function = .{
    .name = "quoteOpenTakerPosition",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "holder", .abi_type = .address },
            .{ .name = "isLong", .abi_type = .bool },
            .{ .name = "margin", .abi_type = .uint128 },
            .{ .name = "marginRatio", .abi_type = .uint24 },
            .{ .name = "unspecifiedAmountLimit", .abi_type = .uint128 },
        } },
    },
    .outputs = &.{
        .{ .name = "unexpectedReason", .abi_type = .bytes },
        .{ .name = "pnl", .abi_type = .int256 },
        .{ .name = "funding", .abi_type = .int256 },
    },
};
pub const quote_open_taker_position_selector = keccak.comptimeSelector("quoteOpenTakerPosition(bytes32,(address,bool,uint128,uint24,uint128))");

pub const quote_open_maker_position: Function = .{
    .name = "quoteOpenMakerPosition",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32 },
        .{ .name = "params", .abi_type = .tuple, .components = &[_]AbiParam{
            .{ .name = "holder", .abi_type = .address },
            .{ .name = "margin", .abi_type = .uint128 },
            .{ .name = "liquidity", .abi_type = .uint120 },
            .{ .name = "tickLower", .abi_type = .int24 },
            .{ .name = "tickUpper", .abi_type = .int24 },
            .{ .name = "maxAmt0In", .abi_type = .uint128 },
            .{ .name = "maxAmt1In", .abi_type = .uint128 },
        } },
    },
    .outputs = &.{
        .{ .name = "unexpectedReason", .abi_type = .bytes },
        .{ .name = "pnl", .abi_type = .int256 },
        .{ .name = "funding", .abi_type = .int256 },
    },
};
pub const quote_open_maker_position_selector = keccak.comptimeSelector("quoteOpenMakerPosition(bytes32,(address,uint128,uint120,int24,int24,uint128,uint128))");

// -- Events --

pub const perp_created: Event = .{
    .name = "PerpCreated",
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32, .indexed = true },
    },
};

pub const position_opened: Event = .{
    .name = "PositionOpened",
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32, .indexed = true },
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
        .{ .name = "isMaker", .abi_type = .bool },
    },
};

pub const position_closed: Event = .{
    .name = "PositionClosed",
    .inputs = &.{
        .{ .name = "perpId", .abi_type = .bytes32, .indexed = true },
        .{ .name = "posId", .abi_type = .uint256, .indexed = true },
    },
};
