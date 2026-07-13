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
        // Write-path receipt scanning is out of scope for the read-path unit
        // tests; a null receipt keeps the interface honest without requiring
        // fabricated logs.
        _ = ptr;
        _ = allocator;
        _ = tx_hash;
        _ = max_attempts;
        return null;
    }

    fn mockAddress(ptr: *anyopaque) anyerror![20]u8 {
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        return self.mock_addr;
    }
};
