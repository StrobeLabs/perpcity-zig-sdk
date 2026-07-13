const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const constants = @import("constants.zig");
const conversions = @import("conversions.zig");
const approve_mod = @import("approve.zig");
const state_cache_mod = @import("state_cache.zig");
const chain_client = @import("chain_client.zig");
const perp_abi = @import("abi/perp_abi.zig");
const fees_abi = @import("abi/fees_abi.zig");
const margin_ratios_abi = @import("abi/margin_ratios_abi.zig");
const erc20_abi = @import("abi/erc20_abi.zig");

const ChainClient = chain_client.ChainClient;
const EthChainClient = chain_client.EthChainClient;

/// Cache time-to-live in seconds (5 minutes).
const CACHE_TTL_SECONDS: i64 = 300;

pub const CacheEntry = struct {
    value: types.PerpConfig,
    expires_at: i64,
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

        const fee_summary = try self.fetchFees(config_val.modules.fees);
        const taker_bounds = try self.fetchTakerBounds(config_val.modules.margin_ratios);
        const maker_bounds = try self.fetchMakerBounds(config_val.modules.margin_ratios);
        const mark = try self.fetchMarkPrice(perp);

        return types.PerpData{
            .perp = perp,
            .mark = mark,
            .beacon = config_val.modules.beacon,
            .taker_bounds = taker_bounds,
            .maker_bounds = maker_bounds,
            .fees = fee_summary,
        };
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

    fn fetchFees(self: *Self, fees_addr: types.Address) !types.Fees {
        const fees_res = try chain_client.readContract(
            &self.client,
            self.allocator,
            fees_addr,
            fees_abi.fees_selector,
            &.{},
            &.{ .uint256, .uint256, .uint256 },
        );
        defer chain_client.freeReturnValues(fees_res, self.allocator);

        const liq_res = try chain_client.readContract(
            &self.client,
            self.allocator,
            fees_addr,
            fees_abi.liq_fee_selector,
            &.{},
            &.{.uint256},
        );
        defer chain_client.freeReturnValues(liq_res, self.allocator);

        const creator: u256 = fees_res[0].uint256;
        const insurance: u256 = fees_res[1].uint256;
        const lp: u256 = fees_res[2].uint256;
        const liq: u256 = liq_res[0].uint256;

        return types.Fees{
            .creator_fee = uintToRatio(creator),
            .insurance_fee = uintToRatio(insurance),
            .lp_fee = uintToRatio(lp),
            .liquidation_fee = uintToRatio(liq),
        };
    }

    fn fetchTakerBounds(self: *Self, mr_addr: types.Address) !types.Bounds {
        return self.fetchBoundsHelper(mr_addr, margin_ratios_abi.taker_margin_ratios_selector);
    }

    fn fetchMakerBounds(self: *Self, mr_addr: types.Address) !types.Bounds {
        return self.fetchBoundsHelper(mr_addr, margin_ratios_abi.maker_margin_ratios_selector);
    }

    fn fetchBoundsHelper(self: *Self, mr_addr: types.Address, selector: [4]u8) !types.Bounds {
        const result = try chain_client.readContract(
            &self.client,
            self.allocator,
            mr_addr,
            selector,
            &.{},
            &.{ .uint256, .uint256, .uint256 },
        );
        defer chain_client.freeReturnValues(result, self.allocator);

        const init_ratio: u256 = result[0].uint256;
        const liq_ratio: u256 = result[1].uint256;
        const backstop_ratio: u256 = result[2].uint256;

        return types.Bounds{
            .init_margin_ratio = uintToRatio(init_ratio),
            .liq_margin_ratio = uintToRatio(liq_ratio),
            .backstop_margin_ratio = uintToRatio(backstop_ratio),
            .max_leverage = if (init_ratio == 0) 0.0 else (constants.F64_1E6 / @as(f64, @floatFromInt(@as(u64, @intCast(init_ratio))))),
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
