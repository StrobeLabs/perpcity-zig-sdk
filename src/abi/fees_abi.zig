const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

pub const creator_fee: Function = .{
    .name = "CREATOR_FEE",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const creator_fee_selector = keccak.selector("CREATOR_FEE()");

pub const insurance_fee: Function = .{
    .name = "INSURANCE_FEE",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const insurance_fee_selector = keccak.selector("INSURANCE_FEE()");

pub const lp_fee: Function = .{
    .name = "LP_FEE",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const lp_fee_selector = keccak.selector("LP_FEE()");

pub const liquidation_fee: Function = .{
    .name = "LIQUIDATION_FEE",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const liquidation_fee_selector = keccak.selector("LIQUIDATION_FEE()");
