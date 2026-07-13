const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const constants = @import("constants.zig");
const conversions = @import("conversions.zig");
const context_mod = @import("context.zig");
const open_position_mod = @import("open_position.zig");
const chain_client = @import("chain_client.zig");
const perp_abi = @import("abi/perp_abi.zig");

const AbiValue = eth.abi_encode.AbiValue;

const PerpCityContext = context_mod.PerpCityContext;
const OpenPosition = open_position_mod.OpenPosition;

pub const PerpError = error{
    MarginMustBePositive,
    PerpDeltaMustBeNonZero,
    InvalidPriceRange,
    TransactionReverted,
    EventDecodeFailed,
};

// ---------------------------------------------------------------------------
// openTaker
// ---------------------------------------------------------------------------

/// The `(to, selector, args)` for an `openTaker` call. Built once from the
/// params so the write path and the `simulate` preflight encode byte-identical
/// calldata. `tuple` is the single ABI struct argument; callers wrap it as
/// `&.{.{ .tuple = &self.tuple }}`.
const OpenTakerCall = struct {
    to: types.Address,
    selector: [4]u8,
    tuple: [4]AbiValue,
};

fn buildOpenTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenTakerPositionParams,
) !OpenTakerCall {
    if (params.margin <= 0.0) return PerpError.MarginMustBePositive;
    if (params.perp_delta == 0) return PerpError.PerpDeltaMustBeNonZero;

    const margin_scaled_i128 = try conversions.scale6Decimals(params.margin);
    if (margin_scaled_i128 <= 0) return PerpError.MarginMustBePositive;
    const margin_scaled: u128 = @intCast(margin_scaled_i128);

    const holder = try ctx.client.address();

    return .{
        .to = perp,
        .selector = perp_abi.open_taker_selector,
        .tuple = .{
            .{ .address = holder },
            .{ .uint256 = @as(u256, margin_scaled) },
            .{ .int256 = params.perp_delta },
            .{ .uint256 = params.amt1_limit },
        },
    };
}

/// Submit an `openTaker` call against `perp`. Returns an `OpenPosition` whose
/// `position_id` is decoded from the `TakerOpened` event in the receipt.
pub fn openTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenTakerPositionParams,
) !OpenPosition {
    const c = try buildOpenTaker(ctx, perp, params);

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
        0,
    );

    const pos_id = try decodePositionId(ctx, tx_hash, perp, perp_abi.taker_opened_topic);

    return OpenPosition{
        .ctx = ctx,
        .perp = perp,
        .position_id = pos_id,
        .is_maker = false,
        .tx_hash = tx_hash,
    };
}

/// Opt-in revert preflight for `openTaker`: encodes the same calldata and runs
/// it through eth_call. Returns normally if the write would not revert;
/// propagates the revert as an error. Does not send a transaction.
pub fn simulateOpenTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenTakerPositionParams,
) !void {
    const c = try buildOpenTaker(ctx, perp, params);
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
    );
}

// ---------------------------------------------------------------------------
// openMaker
// ---------------------------------------------------------------------------

/// The `(to, selector, args)` for an `openMaker` call, shared by the write path
/// and the `simulate` preflight so both encode byte-identical calldata.
const OpenMakerCall = struct {
    to: types.Address,
    selector: [4]u8,
    tuple: [7]AbiValue,
};

fn buildOpenMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenMakerPositionParams,
) !OpenMakerCall {
    if (params.margin <= 0.0) return PerpError.MarginMustBePositive;
    if (params.price_lower >= params.price_upper) return PerpError.InvalidPriceRange;
    if (params.price_lower <= 0.0) return PerpError.InvalidPriceRange;

    const tick_lower_raw = try conversions.priceToTick(params.price_lower, true);
    const tick_upper_raw = try conversions.priceToTick(params.price_upper, false);

    const margin_scaled_i128 = try conversions.scale6Decimals(params.margin);
    if (margin_scaled_i128 <= 0) return PerpError.MarginMustBePositive;
    const margin_scaled: u128 = @intCast(margin_scaled_i128);

    const holder = try ctx.client.address();

    const tick_lower: i24 = @intCast(tick_lower_raw);
    const tick_upper: i24 = @intCast(tick_upper_raw);

    return .{
        .to = perp,
        .selector = perp_abi.open_maker_selector,
        .tuple = .{
            .{ .address = holder },
            .{ .uint256 = @as(u256, margin_scaled) },
            .{ .int256 = @as(i256, tick_lower) },
            .{ .int256 = @as(i256, tick_upper) },
            .{ .uint256 = @as(u256, params.liquidity) },
            .{ .uint256 = params.max_amt0_in },
            .{ .uint256 = params.max_amt1_in },
        },
    };
}

