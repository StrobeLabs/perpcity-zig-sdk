const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const constants = @import("constants.zig");
const conversions = @import("conversions.zig");
const context_mod = @import("context.zig");
const open_position_mod = @import("open_position.zig");
const perp_manager_abi = @import("abi/perp_manager_abi.zig");

const contract = eth.contract;
const AbiValue = eth.abi_encode.AbiValue;
const keccak = eth.keccak;

const PerpCityContext = context_mod.PerpCityContext;
const OpenPosition = open_position_mod.OpenPosition;

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

pub const PerpManagerError = error{
    MarginMustBePositive,
    LeverageMustBePositive,
    InvalidPriceRange,
    MarginRatioOutOfRange,
    ModuleAddressRequired,
    TransactionReverted,
    EventDecodeFailed,
    RpcError,
};

// ---------------------------------------------------------------------------
// Event topic hashes (computed at comptime)
// ---------------------------------------------------------------------------

const PERP_CREATED_TOPIC = keccak.comptimeHash("PerpCreated(bytes32)");
const POSITION_OPENED_TOPIC = keccak.comptimeHash("PositionOpened(bytes32,uint256,bool)");
const POSITION_CLOSED_TOPIC = keccak.comptimeHash("PositionClosed(bytes32,uint256)");

// ---------------------------------------------------------------------------
// createPerp
// ---------------------------------------------------------------------------

pub fn createPerp(ctx: *PerpCityContext, params: types.CreatePerpParams) !types.Bytes32 {
    const fees_addr = params.fees orelse ctx.deployments.fees_module orelse types.ZERO_ADDRESS;
    const margin_ratios_addr = params.margin_ratios orelse ctx.deployments.margin_ratios_module orelse types.ZERO_ADDRESS;
    const lockup_addr = params.lockup_period orelse ctx.deployments.lockup_period_module orelse types.ZERO_ADDRESS;
    const sqrt_limit_addr = params.sqrt_price_impact_limit orelse ctx.deployments.sqrt_price_impact_limit_module orelse types.ZERO_ADDRESS;

    const tx_hash = try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_manager,
        perp_manager_abi.create_perp_selector,
        &.{.{ .tuple = &.{
            .{ .address = params.beacon },
            .{ .address = fees_addr },
            .{ .address = margin_ratios_addr },
            .{ .address = lockup_addr },
            .{ .address = sqrt_limit_addr },
        } }},
    );

    const receipt = (try ctx.wallet.waitForReceipt(tx_hash, 10)) orelse
        return PerpManagerError.EventDecodeFailed;

    // Decode PerpCreated event from logs
    for (receipt.logs) |log| {
        if (log.topics.len >= 2) {
            if (std.mem.eql(u8, &log.topics[0], &PERP_CREATED_TOPIC)) {
                return log.topics[1];
            }
        }
    }

    return PerpManagerError.EventDecodeFailed;
}

// ---------------------------------------------------------------------------
// openTakerPosition
// ---------------------------------------------------------------------------

