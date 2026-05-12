const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

// Modules tuple matches `struct Modules` in perpcity-contracts v0.1.0
// SharedStructs.sol: { beacon, fees, funding, marginRatios, priceImpact, pricing }.
const modules_components = [_]AbiParam{
    .{ .name = "beacon", .abi_type = .address },
    .{ .name = "fees", .abi_type = .address },
    .{ .name = "funding", .abi_type = .address },
    .{ .name = "marginRatios", .abi_type = .address },
    .{ .name = "priceImpact", .abi_type = .address },
    .{ .name = "pricing", .abi_type = .address },
};

pub const create_perp: Function = .{
    .name = "createPerp",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "owner", .abi_type = .address },
        .{ .name = "name", .abi_type = .string },
        .{ .name = "symbol", .abi_type = .string },
        .{ .name = "tokenUri", .abi_type = .string },
        .{ .name = "modules", .abi_type = .tuple, .components = &modules_components },
        .{ .name = "emaWindow", .abi_type = .uint24 },
        .{ .name = "salt", .abi_type = .bytes32 },
    },
    .outputs = &.{
        .{ .name = "perp", .abi_type = .address },
    },
};
pub const create_perp_selector = keccak.selector(
    "createPerp(address,string,string,string,(address,address,address,address,address,address),uint24,bytes32)",
);

pub const perps: Function = .{
    .name = "perps",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "perp", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .bool },
    },
};
pub const perps_selector = keccak.selector("perps(address)");

// Event PerpCreated(
//     address perp,
//     PoolId poolId,           // bytes32 (typedef of bytes32)
//     Modules modules,         // tuple (address x6)
//     uint256 initialIndex,
//     uint24 emaWindow,
//     uint256 protocolFee,
//     uint160 sqrtPriceX96,
//     int24 tick,
//     address owner,
//     string name,
//     string symbol,
//     string tokenUri
// );
// None of the params are indexed at v0.1.0.
pub const perp_created_event: Event = .{
    .name = "PerpCreated",
    .inputs = &.{
        .{ .name = "perp", .abi_type = .address },
        .{ .name = "poolId", .abi_type = .bytes32 },
        .{ .name = "modules", .abi_type = .tuple, .components = &modules_components },
        .{ .name = "initialIndex", .abi_type = .uint256 },
        .{ .name = "emaWindow", .abi_type = .uint24 },
        .{ .name = "protocolFee", .abi_type = .uint256 },
        .{ .name = "sqrtPriceX96", .abi_type = .uint160 },
        .{ .name = "tick", .abi_type = .int24 },
        .{ .name = "owner", .abi_type = .address },
        .{ .name = "name", .abi_type = .string },
        .{ .name = "symbol", .abi_type = .string },
        .{ .name = "tokenUri", .abi_type = .string },
    },
};
pub const perp_created_topic = blk: {
    @setEvalBranchQuota(50_000);
    break :blk keccak.hash(
        "PerpCreated(address,bytes32,(address,address,address,address,address,address),uint256,uint24,uint256,uint160,int24,address,string,string,string)",
    );
};
