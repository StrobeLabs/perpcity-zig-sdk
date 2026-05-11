const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

// IFees v0.1.0 surface (perpcity-contracts).

pub const fees: Function = .{
    .name = "fees",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "cFee", .abi_type = .uint24 },
        .{ .name = "insFee", .abi_type = .uint24 },
        .{ .name = "lpFee", .abi_type = .uint24 },
    },
};
pub const fees_selector = keccak.selector("fees()");

pub const util_fees: Function = .{
    .name = "utilFees",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "longUtilization", .abi_type = .uint256 },
        .{ .name = "shortUtilization", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "longFee", .abi_type = .uint64 },
        .{ .name = "shortFee", .abi_type = .uint64 },
    },
};
pub const util_fees_selector = keccak.selector("utilFees(uint256,uint256)");

pub const liq_fee: Function = .{
    .name = "liqFee",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint24 },
    },
};
pub const liq_fee_selector = keccak.selector("liqFee()");
