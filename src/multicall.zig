//! On-chain Multicall3 `aggregate3` support: bundle many contract reads into a
//! single `eth_call` that executes atomically at one block. Unlike JSON-RPC
//! batching (`callBatch`), every read here observes the same block state, which
//! is what a bot wants when snapshotting many positions' solvency at once.
//!
//! The encoder is self-contained; decoding + the `Call3`/`Result` shapes are
//! reused from eth.zig. Route the encoded call through the `ChainClient` seam's
//! `call` (see `context.multicall3`) so it stays mockable.

const std = @import("std");
const eth = @import("eth");

/// One call in an aggregate3 batch: target, its calldata, and whether a revert
/// of this individual call is tolerated (`allow_failure`) vs. reverting the
/// whole aggregate.
pub const Call3 = eth.multicall.Call3;

/// One result, index-aligned with the input calls: `success` plus `return_data`
/// (owned; free the whole slice with `freeResults`).
pub const Result = eth.multicall.Result;

/// `aggregate3((address,bool,bytes)[])` selector (0x82ad56cb).
pub const AGGREGATE3_SELECTOR = eth.multicall.AGGREGATE3_SELECTOR;

/// Decode an aggregate3 return payload into `[]Result`. Reused from eth.zig.
pub const decodeResults = eth.multicall.decodeAggregate3Results;

/// Free a `[]Result`. Reused from eth.zig.
pub const freeResults = eth.multicall.freeResults;

/// The canonical Multicall3 deployment. It is CREATE2-deployed at the same
/// address on every supported chain, including Arbitrum One and Sepolia.
pub const MULTICALL3_ADDRESS: [20]u8 = .{
    0xcA, 0x11, 0xbd, 0xe0, 0x59, 0x77, 0xb3, 0x63, 0x11, 0x67,
    0x02, 0x88, 0x62, 0xbE, 0x2a, 0x17, 0x39, 0x76, 0xCA, 0x11,
};

fn appendWord(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), value: usize) !void {
    var word: [32]u8 = @splat(0);
    std.mem.writeInt(u256, &word, @as(u256, value), .big);
    try buf.appendSlice(allocator, &word);
}

fn padTo32(len: usize) usize {
    if (len == 0) return 0;
    return ((len + 31) / 32) * 32;
}

/// ABI-encode an `aggregate3((address,bool,bytes)[])` call for `calls`. The
/// argument is a dynamic array of `(address, bool, bytes)` tuples; the layout is
/// selector + head (array offset, length, one offset per tuple) + each tuple
/// body (address, allowFailure, bytes-offset, bytes-length, padded bytes).
/// Caller owns the returned slice.
pub fn encodeAggregate3(allocator: std.mem.Allocator, calls: []const Call3) ![]u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, &AGGREGATE3_SELECTOR);
    try appendWord(allocator, &buf, 0x20); // offset to the array data
    try appendWord(allocator, &buf, calls.len); // array length

    // Each tuple body is a fixed 4 words (address, bool, bytes-offset,
    // bytes-length) plus the 32-padded calldata.
    const n = calls.len;
    var offset: usize = n * 32; // tuple offsets are relative to end of the offset section
    for (calls) |c| {
        try appendWord(allocator, &buf, offset);
        offset += 32 * 4 + padTo32(c.call_data.len);
    }

    for (calls) |c| {
        var addr_word: [32]u8 = @splat(0);
        @memcpy(addr_word[12..32], &c.target);
        try buf.appendSlice(allocator, &addr_word);
        try appendWord(allocator, &buf, if (c.allow_failure) @as(usize, 1) else 0);
        try appendWord(allocator, &buf, 0x60); // bytes data sits 3 words into the tuple
        try appendWord(allocator, &buf, c.call_data.len);
        try buf.appendSlice(allocator, c.call_data);
        try buf.appendNTimes(allocator, 0, padTo32(c.call_data.len) - c.call_data.len);
    }

    return buf.toOwnedSlice(allocator);
}
