const std = @import("std");
const sdk = @import("perpcity_sdk");
const eth = @import("eth");

const revert = sdk.revert;
const Revert = revert.Revert;
const ContractError = revert.ContractError;
const RetryHint = revert.RetryHint;

// ABI-encode a `Name()` custom-error revert: just the 4-byte selector.
fn selectorBytes(comptime sig: []const u8) [4]u8 {
    return eth.keccak.selector(sig);
}

test "decode maps known custom-error selectors to typed variants" {
    // NotLiquidatable() -> the canonical liquidation skip signal.
    {
        const data = selectorBytes("NotLiquidatable()");
        const r = revert.decode(&data);
        try std.testing.expectEqual(Revert{ .contract_error = .not_liquidatable }, r);
    }
    // InsufficientLiquidityToFill() -> retry with a smaller size.
    {
        const data = selectorBytes("InsufficientLiquidityToFill()");
        const r = revert.decode(&data);
        try std.testing.expectEqual(Revert{ .contract_error = .insufficient_liquidity_to_fill }, r);
    }
    // HealthNotImproved() -> present here though the Rust decoder omits it.
    {
        const data = selectorBytes("HealthNotImproved()");
        try std.testing.expectEqual(Revert{ .contract_error = .health_not_improved }, revert.decode(&data));
    }
    // PositionDoesNotExist().
    {
        const data = selectorBytes("PositionDoesNotExist()");
        try std.testing.expectEqual(Revert{ .contract_error = .position_does_not_exist }, revert.decode(&data));
    }
}

test "Solady SafeTransferLib selectors match their canonical 4-byte values" {
    // These are the well-known Solady selectors; matching them proves the
    // comptime keccak table lines up with the on-wire values.
    try std.testing.expectEqualSlices(u8, &.{ 0x79, 0x39, 0xf4, 0x24 }, &selectorBytes("TransferFromFailed()"));
    try std.testing.expectEqualSlices(u8, &.{ 0x90, 0xb8, 0xec, 0x18 }, &selectorBytes("TransferFailed()"));
    try std.testing.expectEqualSlices(u8, &.{ 0x3e, 0x3f, 0x8f, 0x73 }, &selectorBytes("ApproveFailed()"));
    try std.testing.expectEqualSlices(u8, &.{ 0xb1, 0x2d, 0x13, 0xeb }, &selectorBytes("ETHTransferFailed()"));

    const data = selectorBytes("TransferFromFailed()");
    try std.testing.expectEqual(Revert{ .contract_error = .transfer_from_failed }, revert.decode(&data));
}

test "decode extracts an Error(string) reason without allocating" {
    const allocator = std.testing.allocator;
    // Error(string) = 0x08c379a0 + offset(0x20) + len + bytes(padded to 32).
    const msg = "boom";
    var data: std.ArrayList(u8) = .empty;
    defer data.deinit(allocator);
    try data.appendSlice(allocator, &.{ 0x08, 0xc3, 0x79, 0xa0 });
    try data.appendSlice(allocator, &([_]u8{0} ** 31 ++ [_]u8{0x20})); // offset = 32
    try data.appendSlice(allocator, &([_]u8{0} ** 31 ++ [_]u8{msg.len})); // length = 4
    try data.appendSlice(allocator, msg);
    try data.appendSlice(allocator, &([_]u8{0} ** (32 - msg.len))); // pad

    const r = revert.decode(data.items);
    switch (r) {
        .reason => |s| try std.testing.expectEqualStrings("boom", s),
        else => return error.TestUnexpectedResult,
    }

    // A non-canonical offset (not 0x20) must not decode to a bogus reason; it
    // falls through to unknown_selector rather than reading a wrong length.
    data.items[35] = 0x40; // offset = 64 instead of 32
    switch (revert.decode(data.items)) {
        .unknown_selector => {},
        else => return error.TestUnexpectedResult,
    }
}

test "decode reads a Panic(uint256) code" {
    // Panic(uint256) = 0x4e487b71 + 32-byte code; 0x11 = arithmetic overflow.
    var data: [36]u8 = undefined;
    @memcpy(data[0..4], &[_]u8{ 0x4e, 0x48, 0x7b, 0x71 });
    @memset(data[4..36], 0);
    data[35] = 0x11;
    const r = revert.decode(&data);
    try std.testing.expectEqual(Revert{ .panic = 0x11 }, r);
}

test "decode classifies empty and unknown revert data" {
    try std.testing.expectEqual(Revert.empty, revert.decode(&.{}));
    try std.testing.expectEqual(Revert.empty, revert.decode(&.{ 0x01, 0x02 })); // < 4 bytes

    const unknown = [_]u8{ 0xde, 0xad, 0xbe, 0xef };
    switch (revert.decode(&unknown)) {
        .unknown_selector => |s| try std.testing.expectEqualSlices(u8, &unknown, &s),
        else => return error.TestUnexpectedResult,
    }
}

test "fromHex decodes a node error.data hex string (with and without 0x)" {
    var buf: [64]u8 = undefined;
    // NotLiquidatable() selector as the node would return it under error.data.
    const sel = selectorBytes("NotLiquidatable()");
    var hex_buf: [10]u8 = undefined; // "0x" + 8 hex chars
    const hex = try std.fmt.bufPrint(&hex_buf, "0x{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ sel[0], sel[1], sel[2], sel[3] });

    try std.testing.expectEqual(Revert{ .contract_error = .not_liquidatable }, try revert.fromHex(&buf, hex));
    // Same, without the 0x prefix.
    try std.testing.expectEqual(Revert{ .contract_error = .not_liquidatable }, try revert.fromHex(&buf, hex[2..]));
}

test "retryHint drives liquidation-bot branching" {
    try std.testing.expectEqual(RetryHint.skip, revert.retryHint(.{ .contract_error = .not_liquidatable }));
    try std.testing.expectEqual(RetryHint.skip, revert.retryHint(.{ .contract_error = .position_does_not_exist }));
    try std.testing.expectEqual(RetryHint.skip, revert.retryHint(.{ .contract_error = .non_taker_position }));
    try std.testing.expectEqual(RetryHint.retry_smaller, revert.retryHint(.{ .contract_error = .insufficient_liquidity_to_fill }));
    try std.testing.expectEqual(RetryHint.retry, revert.retryHint(.{ .contract_error = .price_impact_too_high }));
    try std.testing.expectEqual(RetryHint.fatal, revert.retryHint(.{ .contract_error = .margin_too_low }));
    try std.testing.expectEqual(RetryHint.retry, revert.retryHint(.empty));
    try std.testing.expectEqual(RetryHint.fatal, revert.retryHint(.{ .panic = 0x11 }));

    try std.testing.expect(revert.isSkip(.{ .contract_error = .not_liquidatable }));
    try std.testing.expect(!revert.isSkip(.{ .contract_error = .insufficient_liquidity_to_fill }));
}