pub fn openTakerPosition(
    ctx: *PerpCityContext,
    perp_id: types.Bytes32,
    params: types.OpenTakerPositionParams,
) !OpenPosition {
    if (params.margin <= 0.0) {
        return PerpManagerError.MarginMustBePositive;
    }
    if (params.leverage <= 0.0) {
        return PerpManagerError.LeverageMustBePositive;
    }

    const margin_scaled_i128 = try conversions.scale6Decimals(params.margin);
    if (margin_scaled_i128 <= 0) {
        return PerpManagerError.MarginMustBePositive;
    }
    const margin_scaled: u128 = @intCast(margin_scaled_i128);

    const margin_ratio_f = @floor(constants.F64_1E6 / params.leverage);
    if (margin_ratio_f < 1.0 or margin_ratio_f > constants.F64_1E6) {
        return PerpManagerError.MarginRatioOutOfRange;
    }
    const margin_ratio: u24 = @intFromFloat(margin_ratio_f);

    const holder = try ctx.wallet.address();

    const perp_id_fb = context_mod.bytes32ToFixedBytes(perp_id);

    const tx_hash = try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_manager,
        perp_manager_abi.open_taker_pos_selector,
        &.{
            .{ .fixed_bytes = perp_id_fb },
            .{ .tuple = &.{
                .{ .address = holder },
                .{ .boolean = params.is_long },
                .{ .uint256 = @as(u256, margin_scaled) },
                .{ .uint256 = @as(u256, margin_ratio) },
                .{ .uint256 = @as(u256, params.unspecified_amount_limit) },
            } },
        },
    );

    const receipt = (try ctx.wallet.waitForReceipt(tx_hash, 10)) orelse
        return PerpManagerError.EventDecodeFailed;

    // Decode PositionOpened event to get posId
    for (receipt.logs) |log| {
        if (log.topics.len >= 3) {
            if (std.mem.eql(u8, &log.topics[0], &POSITION_OPENED_TOPIC)) {
                const pos_id: u256 = @bitCast(log.topics[2]);
                return OpenPosition{
                    .ctx = ctx,
                    .perp_id = perp_id,
                    .position_id = pos_id,
                    .is_long = params.is_long,
                    .is_maker = false,
                    .tx_hash = tx_hash,
                };
            }
        }
    }

    return PerpManagerError.EventDecodeFailed;
}

// ---------------------------------------------------------------------------
// openMakerPosition
// ---------------------------------------------------------------------------

pub fn openMakerPosition(
    ctx: *PerpCityContext,
    perp_id: types.Bytes32,
    params: types.OpenMakerPositionParams,
) !OpenPosition {
    if (params.margin <= 0.0) {
        return PerpManagerError.MarginMustBePositive;
    }
    if (params.price_lower >= params.price_upper) {
        return PerpManagerError.InvalidPriceRange;
    }
    if (params.price_lower <= 0.0) {
        return PerpManagerError.InvalidPriceRange;
    }

    const tick_lower_raw = try conversions.priceToTick(params.price_lower, true);
    const tick_upper_raw = try conversions.priceToTick(params.price_upper, false);

    // Align ticks to tick spacing
    const perp_data = try ctx.getPerpData(perp_id);
    const tick_lower: i24 = @intCast(alignTickDown(tick_lower_raw, perp_data.tick_spacing));
    const tick_upper: i24 = @intCast(alignTickUp(tick_upper_raw, perp_data.tick_spacing));

    const margin_scaled_i128 = try conversions.scale6Decimals(params.margin);
    if (margin_scaled_i128 <= 0) {
        return PerpManagerError.MarginMustBePositive;
    }
    const margin_scaled: u128 = @intCast(margin_scaled_i128);

    const holder = try ctx.wallet.address();

    const perp_id_fb = context_mod.bytes32ToFixedBytes(perp_id);

    const tx_hash = try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_manager,
        perp_manager_abi.open_maker_pos_selector,
        &.{
            .{ .fixed_bytes = perp_id_fb },
            .{ .tuple = &.{
                .{ .address = holder },
                .{ .uint256 = @as(u256, margin_scaled) },
                .{ .uint256 = @as(u256, @as(u120, @intCast(params.liquidity))) },
                .{ .int256 = @as(i256, tick_lower) },
                .{ .int256 = @as(i256, tick_upper) },
                .{ .uint256 = @as(u256, params.max_amt0_in) },
                .{ .uint256 = @as(u256, params.max_amt1_in) },
            } },
        },
    );

    const receipt = (try ctx.wallet.waitForReceipt(tx_hash, 10)) orelse
        return PerpManagerError.EventDecodeFailed;

    for (receipt.logs) |log| {
        if (log.topics.len >= 3) {
            if (std.mem.eql(u8, &log.topics[0], &POSITION_OPENED_TOPIC)) {
                const pos_id: u256 = @bitCast(log.topics[2]);
                return OpenPosition{
                    .ctx = ctx,
                    .perp_id = perp_id,
                    .position_id = pos_id,
                    .is_long = null,
                    .is_maker = true,
                    .tx_hash = tx_hash,
                };
            }
        }
    }

    return PerpManagerError.EventDecodeFailed;
}

