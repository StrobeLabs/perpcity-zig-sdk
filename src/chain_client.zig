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

    /// Result of a raw eth_call that captures reverts instead of erroring.
    /// `ok` is the return data; `reverted` is the ABI revert payload (the
    /// 4-byte selector + args, or empty for a bare revert / no data). Both
    /// slices are caller-owned -- free with `freeCallOutcome`.
    pub const CallOutcome = union(enum) {
        ok: []u8,
        reverted: []u8,
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
        /// eth_getLogs: fetch the logs matching `filter`. Returns the raw
        /// `eth.receipt.Log` slice (each log's `topics`/`data` allocated with
        /// the passed allocator); the caller owns it and frees it with
        /// `freeLogs`.
        getLogs: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, filter: eth.json_rpc.LogFilter) anyerror![]eth.receipt.Log,
        /// Raw eth_call that returns the revert payload instead of erroring, and
        /// can simulate against modified state. `from` (nullable) is passed
        /// through so sender-dependent calls don't falsely revert; `overrides`
        /// (nullable) applies state overrides (e.g. a hypothetical index value
        /// or balance). Returns `.ok` bytes on success or `.reverted` bytes (the
        /// ABI revert payload, decode with `revert.decode`) on revert. Both
        /// owned by the caller (free with `freeCallOutcome`).
        callRaw: *const fn (ptr: *anyopaque, allocator: std.mem.Allocator, to: [20]u8, data: []const u8, from: ?[20]u8, overrides: ?*const eth.state_overrides.StateOverrides) anyerror!CallOutcome,
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

    pub fn getLogs(self: *ChainClient, allocator: std.mem.Allocator, filter: eth.json_rpc.LogFilter) ![]eth.receipt.Log {
        return self.vtable.getLogs(self.ptr, allocator, filter);
    }

    pub fn callRaw(
        self: *ChainClient,
        allocator: std.mem.Allocator,
        to: [20]u8,
        data: []const u8,
        from: ?[20]u8,
        overrides: ?*const eth.state_overrides.StateOverrides,
    ) !CallOutcome {
        return self.vtable.callRaw(self.ptr, allocator, to, data, from, overrides);
    }
};

/// Free the owned bytes of a `CallOutcome`.
pub fn freeCallOutcome(outcome: ChainClient.CallOutcome, allocator: std.mem.Allocator) void {
    switch (outcome) {
        .ok, .reverted => |b| allocator.free(b),
    }
}

/// Parse an `eth_call` JSON-RPC response into a `CallOutcome`. A `result` hex
/// string becomes `.ok`; an `error.data` hex string (the ABI revert payload)
/// becomes `.reverted`; an error object without `data` becomes `.reverted` with
/// empty bytes. Returns `error.RpcError` when the response is neither.
pub fn parseEthCallResponse(allocator: std.mem.Allocator, json: []const u8) !ChainClient.CallOutcome {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.RpcError;
    const obj = parsed.value.object;

    if (obj.get("result")) |res| {
        if (res == .string) return .{ .ok = try hexToOwned(allocator, res.string) };
    }
    if (obj.get("error")) |err_val| {
        if (err_val == .object) {
            if (err_val.object.get("data")) |d| {
                if (d == .string) return .{ .reverted = try hexToOwned(allocator, d.string) };
            }
        }
        return .{ .reverted = try allocator.alloc(u8, 0) };
    }
    return error.RpcError;
}

/// Decode a `0x`-prefixed (or bare) hex string into freshly-allocated bytes.
fn hexToOwned(allocator: std.mem.Allocator, hex: []const u8) ![]u8 {
    const h = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
        hex[2..]
    else
        hex;
    if (h.len % 2 != 0) return error.InvalidHexLength;
    const out = try allocator.alloc(u8, h.len / 2);
    errdefer allocator.free(out);
    _ = try eth.hex.hexToBytes(out, h);
    return out;
}

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

