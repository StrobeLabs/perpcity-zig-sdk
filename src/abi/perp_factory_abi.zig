const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

// IPerpFactory surface of perpcity-contracts v1.0.0.

// `struct Modules`: { beacon, fees, funding, marginRatios, priceImpact, pricing }.
const modules_components = [_]AbiParam{
    .{ .name = "beacon", .abi_type = .address },
    .{ .name = "fees", .abi_type = .address },
    .{ .name = "funding", .abi_type = .address },
    .{ .name = "marginRatios", .abi_type = .address },
    .{ .name = "priceImpact", .abi_type = .address },
    .{ .name = "pricing", .abi_type = .address },
};

// `struct WithdrawalConfig`: { capacity, refillPerSecond, challengeWindow }.
const withdrawal_config_components = [_]AbiParam{
    .{ .name = "capacity", .abi_type = .uint128 },
    .{ .name = "refillPerSecond", .abi_type = .uint128 },
    .{ .name = "challengeWindow", .abi_type = .uint48 },
};

pub const create_perp: Function = .{
    .name = "createPerp",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "owner", .abi_type = .address },
        .{ .name = "governor", .abi_type = .address },
        .{ .name = "modules", .abi_type = .tuple, .components = &modules_components },
        .{ .name = "emaWindow", .abi_type = .uint24 },
        .{ .name = "latency", .abi_type = .uint32 },
        .{ .name = "salt", .abi_type = .bytes32 },
        .{ .name = "withdrawalConfig", .abi_type = .tuple, .components = &withdrawal_config_components },
    },
    .outputs = &.{
        .{ .name = "perp", .abi_type = .address },
    },
};
pub const create_perp_selector = keccak.selector(
    "createPerp(address,address,(address,address,address,address,address,address),uint24,uint32,bytes32,(uint128,uint128,uint48))",
);

/// The Perp implementation that newly created market proxies point at.
pub const perp_implementation: Function = .{
    .name = "perpImplementation",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .address },
    },
};
pub const perp_implementation_selector = keccak.selector("perpImplementation()");

// event PerpCreated(
//     address perp,
//     PoolId poolId,           // bytes32
//     Modules modules,         // tuple (address x6)
//     uint256 initialIndex,
//     uint24 emaWindow,
//     uint32 latency,
//     uint256 protocolFee,
//     uint160 sqrtPriceX96,
//     int24 tick,
//     address owner
// );
// None of the params are indexed.
pub const perp_created_event: Event = .{
    .name = "PerpCreated",
    .inputs = &.{
        .{ .name = "perp", .abi_type = .address },
        .{ .name = "poolId", .abi_type = .bytes32 },
        .{ .name = "modules", .abi_type = .tuple, .components = &modules_components },
        .{ .name = "initialIndex", .abi_type = .uint256 },
        .{ .name = "emaWindow", .abi_type = .uint24 },
        .{ .name = "latency", .abi_type = .uint32 },
        .{ .name = "protocolFee", .abi_type = .uint256 },
        .{ .name = "sqrtPriceX96", .abi_type = .uint160 },
        .{ .name = "tick", .abi_type = .int24 },
        .{ .name = "owner", .abi_type = .address },
    },
};
pub const perp_created_topic = blk: {
    @setEvalBranchQuota(50_000);
    break :blk keccak.hash(
        "PerpCreated(address,bytes32,(address,address,address,address,address,address),uint256,uint24,uint32,uint256,uint160,int24,address)",
    );
};