// ---------------------------------------------------------------------------
// closePosition
// ---------------------------------------------------------------------------

pub fn closePosition(
    ctx: *PerpCityContext,
    perp_id: types.Bytes32,
    position_id: u256,
    params: types.ClosePositionParams,
) !types.ClosePositionResult {
    const tx_hash = try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_manager,
        perp_manager_abi.close_position_selector,
        &.{.{ .tuple = &.{
            .{ .uint256 = position_id },
            .{ .uint256 = @as(u256, params.min_amt0_out) },
            .{ .uint256 = @as(u256, params.min_amt1_out) },
            .{ .uint256 = @as(u256, params.max_amt1_in) },
        } }},
    );

    const receipt = (try ctx.wallet.waitForReceipt(tx_hash, 10)) orelse
        return PerpManagerError.EventDecodeFailed;

    // Check for PositionOpened event (partial close -- new residual position)
    for (receipt.logs) |log| {
        if (log.topics.len >= 3) {
            if (std.mem.eql(u8, &log.topics[0], &POSITION_OPENED_TOPIC)) {
                const new_pos_id: u256 = @bitCast(log.topics[2]);
                if (new_pos_id != position_id) {
                    const new_data = try ctx.getOpenPositionData(perp_id, new_pos_id, true, false);
                    return .{
                        .position = new_data,
                        .tx_hash = tx_hash,
                    };
                }
            }
        }
    }

    // No PositionOpened with new ID = full close
    return .{
        .position = null,
        .tx_hash = tx_hash,
    };
}

// ---------------------------------------------------------------------------
// adjustNotional
// ---------------------------------------------------------------------------

pub fn adjustNotional(ctx: *PerpCityContext, params: types.AdjustNotionalParams) !types.Bytes32 {
    const usd_delta_i256: i256 = @intCast(params.usd_delta);
    return try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_manager,
        perp_manager_abi.adjust_notional_selector,
        &.{.{ .tuple = &.{
            .{ .uint256 = params.position_id },
            .{ .int256 = usd_delta_i256 },
            .{ .uint256 = @as(u256, params.perp_limit) },
        } }},
    );
}

// ---------------------------------------------------------------------------
// adjustMargin
// ---------------------------------------------------------------------------

pub fn adjustMargin(ctx: *PerpCityContext, params: types.AdjustMarginParams) !types.Bytes32 {
    const margin_delta_i256: i256 = @intCast(params.margin_delta);
    return try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_manager,
        perp_manager_abi.adjust_margin_selector,
        &.{.{ .tuple = &.{
            .{ .uint256 = params.position_id },
            .{ .int256 = margin_delta_i256 },
        } }},
    );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

pub fn alignTickDown(tick: i32, tick_spacing: i24) i32 {
    const spacing: i32 = @as(i32, tick_spacing);
    if (spacing <= 0) return tick;
    return @divFloor(tick, spacing) * spacing;
}

pub fn alignTickUp(tick: i32, tick_spacing: i24) i32 {
    const spacing: i32 = @as(i32, tick_spacing);
    if (spacing <= 0) return tick;
    const adjusted = tick + spacing - 1;
    return @divFloor(adjusted, spacing) * spacing;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "alignTickDown rounds toward negative infinity" {
    try std.testing.expectEqual(@as(i32, 60), alignTickDown(105, 60));
    try std.testing.expectEqual(@as(i32, -120), alignTickDown(-105, 60));
    try std.testing.expectEqual(@as(i32, 60), alignTickDown(60, 60));
    try std.testing.expectEqual(@as(i32, 0), alignTickDown(0, 60));
}

test "alignTickUp rounds toward positive infinity" {
    try std.testing.expectEqual(@as(i32, 120), alignTickUp(105, 60));
    try std.testing.expectEqual(@as(i32, -60), alignTickUp(-105, 60));
    try std.testing.expectEqual(@as(i32, 60), alignTickUp(60, 60));
    try std.testing.expectEqual(@as(i32, 0), alignTickUp(0, 60));
}
