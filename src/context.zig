const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const constants = @import("constants.zig");
const conversions = @import("conversions.zig");
const approve_mod = @import("approve.zig");
const state_cache_mod = @import("state_cache.zig");
const chain_client = @import("chain_client.zig");
const event_decode = @import("event_decode.zig");
const revert_mod = @import("revert.zig");
const multicall_mod = @import("multicall.zig");
const nonce_mod = @import("nonce.zig");
const gas_mod = @import("gas.zig");
const tx_pipeline_mod = @import("tx_pipeline.zig");
const perp_abi = @import("abi/perp_abi.zig");
const fees_abi = @import("abi/fees_abi.zig");
const margin_ratios_abi = @import("abi/margin_ratios_abi.zig");
const erc20_abi = @import("abi/erc20_abi.zig");
const beacon_abi = @import("abi/beacon_abi.zig");

const ChainClient = chain_client.ChainClient;
const EthChainClient = chain_client.EthChainClient;

/// Cache time-to-live in seconds (5 minutes).
const CACHE_TTL_SECONDS: i64 = 300;

pub const CacheEntry = struct {
    value: types.PerpConfig,
    expires_at: i64,
};

/// The typed outcome of a raw simulation (`simulateCall`). Free with `deinit`.
pub const SimOutcome = union(enum) {
    /// The call succeeded; `data` is the ABI return bytes.
    ok: []u8,
    /// The call reverted; `data` is the raw revert payload and `decoded`
    /// classifies it (borrowing `data`, so keep the outcome alive).
    reverted: struct { data: []u8, decoded: revert_mod.Revert },

    pub fn deinit(self: SimOutcome, allocator: std.mem.Allocator) void {
        switch (self) {
            .ok => |b| allocator.free(b),
            .reverted => |r| allocator.free(r.data),
        }
    }
};

/// A managed write request: target, calldata, value, gas ceiling, and urgency
/// (which scales the EIP-1559 fees). Re-exported from `tx_pipeline`.
pub const TxRequest = tx_pipeline_mod.TxRequest;
/// The `(tx_hash, nonce)` of a submitted managed write.
pub const TxResult = tx_pipeline_mod.TxResult;
/// Managed-write pipeline tuning (max in-flight, stuck timeout).
pub const TxPipelineConfig = tx_pipeline_mod.TxPipelineConfig;
/// Gas-cache tuning (TTL, default tip).
pub const GasCacheConfig = gas_mod.GasCacheConfig;
/// EIP-1559 fee urgency (low/normal/high/critical) for a managed write.
pub const Urgency = gas_mod.Urgency;

/// Heap-owned bundle backing the managed write path. Held on the heap so the
/// `TxPipeline`'s pointers into `nonce_mgr` / `gas_cache` stay stable.
const ManagedWrites = struct {
    nonce_mgr: nonce_mod.HftNonceManager,
    gas_cache: gas_mod.GasCache,
    pipeline: tx_pipeline_mod.TxPipeline,
};

