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
/// without a network or Anvil. Reads are answered from a canned table of ABI
/// return bytes; writes are recorded for assertions.
///
/// Read resolution checks the full-calldata table first, then falls back to the
/// 4-byte selector table. The selector table is enough when a call's arguments
/// don't change the answer; the calldata table lets a test return distinct
/// results for the same function called with different arguments (e.g. per-id
/// `ownerOf`).
pub const MockChainClient = struct {
    allocator: std.mem.Allocator,
    /// Maps a 4-byte selector (first 4 bytes of the calldata) to owned canned
    /// raw ABI return bytes.
    responses: std.AutoHashMap([4]u8, []u8),
    /// Maps full calldata (selector + encoded args) to owned canned raw ABI
    /// return bytes. Checked before `responses`, so it overrides the
    /// selector-level answer for a specific argument set. Keys and values are
    /// owned by the mock and freed on `deinit`.
    responses_by_calldata: std.StringHashMap([]u8),
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
    /// The `from` passed to the most recent `simulate`, for assertions that the
    /// preflight ran from the caller's wallet (not address(0)). Null until the
    /// first `simulate`.
    last_simulate_from: ?[20]u8 = null,
    /// Canned logs returned by every `getLogs` (the filter is ignored). Set via
    /// `setLogs`; the mock owns this deep copy and frees it on `deinit`. Null
    /// (the default) makes `getLogs` return an empty slice.
    logs: ?[]eth.receipt.Log = null,
    /// Selector-keyed canned revert payloads for `callRaw`. A selector present
    /// here makes `callRaw` return `.reverted` with these bytes; owned by the
    /// mock, freed on `deinit`. Set via `setRevert`.
    reverts: std.AutoHashMap([4]u8, []u8),
    /// True iff the most recent `callRaw` was passed a non-null `overrides`, so
    /// tests can assert the state-override path was taken.
    last_callraw_had_overrides: bool = false,

    pub const MockError = error{NoMockResponse};

    pub fn init(allocator: std.mem.Allocator) MockChainClient {
        return .{
            .allocator = allocator,
            .responses = std.AutoHashMap([4]u8, []u8).init(allocator),
            .responses_by_calldata = std.StringHashMap([]u8).init(allocator),
            .reverts = std.AutoHashMap([4]u8, []u8).init(allocator),
            .sent = .empty,
        };
    }

    pub fn deinit(self: *MockChainClient) void {
        var it = self.responses.valueIterator();
        while (it.next()) |v| {
            self.allocator.free(v.*);
        }
        self.responses.deinit();

        var cit = self.responses_by_calldata.iterator();
        while (cit.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            self.allocator.free(e.value_ptr.*);
        }
        self.responses_by_calldata.deinit();

        var rit = self.reverts.valueIterator();
        while (rit.next()) |v| self.allocator.free(v.*);
        self.reverts.deinit();

        for (self.sent.items) |tx| {
            self.allocator.free(tx.data);
        }
        self.sent.deinit(self.allocator);

        if (self.receipt) |r| freeReceipt(self.allocator, r);

        if (self.logs) |ls| eth.log_watcher.freeLogs(self.allocator, ls);
    }

    /// Supply the canned receipt returned by `getReceipt`. The mock takes
    /// ownership of the receipt's allocated slices (logs/topics/data, e.g. one
    /// built with `makeOpenReceipt`) and frees them on `deinit`. Replacing a
    /// previously set receipt frees the old one first.
    pub fn setReceipt(self: *MockChainClient, receipt: eth.receipt.TransactionReceipt) void {
        if (self.receipt) |old| freeReceipt(self.allocator, old);
        self.receipt = receipt;
    }

    /// Supply the canned logs returned by `getLogs`. The mock deep-copies the
    /// logs (topics/data) into its own memory and frees them on `deinit`.
    /// Replacing a previously set set of logs frees the old copy first.
    pub fn setLogs(self: *MockChainClient, logs: []const eth.receipt.Log) !void {
        const copy = try dupeLogs(self.allocator, logs);
        if (self.logs) |old| eth.log_watcher.freeLogs(self.allocator, old);
        self.logs = copy;
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

    /// Register the raw ABI return bytes for an exact calldata (selector +
    /// encoded args). Takes precedence over the selector-level table, so a test
    /// can return different results for the same function called with different
    /// arguments. Both the calldata key and the return bytes are duped and owned
    /// by the mock; replacing an existing entry frees the old return bytes.
    pub fn setResponseCalldata(self: *MockChainClient, calldata: []const u8, raw_bytes: []const u8) !void {
        const val_copy = try self.allocator.dupe(u8, raw_bytes);
        errdefer self.allocator.free(val_copy);

        // Replace the value in place when the calldata is already registered,
        // reusing the owned key.
        if (self.responses_by_calldata.getPtr(calldata)) |value_ptr| {
            self.allocator.free(value_ptr.*);
            value_ptr.* = val_copy;
            return;
        }

        // New entry: own a copy of the calldata as the key.
        const key_copy = try self.allocator.dupe(u8, calldata);
        errdefer self.allocator.free(key_copy);
        try self.responses_by_calldata.put(key_copy, val_copy);
    }

    /// Register a canned revert payload for a selector: `callRaw` on calldata
    /// with this selector returns `.reverted` carrying these bytes (e.g. a
    /// 4-byte custom-error selector). The bytes are duped and owned by the mock;
    /// replacing an existing entry frees the old copy.
    pub fn setRevert(self: *MockChainClient, selector: [4]u8, raw_bytes: []const u8) !void {
        const copy = try self.allocator.dupe(u8, raw_bytes);
        errdefer self.allocator.free(copy);
        const gop = try self.reverts.getOrPut(selector);
        if (gop.found_existing) self.allocator.free(gop.value_ptr.*);
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
        .simulate = mockSimulate,
        .getLogs = mockGetLogs,
        .callRaw = mockCallRaw,
    };

    fn mockCall(ptr: *anyopaque, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) anyerror![]u8 {
        _ = to;
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        if (data.len < 4) return MockError.NoMockResponse;
        // Exact-calldata match wins over the selector-level fallback.
        if (self.responses_by_calldata.get(data)) |stored| {
            return allocator.dupe(u8, stored);
        }
        const sel: [4]u8 = data[0..4].*;
        const stored = self.responses.get(sel) orelse return MockError.NoMockResponse;
        // Return a fresh copy owned by the caller's allocator, matching the eth
        // path where the read helper frees the response.
        return allocator.dupe(u8, stored);
    }

    fn mockCallRaw(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        to: [20]u8,
        data: []const u8,
        from: ?[20]u8,
        overrides: ?*const eth.state_overrides.StateOverrides,
    ) anyerror!ChainClient.CallOutcome {
        _ = to;
        _ = from;
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        self.last_callraw_had_overrides = overrides != null;
        if (data.len < 4) return .{ .reverted = try allocator.alloc(u8, 0) };
        const sel: [4]u8 = data[0..4].*;
        // A registered revert wins, then a registered ok response (calldata-keyed
        // first, then selector). Nothing registered => a bare revert, no data.
        if (self.reverts.get(sel)) |rb| return .{ .reverted = try allocator.dupe(u8, rb) };
        if (self.responses_by_calldata.get(data)) |ok| return .{ .ok = try allocator.dupe(u8, ok) };
        if (self.responses.get(sel)) |ok| return .{ .ok = try allocator.dupe(u8, ok) };
        return .{ .reverted = try allocator.alloc(u8, 0) };
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
                // Exact-calldata match wins over the selector-level fallback; a
                // miss in both mirrors a reverting call (success=false).
                if (self.responses_by_calldata.get(c.data)) |stored| {
                    out[i] = .{ .success = true, .bytes = try allocator.dupe(u8, stored) };
                } else if (self.responses.get(c.data[0..4].*)) |stored| {
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

    fn mockGetLogs(ptr: *anyopaque, allocator: std.mem.Allocator, filter: eth.json_rpc.LogFilter) anyerror![]eth.receipt.Log {
        // The filter is ignored: the mock returns a fresh deep copy of the
        // caller-set canned logs (or an empty slice if none were set), owned by
        // the caller's allocator and freed via `chain_client.freeLogs`.
        _ = filter;
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        const src = self.logs orelse return allocator.alloc(eth.receipt.Log, 0);
        return dupeLogs(allocator, src);
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

    fn mockSimulate(ptr: *anyopaque, to: [20]u8, data: []const u8, from: [20]u8) anyerror!void {
        _ = to;
        const self: *MockChainClient = @ptrCast(@alignCast(ptr));
        // Record the caller-supplied `from` so tests can assert the preflight
        // ran from a real wallet, not address(0).
        self.last_simulate_from = from;
        if (data.len < 4) return MockError.NoMockResponse;
        const sel: [4]u8 = data[0..4].*;
        // Same selector table as `call`: a registered response stands in for a
        // call that would NOT revert; a missing one stands in for a revert.
        _ = self.responses.get(sel) orelse return MockError.NoMockResponse;
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

/// Deep-copy a slice of logs (including each log's `topics` and `data`) with
/// `allocator`. The copy mirrors eth.zig's own allocation discipline (`data`
/// always allocated, `topics` allocated only when non-empty), so it frees
/// cleanly with `eth.log_watcher.freeLogs` / `chain_client.freeLogs`.
fn dupeLogs(allocator: std.mem.Allocator, logs: []const eth.receipt.Log) ![]eth.receipt.Log {
    const out = try allocator.alloc(eth.receipt.Log, logs.len);
    var filled: usize = 0;
    errdefer {
        for (out[0..filled]) |l| {
            allocator.free(l.data);
            if (l.topics.len > 0) allocator.free(l.topics);
        }
        allocator.free(out);
    }

    for (logs, 0..) |src, i| {
        const topics: []const [32]u8 = if (src.topics.len > 0)
            try allocator.dupe([32]u8, src.topics)
        else
            &.{};
        errdefer if (topics.len > 0) allocator.free(topics);

        const data = try allocator.dupe(u8, src.data);

        out[i] = .{
            .address = src.address,
            .topics = topics,
            .data = data,
            .block_number = src.block_number,
            .transaction_hash = src.transaction_hash,
            .transaction_index = src.transaction_index,
            .log_index = src.log_index,
            .block_hash = src.block_hash,
            .removed = src.removed,
        };
        filled = i + 1;
    }

    return out;
}

/// Free the slices owned by a receipt built with `makeOpenReceipt`.
pub fn freeReceipt(allocator: std.mem.Allocator, receipt: eth.receipt.TransactionReceipt) void {
    for (receipt.logs) |log| {
        allocator.free(log.topics);
        allocator.free(log.data);
    }
    allocator.free(receipt.logs);
}
