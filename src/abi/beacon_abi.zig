const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

// IBeacon surface of beacons v1.0.0, the release perpcity-contracts v1.0.0 pins.

/// The latest observation: the Q96 index and the block timestamp (seconds) at
/// which it was written. Markets reject an observation older than their
/// `latency`.
pub const index: Function = .{
    .name = "index",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "index", .abi_type = .uint256 },
        .{ .name = "updatedAt", .abi_type = .uint256 },
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
