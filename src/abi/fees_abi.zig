const eth = @import("eth");
const Function = eth.abi_types.Function;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

// IFees surface of perpcity-contracts v1.0.0.

const price_pair_components = [_]AbiParam{
    .{ .name = "ammPrice", .abi_type = .uint128 },
    .{ .name = "index", .abi_type = .uint128 },
};

/// Swap-fee rates (scaled by 1e6) for one constant-liquidity swap segment. The
/// LP fee is dynamic: it depends on the active `liquidity` and on how far the
/// spot AMM price sits from its EMA.
pub const fees: Function = .{
    .name = "fees",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "liquidity", .abi_type = .uint128 },
        .{ .name = "spots", .abi_type = .tuple, .components = &price_pair_components },
        .{ .name = "emas", .abi_type = .tuple, .components = &price_pair_components },
    },
    .outputs = &.{
        .{ .name = "cFee", .abi_type = .uint24 },
        .{ .name = "insFee", .abi_type = .uint24 },
        .{ .name = "lpFee", .abi_type = .uint24 },
    },
};
pub const fees_selector = keccak.selector("fees(uint128,(uint128,uint128),(uint128,uint128))");

/// Upper bound on the aggregate swap-fee rate (creator + insurance + maximum LP
/// fee), scaled by 1e6.
pub const max_swap_fee: Function = .{
    .name = "maxSwapFee",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "rateE6", .abi_type = .uint256 },
    },
};
pub const max_swap_fee_selector = keccak.selector("maxSwapFee()");

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
