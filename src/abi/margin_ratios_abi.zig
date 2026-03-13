const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

pub const min_taker_ratio: Function = .{
    .name = "MIN_TAKER_RATIO",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const min_taker_ratio_selector = keccak.selector("MIN_TAKER_RATIO()");

pub const max_taker_ratio: Function = .{
    .name = "MAX_TAKER_RATIO",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const max_taker_ratio_selector = keccak.selector("MAX_TAKER_RATIO()");

pub const liquidation_taker_ratio: Function = .{
    .name = "LIQUIDATION_TAKER_RATIO",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const liquidation_taker_ratio_selector = keccak.selector("LIQUIDATION_TAKER_RATIO()");

pub const min_maker_ratio: Function = .{
    .name = "MIN_MAKER_RATIO",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const min_maker_ratio_selector = keccak.selector("MIN_MAKER_RATIO()");

pub const max_maker_ratio: Function = .{
    .name = "MAX_MAKER_RATIO",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const max_maker_ratio_selector = keccak.selector("MAX_MAKER_RATIO()");

pub const liquidation_maker_ratio: Function = .{
    .name = "LIQUIDATION_MAKER_RATIO",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const liquidation_maker_ratio_selector = keccak.selector("LIQUIDATION_MAKER_RATIO()");