/// Main client context for interacting with the PerpCity v0.1.0 protocol.
pub const PerpCityContext = struct {
    allocator: std.mem.Allocator,
    /// The chain interface every read/write goes through. In production this is
    /// backed by `eth_client`; in tests a mock is injected via `initWithClient`.
    client: ChainClient,
    /// The owned production client, or null when a client was injected. When
    /// non-null, `deinit` destroys it.
    eth_client: ?*EthChainClient,
    deployments: types.PerpCityDeployments,
    /// Approval is tracked per-perp because each Perp market is a separate
    /// ERC721 contract that holds the user's USDC allowance.
    approved_perps: std.AutoHashMap(types.Address, void),
    config_cache: std.AutoHashMap(types.Address, CacheEntry),
    state_cache: state_cache_mod.StateCache,
    rpc_url: []const u8,
    /// The managed-write pipeline, when enabled via `enableManagedWrites`; null
    /// otherwise. `deinit` tears it down.
    managed: ?*ManagedWrites = null,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        private_key: [32]u8,
        deployments: types.PerpCityDeployments,
    ) !Self {
        // The EthChainClient owns the transport/provider/wallet on the heap, so
        // their addresses stay stable no matter where this Self is moved. That
        // is what lets us drop the old `fixPointers` hack.
        const ec = try EthChainClient.create(allocator, rpc_url, private_key);
        return Self{
            .allocator = allocator,
            .client = ec.client(),
            .eth_client = ec,
            .deployments = deployments,
            .approved_perps = std.AutoHashMap(types.Address, void).init(allocator),
            .config_cache = std.AutoHashMap(types.Address, CacheEntry).init(allocator),
            .state_cache = state_cache_mod.StateCache.init(allocator, .{}),
            .rpc_url = rpc_url,
        };
    }

    /// Like `init`, but signs the write path via AWS KMS -- the private key
    /// never leaves KMS. `region` is e.g. "us-west-2"; `key_id` is a KMS key id,
    /// ARN, or `alias/...` (an `ECC_SECG_P256K1` key). Credentials resolve from
    /// the environment / container role. Derives the wallet address from KMS at
    /// construction, so this makes a network call.
    pub fn initWithKms(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        region: []const u8,
        key_id: []const u8,
        deployments: types.PerpCityDeployments,
    ) !Self {
        const ec = try EthChainClient.createWithKms(allocator, rpc_url, region, key_id);
        return Self{
            .allocator = allocator,
            .client = ec.client(),
            .eth_client = ec,
            .deployments = deployments,
            .approved_perps = std.AutoHashMap(types.Address, void).init(allocator),
            .config_cache = std.AutoHashMap(types.Address, CacheEntry).init(allocator),
            .state_cache = state_cache_mod.StateCache.init(allocator, .{}),
            .rpc_url = rpc_url,
        };
    }

    /// Like `init`, but routes the READ path through a multi-endpoint fallback
    /// provider over `rpc_urls` (ordered by preference), with health tracking,
    /// failover, and recovery probing. Writes stay on the primary endpoint.
    /// `opts` tunes the failover threshold / recovery-probe interval.
    pub fn initWithFallback(
        allocator: std.mem.Allocator,
        rpc_urls: []const []const u8,
        private_key: [32]u8,
        opts: eth.fallback_provider.FallbackOpts,
        deployments: types.PerpCityDeployments,
    ) !Self {
        const ec = try EthChainClient.createWithFallback(allocator, rpc_urls, private_key, opts);
        return Self{
            .allocator = allocator,
            .client = ec.client(),
            .eth_client = ec,
            .deployments = deployments,
            .approved_perps = std.AutoHashMap(types.Address, void).init(allocator),
            .config_cache = std.AutoHashMap(types.Address, CacheEntry).init(allocator),
            .state_cache = state_cache_mod.StateCache.init(allocator, .{}),
            .rpc_url = rpc_urls[0],
        };
    }

    /// Build a context around an already-constructed `ChainClient` (for tests
    /// with an in-memory mock). The context does not own the client, so
    /// `deinit` leaves it alone (`eth_client` is null).
    pub fn initWithClient(
        allocator: std.mem.Allocator,
        client: ChainClient,
        deployments: types.PerpCityDeployments,
    ) Self {
        return Self{
            .allocator = allocator,
            .client = client,
            .eth_client = null,
            .deployments = deployments,
            .approved_perps = std.AutoHashMap(types.Address, void).init(allocator),
            .config_cache = std.AutoHashMap(types.Address, CacheEntry).init(allocator),
            .state_cache = state_cache_mod.StateCache.init(allocator, .{}),
            .rpc_url = "",
        };
    }

    pub fn deinit(self: *Self) void {
        self.state_cache.deinit();
        self.config_cache.deinit();
        self.approved_perps.deinit();
        if (self.managed) |mw| {
            mw.pipeline.deinit();
            mw.nonce_mgr.deinit();
            self.allocator.destroy(mw);
        }
        if (self.eth_client) |ec| ec.destroy();
    }

    // -----------------------------------------------------------------
    // Approval helpers (per-perp because each Perp is its own contract)
    // -----------------------------------------------------------------

    pub fn setupForTrading(self: *Self, perp: types.Address) !void {
        const owner = try self.client.address();

        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            self.deployments.usdc,
            erc20_abi.allowance_selector,
            &.{ .{ .address = owner }, .{ .address = perp } },
            &.{.uint256},
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        const current_allowance: u256 = result[0].uint256;
        const threshold: u256 = std.math.maxInt(u256) / 2;

        if (current_allowance < threshold) {
            _ = try approve_mod.approveUsdcMax(self, perp);
        }

        try self.approved_perps.put(perp, {});
    }

    pub fn ensureApproval(self: *Self, perp: types.Address) !void {
        if (!self.approved_perps.contains(perp)) {
            try self.setupForTrading(perp);
        }
    }

    // -----------------------------------------------------------------
    // Cache helpers
    // -----------------------------------------------------------------

    fn now() i64 {
        // Zig 0.16 removed `std.time.timestamp()`; derive unix seconds from the
        // millisecond timestamp exposed by eth.zig's runtime helper.
        return @divTrunc(eth.runtime.milliTimestamp(eth.runtime.blockingIo()), 1000);
    }

    fn getCached(self: *Self, perp: types.Address) ?types.PerpConfig {
        const entry = self.config_cache.get(perp) orelse return null;
        if (now() >= entry.expires_at) return null;
        return entry.value;
    }

    fn putCache(self: *Self, perp: types.Address, config_val: types.PerpConfig) !void {
        try self.config_cache.put(perp, .{
            .value = config_val,
            .expires_at = now() + CACHE_TTL_SECONDS,
        });
    }

    // -----------------------------------------------------------------
    // Public read methods
    // -----------------------------------------------------------------

    pub fn getPerpConfig(self: *Self, perp: types.Address) !types.PerpConfig {
        if (self.getCached(perp)) |cached| return cached;
        const config_val = try self.fetchPerpConfigFromChain(perp);
        try self.putCache(perp, config_val);
        return config_val;
    }

    pub fn getPerpData(self: *Self, perp: types.Address) !types.PerpData {
        const config_val = try self.getPerpConfig(perp);

        const fees_module = config_val.modules.fees;
        const mr_module = config_val.modules.margin_ratios;

        // Collapse the five per-field reads into a single batched eth_call
        // (one JSON-RPC round-trip) instead of issuing them sequentially. The
        // modules() read above is served from the config cache.
        const cd_fees = try eth.abi_encode.encodeFunctionCall(self.allocator, fees_abi.fees_selector, &.{});
        defer self.allocator.free(cd_fees);
        const cd_liq = try eth.abi_encode.encodeFunctionCall(self.allocator, fees_abi.liq_fee_selector, &.{});
        defer self.allocator.free(cd_liq);
        const cd_taker = try eth.abi_encode.encodeFunctionCall(self.allocator, margin_ratios_abi.taker_margin_ratios_selector, &.{});
        defer self.allocator.free(cd_taker);
        const cd_maker = try eth.abi_encode.encodeFunctionCall(self.allocator, margin_ratios_abi.maker_margin_ratios_selector, &.{});
        defer self.allocator.free(cd_maker);
        const cd_pool = try eth.abi_encode.encodeFunctionCall(self.allocator, perp_abi.pool_state_selector, &.{});
        defer self.allocator.free(cd_pool);

        const calls = [_]ChainClient.BatchCall{
            .{ .to = fees_module, .data = cd_fees },
            .{ .to = fees_module, .data = cd_liq },
            .{ .to = mr_module, .data = cd_taker },
            .{ .to = mr_module, .data = cd_maker },
            .{ .to = perp, .data = cd_pool },
        };

        const results = try self.client.callBatch(self.allocator, &calls);
        defer chain_client.freeBatchResults(results, self.allocator);

        // A failed entry means the read reverted on-chain; surface it rather
        // than decoding zero bytes into misleading zeros.
        for (results) |r| {
            if (!r.success) return error.BatchCallFailed;
        }

        // fees(): (creator, insurance, lp) scaled by 1e6.
        const fees_vals = try self.decodeBatch(results[0].bytes, &.{ .uint256, .uint256, .uint256 });
        defer chain_client.freeReturnValues(fees_vals, self.allocator);
        // liqFee(): single uint256.
        const liq_vals = try self.decodeBatch(results[1].bytes, &.{.uint256});
        defer chain_client.freeReturnValues(liq_vals, self.allocator);
        // takerMarginRatios() / makerMarginRatios(): (init, liq, backstop) scaled by 1e6.
        const taker_vals = try self.decodeBatch(results[2].bytes, &.{ .uint256, .uint256, .uint256 });
        defer chain_client.freeReturnValues(taker_vals, self.allocator);
        const maker_vals = try self.decodeBatch(results[3].bytes, &.{ .uint256, .uint256, .uint256 });
        defer chain_client.freeReturnValues(maker_vals, self.allocator);
        // poolState(): (int256, uint256 sqrtPriceX96, uint256, uint256).
        const pool_vals = try self.decodeBatch(results[4].bytes, &.{ .int256, .uint256, .uint256, .uint256 });
        defer chain_client.freeReturnValues(pool_vals, self.allocator);

        const fee_summary = types.Fees{
            .creator_fee = uintToRatio(fees_vals[0].uint256),
            .insurance_fee = uintToRatio(fees_vals[1].uint256),
            .lp_fee = uintToRatio(fees_vals[2].uint256),
            .liquidation_fee = uintToRatio(liq_vals[0].uint256),
        };
        const taker_bounds = boundsFromRatios(taker_vals[0].uint256, taker_vals[1].uint256, taker_vals[2].uint256);
        const maker_bounds = boundsFromRatios(maker_vals[0].uint256, maker_vals[1].uint256, maker_vals[2].uint256);

        const sqrt_price_x96: u256 = pool_vals[1].uint256;
        const mark = try conversions.sqrtPriceX96ToPrice(sqrt_price_x96);
        self.state_cache.putMarkPrice(perp, mark, now()) catch {};

        return types.PerpData{
            .perp = perp,
            .mark = mark,
            .beacon = config_val.modules.beacon,
            .taker_bounds = taker_bounds,
            .maker_bounds = maker_bounds,
            .fees = fee_summary,
        };
    }

    /// Decode raw ABI return bytes (from a `BatchResult`) into values with the
    /// context allocator. Mirrors the decode step of `readContract`, minus the
    /// encode + eth_call (the batch already performed the call).
    fn decodeBatch(self: *Self, bytes: []const u8, out_types: []const eth.abi_types.AbiType) ![]eth.abi_encode.AbiValue {
        return eth.abi_decode.decodeValues(bytes, out_types, self.allocator);
    }

    pub fn getUserData(
        self: *Self,
        address: types.Address,
        positions: []const PerpPositionId,
    ) !types.UserData {
        const balance = try self.fetchUsdcBalance(address);

        var open_list: std.ArrayList(types.OpenPositionData) = .empty;
        defer open_list.deinit(self.allocator);

        for (positions) |entry| {
            const raw = try self.getPositionRawData(entry.perp, entry.position_id);
            try open_list.append(self.allocator, .{
                .perp = entry.perp,
                .position_id = entry.position_id,
                .is_maker = entry.is_maker,
                .live_details = .{
                    .margin = @as(f64, @floatFromInt(raw.margin)) / constants.F64_1E6,
                    .perp_delta = raw.delta,
                    .liq_margin_ratio = raw.liq_margin_ratio,
                    .backstop_margin_ratio = raw.backstop_margin_ratio,
                },
            });
        }

        const owned_slice = try open_list.toOwnedSlice(self.allocator);

        return types.UserData{
            .wallet_address = address,
            .usdc_balance = balance,
            .open_positions = owned_slice,
        };
    }

    pub fn getPositionRawData(
        self: *Self,
        perp: types.Address,
        pos_id: u256,
    ) !types.PositionRawData {
        // Output tuple mirrors `Perp.positions(uint256)` v0.1.0:
        //   (BalanceDelta delta, uint128 margin, uint24 liqMarginRatio,
        //    uint24 backstopMarginRatio, int256 lastCumlFundingX96).
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.positions_selector,
            &.{.{ .uint256 = pos_id }},
            &.{ .int256, .uint128, .uint24, .uint24, .int256 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        return types.PositionRawData{
            .perp = perp,
            .position_id = pos_id,
            .delta = result[0].int256,
            .margin = @intCast(result[1].uint256),
            .liq_margin_ratio = @intCast(result[2].uint256),
            .backstop_margin_ratio = @intCast(result[3].uint256),
            .last_cuml_funding_x96 = result[4].int256,
        };
    }

    pub fn getOpenInterest(self: *Self, perp: types.Address) !types.OpenInterest {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.open_interest_selector,
            &.{},
            &.{ .uint256, .uint256 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);
        return .{
            .long = @intCast(result[0].uint256),
            .short = @intCast(result[1].uint256),
        };
    }

    pub fn getCapacity(self: *Self, perp: types.Address) !types.Capacity {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.capacity_selector,
            &.{},
            &.{ .uint256, .uint256 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);
        return .{
            .long = @intCast(result[0].uint256),
            .short = @intCast(result[1].uint256),
        };
    }

    /// Current funding rate for a perp. Decodes the full `Rates` tuple
    /// (int88 fundingPerDay, uint64 longUtilFeePerDay, uint64 shortUtilFeePerDay,
    /// uint40 lastTouch) but only surfaces the funding component. `fundingPerDay`
    /// is signed and scaled by 1e18 per day; the returned percentages mirror the
    /// TypeScript SDK `getFundingRate`.
    pub fn getFundingRate(self: *Self, perp: types.Address) !types.FundingRate {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.rates_selector,
            &.{},
            &.{ .int88, .uint64, .uint64, .uint40 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        const raw: i256 = result[0].int256;
        // Convert via i128 to avoid the LLVM aarch64 i256->f64 crash. int88 fits
        // comfortably in i128.
        const raw_128: i128 = @intCast(raw);
        const rate_per_day: f64 = @as(f64, @floatFromInt(raw_128)) / constants.F64_1E18 * 100.0;

        return types.FundingRate{
            .rate_per_day = rate_per_day,
            .rate_per_minute = rate_per_day / 1440.0,
            .funding_per_day_raw = raw,
        };
    }

    /// Maker position detail from `Perp.makerDetails(posId)`. The `Maker` struct
    /// is fully static, so decoding its leading `(int24, int24, uint128)` reads
    /// the tick range and liquidity regardless of the trailing checkpoint fields.
    pub fn getMakerDetails(self: *Self, perp: types.Address, pos_id: u256) !types.MakerDetails {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.maker_details_selector,
            &.{.{ .uint256 = pos_id }},
            &.{ .int24, .int24, .uint128 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        return types.MakerDetails{
            .perp = perp,
            .position_id = pos_id,
            .tick_lower = @intCast(result[0].int256),
            .tick_upper = @intCast(result[1].int256),
            .liquidity = @intCast(result[2].uint256),
        };
    }

    /// Taker position detail from `Perp.takerDetails(posId)`: the two X96
    /// utilization-fee payment checkpoints.
    pub fn getTakerDetails(self: *Self, perp: types.Address, pos_id: u256) !types.TakerDetails {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.taker_details_selector,
            &.{.{ .uint256 = pos_id }},
            &.{ .uint256, .uint256 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        return types.TakerDetails{
            .perp = perp,
            .position_id = pos_id,
            .last_long_util_payments_x96 = result[0].uint256,
            .last_short_util_payments_x96 = result[1].uint256,
        };
    }

    /// Owner of position NFT `pos_id` (ERC721 `Perp.ownerOf(id)`).
    ///
    /// Positions are ERC721 tokens; a live position resolves to its owner's
    /// address. `ownerOf` reverts for an id that was never minted or has been
    /// burned (a closed or liquidated position), which surfaces here as an
    /// error from the underlying call - a successful return therefore means the
    /// position is still open. Pair with `pollEvents` to enumerate candidate
    /// ids (the Perp is not ERC721Enumerable, so there is no on-chain listing).
    pub fn getPositionOwner(self: *Self, perp: types.Address, pos_id: u256) !types.Address {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.owner_of_selector,
            &.{.{ .uint256 = pos_id }},
            &.{.address},
        );
        defer chain_client.freeReturnValues(result, self.allocator);
        return result[0].address;
    }

    /// Number of open positions held by `owner` (ERC721 `Perp.balanceOf(owner)`).
    ///
    /// Returns the count only; the Perp is not ERC721Enumerable, so the
    /// individual position ids must be discovered via events (`pollEvents`).
    pub fn getPositionBalance(self: *Self, perp: types.Address, owner: types.Address) !u256 {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.balance_of_selector,
            &.{.{ .address = owner }},
            &.{.uint256},
        );
        defer chain_client.freeReturnValues(result, self.allocator);
        return result[0].uint256;
    }

    /// Market solvency state from `Perp.solvencyState`: (uint128 badDebt,
    /// uint128 totalMargin).
    pub fn getSolvencyState(self: *Self, perp: types.Address) !types.SolvencyState {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.solvency_state_selector,
            &.{},
            &.{ .uint128, .uint128 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        return types.SolvencyState{
            .perp = perp,
            .bad_debt = @intCast(result[0].uint256),
            .total_margin = @intCast(result[1].uint256),
        };
    }

    /// Accrued fee balances from `Perp.feeFund`: (uint80 insurance,
    /// uint80 creatorFees, uint80 protocolFees).
    pub fn getFeeFund(self: *Self, perp: types.Address) !types.FeeFund {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.fee_fund_selector,
            &.{},
            &.{ .uint80, .uint80, .uint80 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        return types.FeeFund{
            .perp = perp,
            .insurance = @intCast(result[0].uint256),
            .creator_fees = @intCast(result[1].uint256),
            .protocol_fees = @intCast(result[2].uint256),
        };
    }

    /// Current index value of a beacon (`IBeacon.index()`), a single uint256.
    /// Matches the TypeScript SDK `getIndexValue`.
    pub fn getIndexValue(self: *Self, beacon: types.Address) !u256 {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            beacon,
            beacon_abi.index_selector,
            &.{},
            &.{.uint256},
        );
        defer chain_client.freeReturnValues(result, self.allocator);
        return result[0].uint256;
    }

    /// Time-weighted average index of a beacon over `seconds_ago`
    /// (`IBeacon.twAvg(uint32)`), a single uint256. Matches the TypeScript SDK
    /// `getIndexTWAP`.
    pub fn getIndexTWAP(self: *Self, beacon: types.Address, seconds_ago: u32) !u256 {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            beacon,
            beacon_abi.tw_avg_selector,
            &.{.{ .uint256 = @as(u256, seconds_ago) }},
            &.{.uint256},
        );
        defer chain_client.freeReturnValues(result, self.allocator);
        return result[0].uint256;
    }

    // -----------------------------------------------------------------
    // Event polling
    // -----------------------------------------------------------------

    /// Fetch and decode the recognized PerpCity events emitted by `perp` in the
    /// inclusive block range `[from_block, to_block]`.
    ///
    /// Builds an `eth_getLogs` filter (address + hex block bounds), decodes each
    /// returned log into its typed `DecodedEvent`, and collects the non-null
    /// results. Logs with an unknown `topic0` are skipped. The raw logs are
    /// freed before returning.
    ///
    /// Ownership: the caller owns the returned slice and frees it with
    /// `allocator.free` (the `DecodedEvent`s themselves hold no allocations).
    ///
    /// This issues a single `eth_getLogs` for the whole `[from_block, to_block]`
    /// span. Public RPC providers cap that span (commonly 2k-10k blocks) and/or
    /// the number of returned logs, and will reject an over-wide request. For
    /// large ranges the caller should chunk into fixed-width windows and call
    /// `pollEvents` per window, concatenating the results.
    pub fn pollEvents(
        self: *Self,
        perp: types.Address,
        from_block: u64,
        to_block: u64,
    ) ![]event_decode.DecodedEvent {
        // json_rpc.LogFilter expects hex strings. `address_hex` lives on the
        // stack for the whole call; getLogs consumes the filter synchronously.
        const address_hex = eth.primitives.addressToHex(&perp);
        const from_hex = try std.fmt.allocPrint(self.allocator, "0x{x}", .{from_block});
        defer self.allocator.free(from_hex);
        const to_hex = try std.fmt.allocPrint(self.allocator, "0x{x}", .{to_block});
        defer self.allocator.free(to_hex);

        const filter = eth.json_rpc.LogFilter{
            .fromBlock = from_hex,
            .toBlock = to_hex,
            .address = &address_hex,
        };

        const logs = try self.client.getLogs(self.allocator, filter);
        defer chain_client.freeLogs(logs, self.allocator);

        return event_decode.decodeLogs(self.allocator, logs);
    }

    /// Discover the position ids currently owned by `owner` in market `perp`.
    ///
    /// The Perp mints positions as Solady ERC721 tokens and is NOT
    /// `ERC721Enumerable`, so there is no on-chain way to list a wallet's
    /// positions. This scans `perp`'s position events over the inclusive block
    /// range `[from_block, to_block]` for every id that appears (opens, adjusts,
    /// closes, backstops, conversions), then confirms each in a single batched
    /// `ownerOf` call. An id is returned iff its token is still live (ownerOf did
    /// not revert) AND currently owned by `owner`; closed/liquidated positions
    /// (ownerOf reverts) and positions transferred away are naturally excluded,
    /// so the event lifecycle semantics never need to be modelled here.
    ///
    /// Ownership: the caller owns the returned slice and frees it with
    /// `allocator.free`. The ids are returned in first-seen event order. For a
    /// large block span, chunk the range as described on `pollEvents` and union
    /// the results.
    pub fn discoverOwnedPositions(
        self: *Self,
        perp: types.Address,
        owner: types.Address,
        from_block: u64,
        to_block: u64,
    ) ![]u256 {
        const evs = try self.pollEvents(perp, from_block, to_block);
        defer self.allocator.free(evs);

        // Collect unique candidate ids in first-seen order.
        var seen = std.AutoHashMap(u256, void).init(self.allocator);
        defer seen.deinit();
        var candidates: std.ArrayList(u256) = .empty;
        defer candidates.deinit(self.allocator);
        for (evs) |ev| {
            const id = event_decode.positionId(ev) orelse continue;
            const gop = try seen.getOrPut(id);
            if (!gop.found_existing) try candidates.append(self.allocator, id);
        }
        if (candidates.items.len == 0) return self.allocator.alloc(u256, 0);

        // Batch ownerOf(id) for every candidate into one round-trip. Each call's
        // encoded calldata is owned here and freed after the batch resolves. A
        // single cleanup frees exactly the entries built so far (whether the
        // encode loop completed or errored partway), so there is no double-free
        // and no read of an uninitialized `calls` entry.
        const calls = try self.allocator.alloc(ChainClient.BatchCall, candidates.items.len);
        var built: usize = 0;
        defer {
            for (calls[0..built]) |c| self.allocator.free(c.data);
            self.allocator.free(calls);
        }
        for (candidates.items, 0..) |id, i| {
            const cd = try eth.abi_encode.encodeFunctionCall(
                self.allocator,
                perp_abi.owner_of_selector,
                &.{.{ .uint256 = id }},
            );
            calls[i] = .{ .to = perp, .data = cd };
            built = i + 1;
        }

        const results = try self.client.callBatch(self.allocator, calls);
        defer chain_client.freeBatchResults(results, self.allocator);

        var owned: std.ArrayList(u256) = .empty;
        defer owned.deinit(self.allocator);
        for (results, candidates.items) |r, id| {
            // A reverted ownerOf (success=false) means the position is closed or
            // never existed; skip it rather than decoding zero bytes.
            if (!r.success) continue;
            const vals = eth.abi_decode.decodeValues(r.bytes, &.{.address}, self.allocator) catch continue;
            defer chain_client.freeReturnValues(vals, self.allocator);
            if (std.mem.eql(u8, &vals[0].address, &owner)) try owned.append(self.allocator, id);
        }
        return owned.toOwnedSlice(self.allocator);
    }

    /// Simulate a call against the chain, capturing a revert as a typed value
    /// (rather than erroring) and optionally against overridden state.
    ///
    /// `from` (nullable) is the sender the call runs as - pass the trading
    /// wallet so sender-dependent calls (e.g. `approve`) don't falsely revert
    /// from `address(0)`. `overrides` (nullable) applies eth `StateOverrides`,
    /// so a bot can simulate against hypothetical state - a future beacon index,
    /// a modified margin/balance - to preview whether a liquidation would
    /// succeed (and decode exactly why it wouldn't) before spending gas.
    ///
    /// On a revert the returned `.reverted.decoded` is the typed classification
    /// (see `revert.zig`); branch on `revert.retryHint` to skip / retry-smaller.
    ///
    /// Ownership: free the returned outcome with `SimOutcome.deinit`.
    pub fn simulateCall(
        self: *Self,
        to: types.Address,
        calldata: []const u8,
        from: ?types.Address,
        overrides: ?*const eth.state_overrides.StateOverrides,
    ) !SimOutcome {
        const outcome = try self.client.callRaw(self.allocator, to, calldata, from, overrides);
        return switch (outcome) {
            .ok => |b| .{ .ok = b },
            .reverted => |b| .{ .reverted = .{ .data = b, .decoded = revert_mod.decode(b) } },
        };
    }

    /// Execute an on-chain Multicall3 `aggregate3`: bundle `calls` into a single
    /// `eth_call` that runs atomically at one block. Returns one `Result` per
    /// call (index-aligned; `success` + `return_data`).
    ///
    /// Unlike `getPerpData`'s JSON-RPC batching (independent calls the node may
    /// serve from different blocks), every read here observes the SAME block
    /// state - use it to snapshot many positions/fields consistently (e.g. a
    /// solvency sweep). Set `allow_failure` per call to tolerate an individual
    /// revert instead of reverting the whole aggregate.
    ///
    /// Ownership: free the returned slice with `multicall.freeResults`.
    pub fn multicall3(self: *Self, calls: []const multicall_mod.Call3) ![]multicall_mod.Result {
        const calldata = try multicall_mod.encodeAggregate3(self.allocator, calls);
        defer self.allocator.free(calldata);
        const raw = try self.client.call(self.allocator, multicall_mod.MULTICALL3_ADDRESS, calldata);
        defer self.allocator.free(raw);
        return multicall_mod.decodeResults(self.allocator, raw);
    }

    // -----------------------------------------------------------------
    // Managed write path (nonce/gas pipeline + stuck-tx gas-bump resends)
    // -----------------------------------------------------------------

    /// Enable the managed write path: a `TxPipeline` that assigns the nonce and
    /// EIP-1559 gas with no RPC on the hot path and supports same-nonce gas-bump
    /// resends of a stuck transaction. `starting_nonce` is the sender's current
    /// on-chain nonce; keep the base fee current via `refreshBaseFee` (from a
    /// block header) before sending. All timing is via explicit `now_ms` (no OS
    /// clock in lib code).
    pub fn enableManagedWrites(
        self: *Self,
        starting_nonce: u64,
        gas_config: GasCacheConfig,
        config: TxPipelineConfig,
    ) !void {
        if (self.managed != null) return error.ManagedWritesAlreadyEnabled;
        const mw = try self.allocator.create(ManagedWrites);
        errdefer self.allocator.destroy(mw);
        mw.nonce_mgr = nonce_mod.HftNonceManager.init(self.allocator, starting_nonce);
        mw.gas_cache = gas_mod.GasCache.init(gas_config);
        // The pipeline borrows &mw.nonce_mgr / &mw.gas_cache; mw is heap-stable.
        mw.pipeline = tx_pipeline_mod.TxPipeline.init(self.allocator, &mw.nonce_mgr, &mw.gas_cache, config);
        self.managed = mw;
    }

    /// Feed the latest block base fee into the managed gas cache (e.g. from a
    /// `PerpEventWatcher`/block header), so `sendManaged` resolves fees without
    /// an `eth_gasPrice` RPC. No-op when managed writes are not enabled.
    pub fn refreshBaseFee(self: *Self, base_fee: u64, now_ms: i64) void {
        if (self.managed) |mw| mw.gas_cache.updateFromBlock(base_fee, now_ms);
    }

    /// Submit a write through the managed pipeline: acquire a nonce and resolve
    /// gas (no RPC), sign+send with those explicit values, and track it in
    /// flight. Returns the `(tx_hash, nonce)`. Errors `GasPriceUnavailable` if
    /// the base fee is stale/unset (call `refreshBaseFee` first) and
    /// `TooManyInFlight` at the configured cap; a send failure releases the
    /// nonce so it is not skipped.
    pub fn sendManaged(self: *Self, request: TxRequest, now_ms: i64) !TxResult {
        const mw = self.managed orelse return error.ManagedWritesNotEnabled;
        const prepared = try mw.pipeline.prepare(request, now_ms);
        const hash = self.client.sendManaged(request.to, request.calldata, request.value, .{
            .nonce = prepared.nonce,
            .gas_limit = prepared.gas_limit,
            .max_fee_per_gas = prepared.gas_fees.max_fee_per_gas,
            .max_priority_fee_per_gas = prepared.gas_fees.max_priority_fee,
        }) catch |e| {
            // The tx never entered the mempool; give the nonce back so the next
            // send does not gap.
            mw.nonce_mgr.releaseNonce(prepared.nonce);
            return e;
        };
        // The tx is already broadcast, so a tracking failure must NOT surface as
        // a send failure -- a caller that retried with a fresh nonce would
        // double-send a live tx. Track best-effort; the only cost of a miss is
        // that this tx is not covered by stuck-detection. Return it regardless.
        mw.pipeline.recordSubmission(hash, prepared, now_ms) catch {};
        return .{ .tx_hash = hash, .nonce = prepared.nonce };
    }

    /// The tx hashes that have been in flight past the pipeline's stuck timeout.
    /// Caller owns the returned slice (`allocator.free`). Feed each into
    /// `resendBumped`.
    pub fn stuckWrites(self: *Self, now_ms: i64) ![][32]u8 {
        const mw = self.managed orelse return error.ManagedWritesNotEnabled;
        return mw.pipeline.getStuckTxs(now_ms);
    }

    /// Resend a stuck write at the SAME nonce with the fees scaled by
    /// `multiplier` (the EIP-1559 replacement rule), returning the new tx hash.
    /// `request` is the original request (the caller retains it; the pipeline's
    /// bump params carry only nonce + fees). The original stays the in-flight
    /// tracker -- when either version mines, call `confirmWrite`/`failWrite` on
    /// the original hash. Errors `TxNotInFlight` if the original is unknown.
    pub fn resendBumped(self: *Self, request: TxRequest, original_tx_hash: [32]u8, multiplier: u64) ![32]u8 {
        const mw = self.managed orelse return error.ManagedWritesNotEnabled;
        const bump = mw.pipeline.prepareBump(original_tx_hash, multiplier) orelse return error.TxNotInFlight;
        return self.client.sendManaged(request.to, request.calldata, request.value, .{
            .nonce = bump.nonce,
            .gas_limit = bump.gas_limit,
            .max_fee_per_gas = bump.new_max_fee,
            .max_priority_fee_per_gas = bump.new_max_priority_fee,
        });
    }

    /// Mark a managed write mined: drop it from in-flight and confirm its nonce.
    pub fn confirmWrite(self: *Self, tx_hash: [32]u8) void {
        if (self.managed) |mw| mw.pipeline.confirmTx(tx_hash);
    }

    /// Mark a managed write failed: drop it and release its nonce for reuse.
    pub fn failWrite(self: *Self, tx_hash: [32]u8) void {
        if (self.managed) |mw| mw.pipeline.failTx(tx_hash);
    }

    // -----------------------------------------------------------------
    // Private chain-reading helpers
    // -----------------------------------------------------------------

    fn fetchPerpConfigFromChain(self: *Self, perp: types.Address) !types.PerpConfig {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.modules_selector,
            &.{},
            &.{ .address, .address, .address, .address, .address, .address },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        return types.PerpConfig{
            .perp = perp,
            .modules = .{
                .beacon = result[0].address,
                .fees = result[1].address,
                .funding = result[2].address,
                .margin_ratios = result[3].address,
                .price_impact = result[4].address,
                .pricing = result[5].address,
            },
        };
    }

    fn fetchMarkPrice(self: *Self, perp: types.Address) !f64 {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            perp,
            perp_abi.pool_state_selector,
            &.{},
            &.{ .int256, .uint256, .uint256, .uint256 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        const sqrt_price_x96: u256 = result[1].uint256;
        const price = try conversions.sqrtPriceX96ToPrice(sqrt_price_x96);
        self.state_cache.putMarkPrice(perp, price, now()) catch {};
        return price;
    }

    pub fn getMarkPriceCached(self: *Self, perp: types.Address) !f64 {
        if (self.state_cache.getMarkPrice(perp, now())) |cached_price| {
            return cached_price;
        }
        return self.fetchMarkPrice(perp);
    }

    fn fetchUsdcBalance(self: *Self, address: types.Address) !f64 {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            self.deployments.usdc,
            erc20_abi.balance_of_selector,
            &.{.{ .address = address }},
            &.{.uint256},
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        const raw_balance: u256 = result[0].uint256;
        // Convert via u128 intermediate to avoid LLVM aarch64 bug with u256->f64.
        const balance_128: u128 = @intCast(raw_balance);
        return @as(f64, @floatFromInt(balance_128)) / constants.F64_1E6;
    }
};

/// Identifier for a position in `getUserData`. `is_maker` is supplied by the
/// caller because v0.1.0 stores it implicitly in `Perp.makers` / `Perp.takers`
/// rather than on the Position struct.
pub const PerpPositionId = struct {
    perp: types.Address,
    position_id: u256,
    is_maker: bool,
};

fn uintToRatio(value: u256) f64 {
    const v128: u128 = @intCast(value);
    return @as(f64, @floatFromInt(v128)) / constants.F64_1E6;
}

/// Build a `Bounds` from the three 1e6-scaled margin ratios returned by
/// IMarginRatios (taker or maker), deriving `max_leverage` from the init ratio.
fn boundsFromRatios(init_ratio: u256, liq_ratio: u256, backstop_ratio: u256) types.Bounds {
    return types.Bounds{
        .init_margin_ratio = uintToRatio(init_ratio),
        .liq_margin_ratio = uintToRatio(liq_ratio),
        .backstop_margin_ratio = uintToRatio(backstop_ratio),
        .max_leverage = if (init_ratio == 0) 0.0 else (constants.F64_1E6 / @as(f64, @floatFromInt(@as(u64, @intCast(init_ratio))))),
    };
}
