const std = @import("std");
const eth = @import("eth");

const AbiValue = eth.abi_encode.AbiValue;
const AbiType = eth.abi_types.AbiType;

/// Abstraction over the on-chain read/write surface the SDK's contract layer
/// needs. Decouples the contract wrappers from eth.zig's concrete
/// `Provider`/`Wallet` so the layer can be unit-tested with an in-memory mock
/// (no network / Anvil). The production implementation is `EthChainClient`
/// below; the test double is `testing/mock_chain_client.zig`.
pub const ChainClient = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    /// One read in a batched eth_call round-trip: a target and its calldata.
    pub const BatchCall = struct {
        to: [20]u8,
        data: []const u8,
    };

    /// Result of one entry in a `callBatch`, index-aligned with the input calls.
    /// `bytes` is owned by the caller (freed via `freeBatchResults`). A failed
    /// on-chain call yields `success == false` with an empty `bytes`.
    pub const BatchResult = struct {
        success: bool,
        bytes: []u8,
    };

    pub const VTable = struct {
        /// eth_call; returns the raw ABI return bytes. Caller owns the slice
        /// (freed with the passed allocator by the read helper).
        call: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) anyerror![]u8,
        /// Sign + broadcast a transaction; returns the transaction hash.
        sendTransaction: *const fn (ptr: *anyopaque, to: [20]u8, data: []const u8, value: u256) anyerror![32]u8,
        /// Fetch a receipt (null until mined). Caller owns per eth semantics.
        getReceipt: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, tx_hash: [32]u8, max_attempts: u32) anyerror!?eth.receipt.TransactionReceipt,
        /// Signer address.
        address: *const fn (ptr: *anyopaque) anyerror![20]u8,
        /// Batched eth_call: collapses many reads into a single JSON-RPC
        /// round-trip. Returns one `BatchResult` per input call, index-aligned;
        /// each `bytes` is duped with the passed allocator and owned by the
        /// caller (free the whole slice with `freeBatchResults`).
        callBatch: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, calls: []const BatchCall) anyerror![]BatchResult,
        /// From-aware revert preflight: run the tx from `from` without sending
        /// it. Returns normally if it would NOT revert; errors iff it would.
        /// `from` is load-bearing -- an eth_call from address(0) falsely reverts
        /// on sender-dependent writes (e.g. ERC20 approve from the zero address).
        simulate: *const fn (ptr: *anyopaque, to: [20]u8, data: []const u8, from: [20]u8) anyerror!void,
    };

    pub fn call(self: *ChainClient, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) ![]u8 {
        return self.vtable.call(self.ptr, allocator, to, data);
    }

    pub fn callBatch(self: *ChainClient, allocator: std.mem.Allocator, calls: []const BatchCall) ![]BatchResult {
        return self.vtable.callBatch(self.ptr, allocator, calls);
    }

    pub fn sendTransaction(self: *ChainClient, to: [20]u8, data: []const u8, value: u256) ![32]u8 {
        return self.vtable.sendTransaction(self.ptr, to, data, value);
    }

    pub fn getReceipt(self: *ChainClient, allocator: std.mem.Allocator, tx_hash: [32]u8, max_attempts: u32) !?eth.receipt.TransactionReceipt {
        return self.vtable.getReceipt(self.ptr, allocator, tx_hash, max_attempts);
    }

    pub fn address(self: *ChainClient) ![20]u8 {
        return self.vtable.address(self.ptr);
    }

    pub fn simulate(self: *ChainClient, to: [20]u8, data: []const u8, from: [20]u8) !void {
        return self.vtable.simulate(self.ptr, to, data, from);
    }
};

// ---------------------------------------------------------------------------
// Free helpers -- mirror eth.contract.contractRead/contractWrite but over the
// ChainClient interface instead of a concrete Provider/Wallet.
// ---------------------------------------------------------------------------

