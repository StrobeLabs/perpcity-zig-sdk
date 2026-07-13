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
    };

    pub fn call(self: *ChainClient, allocator: std.mem.Allocator, to: [20]u8, data: []const u8) ![]u8 {
        return self.vtable.call(self.ptr, allocator, to, data);
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

/// Free values returned by `readContract`.
pub fn freeReturnValues(values: []AbiValue, allocator: std.mem.Allocator) void {
    eth.abi_decode.freeValues(values, allocator);
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
};
