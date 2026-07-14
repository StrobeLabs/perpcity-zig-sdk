const std = @import("std");
const eth = @import("eth");
const chain_client = @import("../chain_client.zig");

const ChainClient = chain_client.ChainClient;

/// A transaction recorded by the mock for later assertions.
pub const SentTx = struct {
    to: [20]u8,
    /// Owned copy of the calldata (freed on `deinit`).
    data: []u8,
    value: u256,
};

/// Deterministic, in-memory `ChainClient` for unit-testing the contract layer
/// without a network or Anvil. Reads are answered from a selector-keyed table
/// of canned ABI return bytes; writes are recorded for assertions.
pub const MockChainClient = struct {
    allocator: std.mem.Allocator,
    /// Maps a 4-byte selector (first 4 bytes of the calldata) to owned canned
    /// raw ABI return bytes.
    responses: std.AutoHashMap([4]u8, []u8),
    /// Records every `sendTransaction` for assertions.
    sent: std.ArrayList(SentTx),
    /// Address returned by `address()`.
    mock_addr: [20]u8 = [_]u8{0xAB} ** 20,
    /// Hash returned by every `sendTransaction`.
    next_hash: [32]u8 = [_]u8{0xCD} ** 32,
    /// Canned receipt returned by `getReceipt`. Null (the default) makes
    /// `getReceipt` return null, matching an unmined transaction. Set via
    /// `setReceipt`; the mock owns and frees it (and any receipt it replaces)
    /// so tests built through `makeOpenReceipt` stay leak-clean.
    receipt: ?eth.receipt.TransactionReceipt = null,

    pub const MockError = error{NoMockResponse};

    pub fn init(allocator: std.mem.Allocator) MockChainClient {
        return .{
            .allocator = allocator,
            .responses = std.AutoHashMap([4]u8, []u8).init(allocator),
            .sent = .empty,
        };
    }

    pub fn deinit(self: *MockChainClient) void {
        var it = self.responses.valueIterator();
        while (it.next()) |v| {
            self.allocator.free(v.*);
        }
        self.responses.deinit();

        for (self.sent.items) |tx| {
            self.allocator.free(tx.data);
        }
        self.sent.deinit(self.allocator);

        if (self.receipt) |r| freeReceipt(self.allocator, r);
    }

    /// Supply the canned receipt returned by `getReceipt`. The mock takes
    /// ownership of the receipt's allocated slices (logs/topics/data, e.g. one
    /// built with `makeOpenReceipt`) and frees them on `deinit`. Replacing a
    /// previously set receipt frees the old one first.
    pub fn setReceipt(self: *MockChainClient, receipt: eth.receipt.TransactionReceipt) void {
        if (self.receipt) |old| freeReceipt(self.allocator, old);
        self.receipt = receipt;
    }

    /// Convenience accessor for the most recently recorded `sendTransaction`.
    /// Returns null when nothing has been sent.
    pub fn lastSent(self: *MockChainClient) ?SentTx {
        if (self.sent.items.len == 0) return null;
        return self.sent.items[self.sent.items.len - 1];
    }

    /// Register the raw ABI return bytes for a selector. The bytes are duped
    /// and owned by the mock. Replacing an existing entry frees the old copy.
    pub fn setResponse(self: *MockChainClient, selector: [4]u8, raw_bytes: []const u8) !void {
        const copy = try self.allocator.dupe(u8, raw_bytes);
        errdefer self.allocator.free(copy);
        const gop = try self.responses.getOrPut(selector);
        if (gop.found_existing) {
            self.allocator.free(gop.value_ptr.*);
        }
        gop.value_ptr.* = copy;
    }

    /// Convenience wrapper over `setResponse` that decodes a hex string (with
    /// or without a `0x` prefix) into bytes first.
    pub fn setResponseHex(self: *MockChainClient, selector: [4]u8, hex: []const u8) !void {
        const src = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
            hex[2..]
        else
            hex;
        const bytes = try self.allocator.alloc(u8, src.len / 2);
        defer self.allocator.free(bytes);
        _ = try eth.hex.hexToBytes(bytes, src);
        try self.setResponse(selector, bytes);
    }

    /// Return a `ChainClient` view over this mock. The `ptr` is `self`, so the
    /// mock must outlive any `ChainClient`/`PerpCityContext` built from it.
    pub fn client(self: *MockChainClient) ChainClient {
        return .{ .ptr = self, .vtable = &mock_vtable };
    }

    const mock_vtable = ChainClient.VTable{
        .call = mockCall,
        .sendTransaction = mockSendTransaction,
        .getReceipt = mockGetReceipt,
        .address = mockAddress,
        .callBatch = mockCallBatch,
    };

    fn mockCall(ptr: *anyopaque, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) anyerror![]u8 {
        _ = to;
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        if (data.len < 4) return MockError.NoMockResponse;
        const sel: [4]u8 = data[0..4].*;
        const stored = self.responses.get(sel) orelse return MockError.NoMockResponse;
        // Return a fresh copy owned by the caller's allocator, matching the eth
        // path where the read helper frees the response.
        return allocator.dupe(u8, stored);
    }

    fn mockCallBatch(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        calls: []const ChainClient.BatchCall,
    ) anyerror![]ChainClient.BatchResult {
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));

        const out = try allocator.alloc(ChainClient.BatchResult, calls.len);
        var filled: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < filled) : (i += 1) allocator.free(out[i].bytes);
            allocator.free(out);
        }

        for (calls, 0..) |c, i| {
            // Resolve each call by its 4-byte selector (same table as `call`).
            // A missing selector mirrors a failed on-chain call: success=false,
            // empty bytes.
            if (c.data.len >= 4) {
                const sel: [4]u8 = c.data[0..4].*;
                if (self.responses.get(sel)) |stored| {
                    out[i] = .{ .success = true, .bytes = try allocator.dupe(u8, stored) };
                } else {
                    out[i] = .{ .success = false, .bytes = try allocator.alloc(u8, 0) };
                }
            } else {
                out[i] = .{ .success = false, .bytes = try allocator.alloc(u8, 0) };
            }
            filled = i + 1;
        }
        return out;
    }

    fn mockSendTransaction(ptr: *anyopaque, to: [20]u8, data: []const u8, value: u256) anyerror![32]u8 {
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        const data_copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(data_copy);
        try self.sent.append(self.allocator, .{ .to = to, .data = data_copy, .value = value });
        return self.next_hash;
    }

    fn mockGetReceipt(ptr: *anyopaque, allocator: std.mem.Allocator, tx_hash: [32]u8, max_attempts: u32) anyerror!?eth.receipt.TransactionReceipt {
        // Returns the canned receipt (or null if none was set). The receipt is
        // a value with slices into mock-owned memory, so returning it by value
        // is safe as long as the mock outlives the caller.
        _ = allocator;
        _ = tx_hash;
        _ = max_attempts;
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        return self.receipt;
    }

    fn mockAddress(ptr: *anyopaque) anyerror![20]u8 {
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        return self.mock_addr;
    }
};