/// Read a contract function through the interface: encode calldata, eth_call,
/// decode the result. Caller must free the returned values with
/// `freeReturnValues`.
pub fn readContract(
    client: *ChainClient,
    allocator: std.mem.Allocator,
    to: [20]u8,
    sel: [4]u8,
    args: []const AbiValue,
    out_types: []const AbiType,
) ![]AbiValue {
    const calldata = try eth.abi_encode.encodeFunctionCall(allocator, sel, args);
    defer allocator.free(calldata);
    const response = try client.call(allocator, to, calldata);
    defer allocator.free(response);
    return try eth.abi_decode.decodeValues(response, out_types, allocator);
}

/// Write to a contract through the interface: encode calldata, send it as a
/// transaction. Returns the transaction hash.
pub fn writeContract(
    client: *ChainClient,
    allocator: std.mem.Allocator,
    to: [20]u8,
    sel: [4]u8,
    args: []const AbiValue,
    value: u256,
) ![32]u8 {
    const calldata = try eth.abi_encode.encodeFunctionCall(allocator, sel, args);
    defer allocator.free(calldata);
    return try client.sendTransaction(to, calldata, value);
}

/// Simulate a state-changing call from `from`: encode calldata, run the
/// from-aware preflight, discard the result. Returns normally if the call would
/// NOT revert; propagates the underlying error (an on-chain revert surfaces as
/// an error) otherwise.
///
/// This is the opt-in revert preflight: callers invoke it before a matching
/// `writeContract` when they want to learn a tx will revert without spending gas
/// or burning a nonce. It is never called implicitly on the write path. `from`
/// must be the caller's wallet address -- a from-less (address(0)) preflight
/// falsely reverts on any sender-dependent write.
pub fn simulateContract(
    client: *ChainClient,
    allocator: std.mem.Allocator,
    to: [20]u8,
    sel: [4]u8,
    args: []const AbiValue,
    from: [20]u8,
) !void {
    const calldata = try eth.abi_encode.encodeFunctionCall(allocator, sel, args);
    defer allocator.free(calldata);
    try client.simulate(to, calldata, from);
}

/// Free values returned by `readContract`.
pub fn freeReturnValues(values: []AbiValue, allocator: std.mem.Allocator) void {
    eth.abi_decode.freeValues(values, allocator);
}

/// Free the slice returned by `ChainClient.callBatch`, including each entry's
/// owned `bytes`. Empty (`success == false`) entries free cleanly too.
pub fn freeBatchResults(results: []ChainClient.BatchResult, allocator: std.mem.Allocator) void {
    for (results) |r| {
        allocator.free(r.bytes);
    }
    allocator.free(results);
}

// ---------------------------------------------------------------------------
// Production implementation
// ---------------------------------------------------------------------------

