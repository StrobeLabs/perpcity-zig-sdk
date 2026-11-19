//! Shared builders for v1.0.0-shaped event logs used across the contract-layer
//! tests. Indexed parameters go in `topics[1..]` (a uint256 as its big-endian
//! word, an address left-padded to 32 bytes); everything else is ABI-encoded
//! into the log data.
const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const types = sdk.types;

pub const AbiValue = eth.abi_encode.AbiValue;
pub const Log = eth.receipt.Log;

pub fn addr(b: u8) types.Address {
    return @as([20]u8, @splat(b));
}

/// ABI-encode `values` as a log's `data` payload. Caller frees.
pub fn enc(values: []const AbiValue) ![]u8 {
    return eth.abi_encode.encodeValues(std.testing.allocator, values);
}

/// A uint256 as an indexed topic word.
pub fn topicU256(value: u256) [32]u8 {
    var word: [32]u8 = undefined;
    std.mem.writeInt(u256, &word, value, .big);
    return word;
}

/// An address as an indexed topic word (left-padded with zeros).
pub fn topicAddr(a: types.Address) [32]u8 {
    var word: [32]u8 = @splat(0);
    @memcpy(word[12..32], &a);
    return word;
}

/// Build a Log emitted by perp `0xBE` with the given topics and data. Both
/// slices are borrowed; `MockChainClient.setLogs` deep-copies them.
pub fn mkLog(topics: []const [32]u8, data: []const u8) Log {
    return .{
        .address = addr(0xBE),
        .topics = topics,
        .data = data,
        .block_number = 100,
        .transaction_hash = null,
        .transaction_index = null,
        .log_index = null,
        .block_hash = null,
        .removed = false,
    };
}

/// The three topics of a `(posId indexed, address indexed)` position event.
pub fn positionTopics(topic0: [32]u8, pos_id: u256, who: types.Address) [3][32]u8 {
    return .{ topic0, topicU256(pos_id), topicAddr(who) };
}

/// `TakerOpened` data with an all-zero SwapResult: margin, SwapResult(8),
/// lastCumlFundingX96.
pub fn takerOpenedData() ![]u8 {
    return enc(&(.{AbiValue{ .uint256 = 0 }} ++ zero_swap_result ++ .{AbiValue{ .int256 = 0 }}));
}

/// `MakerOpened` data, all zero: tickLower, tickUpper, liquidity, delta,
/// lastCumlFundingX96, MakerFunding(2).
pub fn makerOpenedData() ![]u8 {
    return enc(&.{
        .{ .int256 = 0 }, .{ .int256 = 0 }, .{ .uint256 = 0 }, .{ .int256 = 0 },
        .{ .int256 = 0 }, .{ .int256 = 0 }, .{ .int256 = 0 },
    });
}

/// `MakerAdjusted` / `MakerClosed` / `MakerConverted` data, all zero:
/// marginDelta, liquidityDelta, funding, lpFees, delta, margin, liquidity,
/// lastCumlFundingX96, MakerFunding(2).
pub fn makerLifecycleData() ![]u8 {
    return enc(&.{
        .{ .int256 = 0 },  .{ .int256 = 0 },  .{ .int256 = 0 }, .{ .uint256 = 0 }, .{ .int256 = 0 },
        .{ .uint256 = 0 }, .{ .uint256 = 0 }, .{ .int256 = 0 }, .{ .int256 = 0 },  .{ .int256 = 0 },
    });
}

/// An all-zero inline SwapResult (8 static words).
pub const zero_swap_result = [_]AbiValue{
    .{ .int256 = 0 },  .{ .uint256 = 0 }, .{ .int256 = 0 },  .{ .uint256 = 0 },
    .{ .uint256 = 0 }, .{ .uint256 = 0 }, .{ .uint256 = 0 }, .{ .uint256 = 0 },
};
