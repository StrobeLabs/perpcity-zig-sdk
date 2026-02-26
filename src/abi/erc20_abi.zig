const eth = @import("eth");
const Function = eth.abi_types.Function;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

pub const approve: Function = .{
    .name = "approve",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "spender", .abi_type = .address },
        .{ .name = "amount", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .bool },
    },
};
pub const approve_selector = keccak.comptimeSelector("approve(address,uint256)");

pub const balance_of: Function = .{
    .name = "balanceOf",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "account", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const balance_of_selector = keccak.comptimeSelector("balanceOf(address)");

pub const allowance: Function = .{
    .name = "allowance",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "owner", .abi_type = .address },
        .{ .name = "spender", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const allowance_selector = keccak.comptimeSelector("allowance(address,address)");