/// The production `ChainClient` backed by eth.zig. It OWNS the transport,
/// provider, and wallet on the heap so their addresses are stable regardless
/// of where the enclosing `PerpCityContext` is moved. This is what removes the
/// old `fixPointers` footgun: provider->transport and wallet->provider pointers
/// reference stable heap allocations, not fields inside a value-type struct.
pub const EthChainClient = struct {
    allocator: std.mem.Allocator,
    transport: *eth.http_transport.HttpTransport,
    provider: *eth.provider.Provider,
    wallet: *eth.wallet.Wallet,

    /// Allocate and wire the eth.zig objects on the heap. Returns the heap
    /// pointer -- keep it and hand out `ChainClient`s via `client()`.
    pub fn create(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        private_key: [32]u8,
    ) !*EthChainClient {
        const self = try allocator.create(EthChainClient);
        errdefer allocator.destroy(self);

        const transport = try allocator.create(eth.http_transport.HttpTransport);
        errdefer allocator.destroy(transport);
        transport.* = eth.http_transport.HttpTransport.init(allocator, rpc_url, eth.runtime.blockingIo());
        errdefer transport.deinit();

        const provider = try allocator.create(eth.provider.Provider);
        errdefer allocator.destroy(provider);
        provider.* = eth.provider.Provider.init(allocator, transport);

        const wallet = try allocator.create(eth.wallet.Wallet);
        errdefer allocator.destroy(wallet);
        wallet.* = eth.wallet.Wallet.initLocal(allocator, private_key, provider);

        self.* = .{
            .allocator = allocator,
            .transport = transport,
            .provider = provider,
            .wallet = wallet,
        };
        return self;
    }

    /// Tear down the wallet/transport and free every heap allocation, including
    /// `self`.
    pub fn destroy(self: *EthChainClient) void {
        self.wallet.deinit();
        self.transport.deinit();
        self.allocator.destroy(self.wallet);
        self.allocator.destroy(self.provider);
        self.allocator.destroy(self.transport);
        self.allocator.destroy(self);
    }

    /// Return a `ChainClient` view over this instance. The `ptr` is the stable
    /// heap address, so the returned value survives moves of any enclosing
    /// struct.
    pub fn client(self: *EthChainClient) ChainClient {
        return .{ .ptr = self, .vtable = &eth_vtable };
    }

    const eth_vtable = ChainClient.VTable{
        .call = ethCall,
        .sendTransaction = ethSendTransaction,
        .getReceipt = ethGetReceipt,
        .address = ethAddress,
        .callBatch = ethCallBatch,
        .simulate = ethSimulate,
    };

    fn ethCall(ptr: *anyopaque, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) anyerror![]u8 {
        // The provider allocates the returned bytes with its own allocator,
        // which is the same allocator used to construct this client and to run
        // the read helper, so the caller can free with `allocator`.
        _ = allocator;
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        return self.provider.call(to, data);
    }

    fn ethSendTransaction(ptr: *anyopaque, to: [20]u8, data: []const u8, value: u256) anyerror![32]u8 {
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        return self.wallet.sendTransaction(.{ .to = to, .data = data, .value = value });
    }

    fn ethGetReceipt(ptr: *anyopaque, allocator: std.mem.Allocator, tx_hash: [32]u8, max_attempts: u32) anyerror!?eth.receipt.TransactionReceipt {
        _ = allocator;
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        return self.wallet.waitForReceipt(tx_hash, max_attempts);
    }

    fn ethAddress(ptr: *anyopaque) anyerror![20]u8 {
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        return self.wallet.address();
    }

    fn ethSimulate(ptr: *anyopaque, to: [20]u8, data: []const u8, from: [20]u8) anyerror!void {
        // `provider.call` hardcodes `from = null`, so it runs from address(0)
        // and sender-dependent writes falsely revert. `estimateGas` takes a
        // `from` and errors iff the tx would revert, so it is the from-aware
        // revert preflight; the returned gas estimate is discarded.
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        _ = try self.provider.estimateGas(to, data, from);
    }

    fn ethCallBatch(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        calls: []const ChainClient.BatchCall,
    ) anyerror![]ChainClient.BatchResult {
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));

        // eth.zig's BatchCaller issues all reads as a single JSON-RPC batch
        // (one HTTP round-trip). It borrows the calldata (does not copy), which
        // is fine: `calls` outlives `execute`.
        var batch = eth.provider.BatchCaller.init(self.allocator, self.provider);
        defer batch.deinit();
        for (calls) |c| {
            _ = try batch.addCall(c.to, c.data);
        }

        const eth_results = try batch.execute();
        defer eth.provider.freeBatchResults(self.allocator, eth_results);

        // Re-home every entry onto the passed allocator so callers can free the
        // whole slice uniformly with `freeBatchResults`.
        const out = try allocator.alloc(ChainClient.BatchResult, eth_results.len);
        var filled: usize = 0;
        errdefer {
            var i: usize = 0;
            while (i < filled) : (i += 1) allocator.free(out[i].bytes);
            allocator.free(out);
        }

        for (eth_results, 0..) |r, i| {
            switch (r) {
                .success => |data| {
                    out[i] = .{ .success = true, .bytes = try allocator.dupe(u8, data) };
                },
                .rpc_error => {
                    out[i] = .{ .success = false, .bytes = try allocator.alloc(u8, 0) };
                },
            }
            filled = i + 1;
        }
        return out;
    }
};