pub fn openMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenMakerPositionParams,
) !OpenPosition {
    const c = try buildOpenMaker(ctx, perp, params);

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
        0,
    );

    const pos_id = try decodePositionId(ctx, tx_hash, perp, perp_abi.maker_opened_topic);

    return OpenPosition{
        .ctx = ctx,
        .perp = perp,
        .position_id = pos_id,
        .is_maker = true,
        .tx_hash = tx_hash,
    };
}

/// Opt-in revert preflight for `openMaker`; see `simulateOpenTaker`.
pub fn simulateOpenMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenMakerPositionParams,
) !void {
    const c = try buildOpenMaker(ctx, perp, params);
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
    );
}

// ---------------------------------------------------------------------------
// adjustMaker / adjustTaker
// ---------------------------------------------------------------------------

/// The `(to, selector, args)` for an `adjustMaker` call, shared by the write
/// path and the `simulate` preflight.
const AdjustMakerCall = struct {
    to: types.Address,
    selector: [4]u8,
    tuple: [5]AbiValue,
};

fn buildAdjustMaker(perp: types.Address, params: types.AdjustMakerParams) AdjustMakerCall {
    return .{
        .to = perp,
        .selector = perp_abi.adjust_maker_selector,
        .tuple = .{
            .{ .uint256 = params.position_id },
            .{ .int256 = @as(i256, params.margin_delta) },
            .{ .int256 = @as(i256, params.liquidity_delta) },
            .{ .uint256 = params.amt0_limit },
            .{ .uint256 = params.amt1_limit },
        },
    };
}

pub fn adjustMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.AdjustMakerParams,
) !types.Bytes32 {
    const c = buildAdjustMaker(perp, params);
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
        0,
    );
}

/// Opt-in revert preflight for `adjustMaker`; see `simulateOpenTaker`.
pub fn simulateAdjustMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.AdjustMakerParams,
) !void {
    const c = buildAdjustMaker(perp, params);
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
    );
}

/// The `(to, selector, args)` for an `adjustTaker` call, shared by the write
/// path and the `simulate` preflight.
const AdjustTakerCall = struct {
    to: types.Address,
    selector: [4]u8,
    tuple: [4]AbiValue,
};

fn buildAdjustTaker(perp: types.Address, params: types.AdjustTakerParams) AdjustTakerCall {
    return .{
        .to = perp,
        .selector = perp_abi.adjust_taker_selector,
        .tuple = .{
            .{ .uint256 = params.position_id },
            .{ .int256 = @as(i256, params.margin_delta) },
            .{ .int256 = params.perp_delta },
            .{ .uint256 = params.amt1_limit },
        },
    };
}

pub fn adjustTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.AdjustTakerParams,
) !types.Bytes32 {
    const c = buildAdjustTaker(perp, params);
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
        0,
    );
}

/// Opt-in revert preflight for `adjustTaker`; see `simulateOpenTaker`.
pub fn simulateAdjustTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.AdjustTakerParams,
) !void {
    const c = buildAdjustTaker(perp, params);
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &.{.{ .tuple = &c.tuple }},
    );
}

// ---------------------------------------------------------------------------
// liquidate / backstop
// ---------------------------------------------------------------------------

/// The `(to, selector, args)` for a liquidate call. `liquidateMaker` and
/// `liquidateTaker` share the 2-arg `(posId, feeRecipient)` shape and differ
/// only by selector, so one builder serves both. Shared by the write path and
/// the `simulate` preflight.
const LiquidateCall = struct {
    to: types.Address,
    selector: [4]u8,
    args: [2]AbiValue,
};

fn buildLiquidate(perp: types.Address, selector: [4]u8, params: types.LiquidateParams) LiquidateCall {
    return .{
        .to = perp,
        .selector = selector,
        .args = .{
            .{ .uint256 = params.position_id },
            .{ .address = params.fee_recipient },
        },
    };
}

pub fn liquidateMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.LiquidateParams,
) !types.Bytes32 {
    const c = buildLiquidate(perp, perp_abi.liquidate_maker_selector, params);
    return chain_client.writeContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args, 0);
}

/// Opt-in revert preflight for `liquidateMaker`; see `simulateOpenTaker`.
pub fn simulateLiquidateMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.LiquidateParams,
) !void {
    const c = buildLiquidate(perp, perp_abi.liquidate_maker_selector, params);
    return chain_client.simulateContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args);
}

