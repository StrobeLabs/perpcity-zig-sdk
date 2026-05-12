const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

// IPricing v0.1.0:
// function fairPrice(uint256 ammPrice, uint256 index, uint256 emaAmmPrice, uint256 emaIndex)
//     external view returns (uint256);
pub const fair_price: Function = .{
    .name = "fairPrice",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "ammPrice", .abi_type = .uint256 },
        .{ .name = "index", .abi_type = .uint256 },
        .{ .name = "emaAmmPrice", .abi_type = .uint256 },
        .{ .name = "emaIndex", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const fair_price_selector = keccak.selector("fairPrice(uint256,uint256,uint256,uint256)");
