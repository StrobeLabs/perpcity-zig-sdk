const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const constants = @import("constants.zig");
const conversions = @import("conversions.zig");
const approve_mod = @import("approve.zig");
const state_cache_mod = @import("state_cache.zig");
const perp_manager_abi = @import("abi/perp_manager_abi.zig");
const fees_abi = @import("abi/fees_abi.zig");
const margin_ratios_abi = @import("abi/margin_ratios_abi.zig");
const erc20_abi = @import("abi/erc20_abi.zig");

const Wallet = eth.wallet.Wallet;
const Provider = eth.provider.Provider;
const HttpTransport = eth.http_transport.HttpTransport;
const contract = eth.contract;
const AbiValue = eth.abi_encode.AbiValue;
const AbiType = eth.abi_types.AbiType;
const abi_decode = eth.abi_decode;

/// Cache time-to-live in seconds (5 minutes).
const CACHE_TTL_SECONDS: i64 = 300;

pub const CacheEntry = struct {
    value: types.PerpConfig,
    expires_at: i64,
};

/// Main client context for interacting with the PerpCity protocol.
pub const PerpCityContext = struct {
    allocator: std.mem.Allocator,
    transport: HttpTransport,
    provider: Provider,
    wallet: Wallet,
    deployments: types.PerpCityDeployments,
    config_cache: std.AutoHashMap(types.Bytes32, CacheEntry),
    state_cache: state_cache_mod.StateCache,
    rpc_url: []const u8,
    is_approved: bool,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        rpc_url: []const u8,
        private_key: [32]u8,
        deployments: types.PerpCityDeployments,
    ) Self {
        var transport = HttpTransport.init(allocator, rpc_url);
        var provider = Provider.init(allocator, &transport);
        const wallet = Wallet.init(allocator, private_key, &provider);

        return Self{
            .allocator = allocator,
            .transport = transport,
            .provider = provider,
            .wallet = wallet,
            .deployments = deployments,
            .config_cache = std.AutoHashMap(types.Bytes32, CacheEntry).init(allocator),
            .state_cache = state_cache_mod.StateCache.init(allocator, .{}),
            .rpc_url = rpc_url,
            .is_approved = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.state_cache.deinit();
        self.config_cache.deinit();
        self.transport.deinit();
    }

    /// Fix up internal pointers after init (provider -> transport, wallet -> provider).
    /// Must be called after init since Zig moves invalidate pointers.
    pub fn fixPointers(self: *Self) void {
        self.provider.transport = &self.transport;
        self.wallet.provider = &self.provider;
    }

    // -----------------------------------------------------------------
    // Approval helpers
    // -----------------------------------------------------------------

    pub fn setupForTrading(self: *Self) !void {
        const owner = try self.wallet.address();

        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.usdc,
            erc20_abi.allowance_selector,
            &.{ .{ .address = owner }, .{ .address = self.deployments.perp_manager } },
            &.{.uint256},
        );
        defer contract.freeReturnValues(result, self.allocator);

        const current_allowance: u256 = result[0].uint256;
        const threshold: u256 = std.math.maxInt(u256) / 2;

        if (current_allowance < threshold) {
            _ = try approve_mod.approveUsdcMax(self);
        }

        self.is_approved = true;
    }

    pub fn ensureApproval(self: *Self) !void {
        if (!self.is_approved) {
            try self.setupForTrading();
        }
    }

    // -----------------------------------------------------------------
    // Cache helpers
    // -----------------------------------------------------------------

    fn now() i64 {
        return std.time.timestamp();
    }

    fn getCached(self: *Self, perp_id: types.Bytes32) ?types.PerpConfig {
        const entry = self.config_cache.get(perp_id) orelse return null;
        if (now() >= entry.expires_at) {
            return null;
        }
        return entry.value;
    }

    fn putCache(self: *Self, perp_id: types.Bytes32, config_val: types.PerpConfig) !void {
        try self.config_cache.put(perp_id, .{
            .value = config_val,
            .expires_at = now() + CACHE_TTL_SECONDS,
        });
    }

    // -----------------------------------------------------------------
    // Public read methods
    // -----------------------------------------------------------------

    pub fn getPerpConfig(self: *Self, perp_id: types.Bytes32) !types.PerpConfig {
        if (self.getCached(perp_id)) |cached| {
            return cached;
        }

        const config_val = try self.fetchPerpConfigFromChain(perp_id);
        try self.putCache(perp_id, config_val);
        return config_val;
    }

    pub fn getPerpData(self: *Self, perp_id: types.Bytes32) !types.PerpData {
        const config_val = try self.getPerpConfig(perp_id);

        const fees = try self.fetchFees(config_val.fees);
        const bounds = try self.fetchBounds(config_val.margin_ratios);
        const mark = try self.fetchMarkPrice(perp_id);

        return types.PerpData{
            .id = perp_id,
            .tick_spacing = config_val.key.tick_spacing,
            .mark = mark,
            .beacon = config_val.beacon,
            .bounds = bounds,
            .fees = fees,
        };
    }

    pub fn getUserData(
        self: *Self,
        address: types.Address,
        positions: []const u256,
    ) !types.UserData {
        const balance = try self.fetchUsdcBalance(address);

        var open_list = std.ArrayList(types.OpenPositionData).init(self.allocator);
        defer open_list.deinit();

        for (positions) |pos_id| {
            const raw = try self.getPositionRawData(pos_id);
            const open = try self.getOpenPositionData(raw.perp_id, pos_id, true, false);
            try open_list.append(open);
        }

        const owned_slice = try open_list.toOwnedSlice();

        return types.UserData{
            .wallet_address = address,
            .usdc_balance = balance,
            .open_positions = owned_slice,
        };
    }

    pub fn getPositionRawData(self: *Self, pos_id: u256) !types.PositionRawData {
        var fb: AbiValue.FixedBytes = .{ .len = 32 };
        @memcpy(&fb.data, &pos_id_to_bytes32(pos_id));

        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.positions_selector,
            &.{.{ .uint256 = pos_id }},
            // Flattened outputs: bytes32, uint256, int256, int256, int256, uint256, uint256,
            //                    uint256, uint256, uint256 (tuple components), int256, int256, uint256
            &.{ .bytes32, .uint256, .int256, .int256, .int256, .uint256, .uint256, .uint256, .uint256, .uint256, .int256, .int256, .uint256 },
        );
        defer contract.freeReturnValues(result, self.allocator);

        return types.PositionRawData{
            .perp_id = result[0].fixed_bytes.data,
            .position_id = pos_id,
            .margin = conversions.scaleFrom6Decimals(@intCast(result[1].uint256)),
            .entry_perp_delta = result[2].int256,
            .entry_usd_delta = result[3].int256,
            .margin_ratios = .{
                .min = @intCast(result[7].uint256),
                .max = @intCast(result[8].uint256),
                .liq = @intCast(result[9].uint256),
            },
        };
    }

    pub fn getOpenPositionData(
        self: *Self,
        perp_id: types.Bytes32,
        pos_id: u256,
        is_long: bool,
        is_maker: bool,
    ) !types.OpenPositionData {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.quote_close_position_selector,
            &.{.{ .uint256 = pos_id }},
            &.{ .bytes, .int256, .int256, .int256, .bool, .uint256 },
        );
        defer contract.freeReturnValues(result, self.allocator);

        const live = types.LiveDetails{
            .pnl = conversions.scaleFrom6Decimals(@intCast(result[1].int256)),
            .funding_payment = conversions.scaleFrom6Decimals(@intCast(result[2].int256)),
            .effective_margin = conversions.scaleFrom6Decimals(@intCast(result[3].int256)),
            .is_liquidatable = result[4].boolean,
        };

        return types.OpenPositionData{
            .perp_id = perp_id,
            .position_id = pos_id,
            .is_long = is_long,
            .is_maker = is_maker,
            .live_details = live,
        };
    }

    pub fn getFundingRate(self: *Self, perp_id: types.Bytes32) !i256 {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.funding_per_second_x96_selector,
            &.{.{ .fixed_bytes = bytes32ToFixedBytes(perp_id) }},
            &.{.int256},
        );
        defer contract.freeReturnValues(result, self.allocator);
        return result[0].int256;
    }

    pub fn getUtilFee(self: *Self, perp_id: types.Bytes32) !u256 {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.util_fee_per_sec_x96_selector,
            &.{.{ .fixed_bytes = bytes32ToFixedBytes(perp_id) }},
            &.{.uint256},
        );
        defer contract.freeReturnValues(result, self.allocator);
        return result[0].uint256;
    }

    pub fn getInsurance(self: *Self, perp_id: types.Bytes32) !u128 {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.insurance_selector,
            &.{.{ .fixed_bytes = bytes32ToFixedBytes(perp_id) }},
            &.{.uint256},
        );
        defer contract.freeReturnValues(result, self.allocator);
        return @intCast(result[0].uint256);
    }

    pub fn getOpenInterest(self: *Self, perp_id: types.Bytes32) !types.OpenInterest {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.taker_open_interest_selector,
            &.{.{ .fixed_bytes = bytes32ToFixedBytes(perp_id) }},
            &.{ .uint256, .uint256 },
        );
        defer contract.freeReturnValues(result, self.allocator);
        return types.OpenInterest{
            .long_oi = @intCast(result[0].uint256),
            .short_oi = @intCast(result[1].uint256),
        };
    }

    // -----------------------------------------------------------------
    // Private chain-reading helpers
    // -----------------------------------------------------------------

    fn fetchPerpConfigFromChain(self: *Self, perp_id: types.Bytes32) !types.PerpConfig {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.cfgs_selector,
            &.{.{ .fixed_bytes = bytes32ToFixedBytes(perp_id) }},
            // Flattened: 5 tuple components + 7 addresses = 12 values
            &.{ .address, .address, .uint256, .int256, .address, .address, .address, .address, .address, .address, .address, .address },
        );
        defer contract.freeReturnValues(result, self.allocator);

        return types.PerpConfig{
            .key = .{
                .currency0 = result[0].address,
                .currency1 = result[1].address,
                .fee = @intCast(result[2].uint256),
                .tick_spacing = @intCast(result[3].int256),
                .hooks = result[4].address,
            },
            .creator = result[5].address,
            .vault = result[6].address,
            .beacon = result[7].address,
            .fees = result[8].address,
            .margin_ratios = result[9].address,
            .lockup_period = result[10].address,
            .sqrt_price_impact_limit = result[11].address,
        };
    }

    fn fetchFees(self: *Self, fees_addr: types.Address) !types.Fees {
        const creator = try readSingleUint(self, fees_addr, fees_abi.creator_fee_selector);
        const insurance_val = try readSingleUint(self, fees_addr, fees_abi.insurance_fee_selector);
        const lp = try readSingleUint(self, fees_addr, fees_abi.lp_fee_selector);
        const liquidation = try readSingleUint(self, fees_addr, fees_abi.liquidation_fee_selector);

        return types.Fees{
            .creator_fee = @as(f64, @floatFromInt(creator)) / constants.F64_1E6,
            .insurance_fee = @as(f64, @floatFromInt(insurance_val)) / constants.F64_1E6,
            .lp_fee = @as(f64, @floatFromInt(lp)) / constants.F64_1E6,
            .liquidation_fee = @as(f64, @floatFromInt(liquidation)) / constants.F64_1E6,
        };
    }

    fn fetchBounds(self: *Self, margin_ratios_addr: types.Address) !types.Bounds {
        const min_taker = try readSingleUint(self, margin_ratios_addr, margin_ratios_abi.min_taker_ratio_selector);
        const max_taker = try readSingleUint(self, margin_ratios_addr, margin_ratios_abi.max_taker_ratio_selector);
        const liq_taker = try readSingleUint(self, margin_ratios_addr, margin_ratios_abi.liquidation_taker_ratio_selector);

        return types.Bounds{
            .min_margin = conversions.marginRatioToLeverage(min_taker) catch 0.0,
            .min_taker_leverage = conversions.marginRatioToLeverage(max_taker) catch 0.0,
            .max_taker_leverage = conversions.marginRatioToLeverage(min_taker) catch 0.0,
            .liquidation_taker_ratio = @as(f64, @floatFromInt(liq_taker)) / constants.F64_1E6,
        };
    }

    fn fetchMarkPrice(self: *Self, perp_id: types.Bytes32) !f64 {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.perp_manager,
            perp_manager_abi.time_weighted_avg_sqrt_price_x96_selector,
            &.{ .{ .fixed_bytes = bytes32ToFixedBytes(perp_id) }, .{ .uint256 = 1 } },
            &.{.uint256},
        );
        defer contract.freeReturnValues(result, self.allocator);

        const sqrt_price_x96: u256 = result[0].uint256;
        const price = conversions.sqrtPriceX96ToPrice(sqrt_price_x96);
        self.state_cache.putMarkPrice(perp_id, price, now()) catch {};
        return price;
    }

    pub fn getMarkPriceCached(self: *Self, perp_id: types.Bytes32) !f64 {
        if (self.state_cache.getMarkPrice(perp_id, now())) |cached_price| {
            return cached_price;
        }
        return self.fetchMarkPrice(perp_id);
    }

    fn fetchUsdcBalance(self: *Self, address: types.Address) !f64 {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            self.deployments.usdc,
            erc20_abi.balance_of_selector,
            &.{.{ .address = address }},
            &.{.uint256},
        );
        defer contract.freeReturnValues(result, self.allocator);

        const raw_balance: u256 = result[0].uint256;
        // Convert via u128 intermediate to avoid LLVM aarch64 bug with u256->f64
        const balance_128: u128 = @intCast(raw_balance);
        return @as(f64, @floatFromInt(balance_128)) / constants.F64_1E6;
    }

    // -----------------------------------------------------------------
    // Helper to read a single uint256 value from a view function
    // -----------------------------------------------------------------

    fn readSingleUint(self: *Self, to: types.Address, sel: [4]u8) !u256 {
        const result = try contract.contractRead(
            self.allocator,
            &self.provider,
            to,
            sel,
            &.{},
            &.{.uint256},
        );
        defer contract.freeReturnValues(result, self.allocator);
        return result[0].uint256;
    }
};

// -----------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------

pub fn bytes32ToFixedBytes(data: [32]u8) AbiValue.FixedBytes {
    var fb: AbiValue.FixedBytes = .{ .len = 32 };
    @memcpy(&fb.data, &data);
    return fb;
}

fn pos_id_to_bytes32(pos_id: u256) [32]u8 {
    _ = pos_id;
    return [_]u8{0} ** 32;
}