pub fn liquidateTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.LiquidateParams,
) !types.Bytes32 {
    const c = buildLiquidate(perp, perp_abi.liquidate_taker_selector, params);
    return chain_client.writeContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args, 0);
}

/// Opt-in revert preflight for `liquidateTaker`; see `simulateOpenTaker`.
pub fn simulateLiquidateTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.LiquidateParams,
) !void {
    const c = buildLiquidate(perp, perp_abi.liquidate_taker_selector, params);
    return chain_client.simulateContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args);
}

/// The `(to, selector, args)` for a backstop call. `backstopMaker` and
/// `backstopTaker` share the 3-arg `(posId, marginIn, positionRecipient)` shape
/// and differ only by selector. Shared by the write path and the `simulate`
/// preflight.
const BackstopCall = struct {
    to: types.Address,
    selector: [4]u8,
    args: [3]AbiValue,
};

fn buildBackstop(perp: types.Address, selector: [4]u8, params: types.BackstopParams) BackstopCall {
    return .{
        .to = perp,
        .selector = selector,
        .args = .{
            .{ .uint256 = params.position_id },
            .{ .uint256 = @as(u256, params.margin_in) },
            .{ .address = params.position_recipient },
        },
    };
}

pub fn backstopMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.BackstopParams,
) !types.Bytes32 {
    const c = buildBackstop(perp, perp_abi.backstop_maker_selector, params);
    return chain_client.writeContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args, 0);
}

/// Opt-in revert preflight for `backstopMaker`; see `simulateOpenTaker`.
pub fn simulateBackstopMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.BackstopParams,
) !void {
    const c = buildBackstop(perp, perp_abi.backstop_maker_selector, params);
    return chain_client.simulateContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args);
}

pub fn backstopTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.BackstopParams,
) !types.Bytes32 {
    const c = buildBackstop(perp, perp_abi.backstop_taker_selector, params);
    return chain_client.writeContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args, 0);
}

/// Opt-in revert preflight for `backstopTaker`; see `simulateOpenTaker`.
pub fn simulateBackstopTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.BackstopParams,
) !void {
    const c = buildBackstop(perp, perp_abi.backstop_taker_selector, params);
    return chain_client.simulateContract(&ctx.client, ctx.allocator, c.to, c.selector, &c.args);
}

// ---------------------------------------------------------------------------
// donate / touch / fee admin
// ---------------------------------------------------------------------------

pub fn donate(ctx: *PerpCityContext, perp: types.Address, amount: u128) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.donate_selector,
        &.{.{ .uint256 = @as(u256, amount) }},
        0,
    );
}

pub fn touch(ctx: *PerpCityContext, perp: types.Address) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.touch_selector,
        &.{},
        0,
    );
}

pub fn syncProtocolFee(ctx: *PerpCityContext, perp: types.Address) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.sync_protocol_fee_selector,
        &.{},
        0,
    );
}

pub fn collectCreatorFees(
    ctx: *PerpCityContext,
    perp: types.Address,
    recipient: types.Address,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.collect_creator_fees_selector,
        &.{.{ .address = recipient }},
        0,
    );
}

pub fn collectProtocolFees(
    ctx: *PerpCityContext,
    perp: types.Address,
    recipient: types.Address,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.collect_protocol_fees_selector,
        &.{.{ .address = recipient }},
        0,
    );
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Scan a transaction receipt for an event with `expected_topic` emitted by
/// `expected_emitter` and decode the position id from the first 32 bytes of
/// its log `data`. Returns `EventDecodeFailed` if no matching log is found,
/// or `TransactionReverted` if the receipt's status is not 1.
fn decodePositionId(
    ctx: *PerpCityContext,
    tx_hash: types.Bytes32,
    expected_emitter: types.Address,
    expected_topic: [32]u8,
) !u256 {
    const receipt = (try ctx.client.getReceipt(ctx.allocator, tx_hash, 10)) orelse
        return PerpError.EventDecodeFailed;

    if (receipt.status != 1) return PerpError.TransactionReverted;

    for (receipt.logs) |log| {
        if (!std.mem.eql(u8, &log.address, &expected_emitter)) continue;
        if (log.topics.len == 0) continue;
        if (!std.mem.eql(u8, &log.topics[0], &expected_topic)) continue;
        if (log.data.len < 32) continue;
        return u256FromBytes(log.data[0..32]);
    }

    return PerpError.EventDecodeFailed;
}

fn u256FromBytes(buf: *const [32]u8) u256 {
    var v: u256 = 0;
    for (buf) |b| {
        v = (v << 8) | @as(u256, b);
    }
    return v;
}