/// Free the slice returned by `ChainClient.getLogs`, including each log's
/// owned `topics` and `data`. Delegates to eth.zig's log-freeing helper so the
/// alloc/free discipline stays identical to the production `getLogs` path.
pub fn freeLogs(logs: []eth.receipt.Log, allocator: std.mem.Allocator) void {
    eth.log_watcher.freeLogs(allocator, logs);
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
    /// The heap-owned KMS signer when this client signs via AWS KMS (see
    /// `createWithKms`); null for the raw-key path. Kept stable because the
    /// wallet's `Signer` holds a borrowed pointer to it.
    kms_signer: ?*eth.signer.KmsSigner = null,
    /// Owned copy of the KMS key id (the signer borrows it), freed on `destroy`.
    kms_key_id: ?[]u8 = null,
    /// Multi-endpoint read provider with health tracking + failover, when built
    /// via `createWithFallback`; null for the single-endpoint path. When set,
    /// the READ methods (`call`/`getLogs`/`simulate`) route through it; writes,
    /// `callBatch`, and `callRaw` stay on the primary `provider`.
    fallback: ?*eth.fallback_provider.FallbackProvider = null,
    /// Owned copies of the fallback endpoint URLs (the provider borrows them),
    /// freed on `destroy` after the fallback provider.
    fallback_urls: ?[][]const u8 = null,

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

    /// Like `create`, but signs via AWS KMS: the private key never leaves KMS.
    /// `region` is e.g. "us-west-2" and `key_id` is a KMS key id, ARN, or
    /// `alias/...` (must be an `ECC_SECG_P256K1` key). Credentials are resolved
    /// from the environment / container role at call time. The signer derives
    /// and caches the wallet address from KMS during construction (one
    /// `kms:GetPublicKey`), so this makes a network call.
    pub fn createWithKms(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        region: []const u8,
        key_id: []const u8,
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

        // The signer borrows key_id for its lifetime, so own a copy here.
        const key_id_owned = try allocator.dupe(u8, key_id);
        errdefer allocator.free(key_id_owned);

        // Heap-owned + stable: the wallet's Signer holds a borrowed pointer.
        const kms_signer = try allocator.create(eth.signer.KmsSigner);
        errdefer allocator.destroy(kms_signer);
        kms_signer.* = try eth.signer.KmsSigner.init(allocator, eth.runtime.blockingIo(), region, key_id_owned);
        errdefer kms_signer.deinit();

        const wallet = try allocator.create(eth.wallet.Wallet);
        errdefer allocator.destroy(wallet);
        wallet.* = eth.wallet.Wallet.init(allocator, eth.signer.Signer.fromKms(kms_signer), provider);

        self.* = .{
            .allocator = allocator,
            .transport = transport,
            .provider = provider,
            .wallet = wallet,
            .kms_signer = kms_signer,
            .kms_key_id = key_id_owned,
        };
        return self;
    }

    /// Like `create`, but routes the READ path through a multi-endpoint
    /// `FallbackProvider` (health tracking + failover + recovery probing) over
    /// `rpc_urls`, ordered by preference. Writes/`callBatch`/`callRaw` still use
    /// the primary endpoint (`rpc_urls[0]`); a liquidation bot's high-frequency
    /// detection reads (`eth_call`/`eth_getLogs`) get the resilience.
    ///
    /// `opts` tunes the failover threshold and recovery-probe interval. The
    /// endpoint URLs are copied and owned by the client.
    pub fn createWithFallback(
        allocator: std.mem.Allocator,
        rpc_urls: []const []const u8,
        private_key: [32]u8,
        opts: eth.fallback_provider.FallbackOpts,
    ) !*EthChainClient {
        if (rpc_urls.len == 0) return error.NoEndpoints;

        const self = try allocator.create(EthChainClient);
        errdefer allocator.destroy(self);

        // Standalone primary (writes + batch + raw), on the preferred endpoint.
        const transport = try allocator.create(eth.http_transport.HttpTransport);
        errdefer allocator.destroy(transport);
        transport.* = eth.http_transport.HttpTransport.init(allocator, rpc_urls[0], eth.runtime.blockingIo());
        errdefer transport.deinit();

        const provider = try allocator.create(eth.provider.Provider);
        errdefer allocator.destroy(provider);
        provider.* = eth.provider.Provider.init(allocator, transport);

        const wallet = try allocator.create(eth.wallet.Wallet);
        errdefer allocator.destroy(wallet);
        wallet.* = eth.wallet.Wallet.initLocal(allocator, private_key, provider);

        // Own copies of the endpoint URLs (the fallback provider borrows them).
        const owned = try allocator.alloc([]const u8, rpc_urls.len);
        errdefer allocator.free(owned);
        var duped: usize = 0;
        errdefer for (owned[0..duped]) |u| allocator.free(u);
        for (rpc_urls, 0..) |u, i| {
            owned[i] = try allocator.dupe(u8, u);
            duped = i + 1;
        }

        const fallback = try allocator.create(eth.fallback_provider.FallbackProvider);
        errdefer allocator.destroy(fallback);
        fallback.* = try eth.fallback_provider.FallbackProvider.init(allocator, owned, eth.runtime.blockingIo(), opts);
        errdefer fallback.deinit();

        self.* = .{
            .allocator = allocator,
            .transport = transport,
            .provider = provider,
            .wallet = wallet,
            .fallback = fallback,
            .fallback_urls = owned,
        };
        return self;
    }

    /// Tear down the wallet/transport and free every heap allocation, including
    /// `self`, the KMS signer (if any), and the fallback provider (if any).
    pub fn destroy(self: *EthChainClient) void {
        self.wallet.deinit();
        self.transport.deinit();
        if (self.kms_signer) |ks| {
            ks.deinit();
            self.allocator.destroy(ks);
        }
        if (self.kms_key_id) |kid| self.allocator.free(kid);
        // Free the fallback provider before its borrowed URLs.
        if (self.fallback) |fb| {
            fb.deinit();
            self.allocator.destroy(fb);
        }
        if (self.fallback_urls) |urls| {
            for (urls) |u| self.allocator.free(u);
            self.allocator.free(urls);
        }
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
        .getLogs = ethGetLogs,
        .callRaw = ethCallRaw,
    };

    fn ethCall(ptr: *anyopaque, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) anyerror![]u8 {
        // The provider allocates the returned bytes with its own allocator,
        // which is the same allocator used to construct this client and to run
        // the read helper, so the caller can free with `allocator`.
        _ = allocator;
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        if (self.fallback) |fb| return fb.call(to, data);
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
        if (self.fallback) |fb| {
            _ = try fb.estimateGas(to, data, from);
            return;
        }
        _ = try self.provider.estimateGas(to, data, from);
    }

    fn ethGetLogs(ptr: *anyopaque, allocator: std.mem.Allocator, filter: eth.json_rpc.LogFilter) anyerror![]eth.receipt.Log {
        // The provider allocates the returned logs (topics/data) with its own
        // allocator, which is the same allocator used to construct this client
        // and to run `pollEvents`, so the caller can free with `allocator` via
        // `freeLogs`.
        _ = allocator;
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        if (self.fallback) |fb| return fb.getLogs(filter);
        return self.provider.getLogs(filter);
    }

    fn ethCallRaw(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        to: [20]u8,
        data: []const u8,
        from: ?[20]u8,
        overrides: ?*const eth.state_overrides.StateOverrides,
    ) anyerror!ChainClient.CallOutcome {
        // eth.zig's Provider.call drops the JSON-RPC error.data (revert bytes)
        // and has no from+overrides path, so build the params and go through the
        // raw transport, then parse the response ourselves.
        const self: *EthChainClient = @ptrCast(@alignCast(ptr));
        const params = if (overrides) |ov|
            try self.provider.formatCallParamsWithOverrides(to, data, from, ov)
        else
            try self.provider.formatCallParams(to, data, from);
        defer self.allocator.free(params);

        const resp = try self.transport.request(eth.json_rpc.Method.eth_call, params, 1);
        defer self.allocator.free(resp);

        return parseEthCallResponse(allocator, resp);
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
