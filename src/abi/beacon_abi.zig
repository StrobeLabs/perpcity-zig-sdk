const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

pub const index: Function = .{
    .name = "index",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const index_selector = keccak.selector("index()");

pub const tw_avg: Function = .{
    .name = "twAvg",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "secondsAgo", .abi_type = .uint32 },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const tw_avg_selector = keccak.selector("twAvg(uint32)");
