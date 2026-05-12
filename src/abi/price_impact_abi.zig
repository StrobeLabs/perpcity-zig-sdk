const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

// IPriceImpact v0.1.0:
// function sqrtPriceBounds(uint256 ammPrice, uint256 index, uint256 emaAmmPrice, uint256 emaIndex)
//     external view returns (uint256 sqrtMin, uint256 sqrtMax);
pub const sqrt_price_bounds: Function = .{
    .name = "sqrtPriceBounds",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "ammPrice", .abi_type = .uint256 },
        .{ .name = "index", .abi_type = .uint256 },
        .{ .name = "emaAmmPrice", .abi_type = .uint256 },
        .{ .name = "emaIndex", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "sqrtMin", .abi_type = .uint256 },
        .{ .name = "sqrtMax", .abi_type = .uint256 },
    },
};
pub const sqrt_price_bounds_selector = keccak.selector(
    "sqrtPriceBounds(uint256,uint256,uint256,uint256)",
);
