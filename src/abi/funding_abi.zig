const eth = @import("eth");
const Function = eth.abi_types.Function;
const AbiParam = eth.abi_types.AbiParam;
const keccak = eth.keccak;

const price_pair_components = [_]AbiParam{
    .{ .name = "ammPrice", .abi_type = .uint128 },
    .{ .name = "index", .abi_type = .uint128 },
};

// IFunding v1.0.0:
// function funding(PricePair calldata spots, PricePair calldata emas, uint256 markPrice)
//     external view returns (int88);
pub const funding: Function = .{
    .name = "funding",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "spots", .abi_type = .tuple, .components = &price_pair_components },
        .{ .name = "emas", .abi_type = .tuple, .components = &price_pair_components },
        .{ .name = "markPrice", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .int88 },
    },
};
pub const funding_selector = keccak.selector("funding((uint128,uint128),(uint128,uint128),uint256)");