/// Build a canned success receipt (`status == 1`) carrying a single log emitted
/// by `emitter`, with `topic0` as its only topic and the 32-byte big-endian
/// `position_id` as its data. This is what the open/create wrappers scan to
/// decode a position or perp id. The receipt's slices are allocated with
/// `allocator`; free them with `freeReceipt` (or hand the receipt to
/// `MockChainClient.setReceipt`, which frees it on `deinit`).
pub fn makeOpenReceipt(
    allocator: std.mem.Allocator,
    emitter: [20]u8,
    topic0: [32]u8,
    position_id: u256,
) !eth.receipt.TransactionReceipt {
    const topics = try allocator.alloc([32]u8, 1);
    errdefer allocator.free(topics);
    topics[0] = topic0;

    const data = try allocator.alloc(u8, 32);
    errdefer allocator.free(data);
    var v = position_id;
    var i: usize = 32;
    while (i > 0) {
        i -= 1;
        data[i] = @truncate(v & 0xff);
        v >>= 8;
    }

    const logs = try allocator.alloc(eth.receipt.Log, 1);
    errdefer allocator.free(logs);
    logs[0] = .{
        .address = emitter,
        .topics = topics,
        .data = data,
        .block_number = 1,
        .transaction_hash = null,
        .transaction_index = null,
        .log_index = null,
        .block_hash = null,
        .removed = false,
    };

    return .{
        .transaction_hash = [_]u8{0xCD} ** 32,
        .block_hash = [_]u8{0} ** 32,
        .block_number = 1,
        .transaction_index = 0,
        .from = [_]u8{0} ** 20,
        .to = null,
        .gas_used = 0,
        .cumulative_gas_used = 0,
        .effective_gas_price = 0,
        .status = 1,
        .logs = logs,
        .contract_address = null,
        .type_ = 2,
    };
}

/// Free the slices owned by a receipt built with `makeOpenReceipt`.
pub fn freeReceipt(allocator: std.mem.Allocator, receipt: eth.receipt.TransactionReceipt) void {
    for (receipt.logs) |log| {
        allocator.free(log.topics);
        allocator.free(log.data);
    }
    allocator.free(receipt.logs);
}
