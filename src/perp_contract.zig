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

/// Submit an `openTaker` call against `perp`. Returns an `OpenPosition` whose
/// `position_id` is decoded from the `TakerOpened` event in the receipt.
pub fn openTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenTakerPositionParams,
) !OpenPosition {
    if (params.margin <= 0.0) return PerpError.MarginMustBePositive;
    if (params.perp_delta == 0) return PerpError.PerpDeltaMustBeNonZero;

    const margin_scaled_i128 = try conversions.scale6Decimals(params.margin);
    if (margin_scaled_i128 <= 0) return PerpError.MarginMustBePositive;
    const margin_scaled: u128 = @intCast(margin_scaled_i128);

    const holder = try ctx.client.address();

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.open_taker_selector,
        &.{.{ .tuple = &.{
            .{ .address = holder },
            .{ .uint256 = @as(u256, margin_scaled) },
            .{ .int256 = params.perp_delta },
            .{ .uint256 = params.amt1_limit },
        } }},
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

// ---------------------------------------------------------------------------
// openMaker
// ---------------------------------------------------------------------------

pub fn openMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.OpenMakerPositionParams,
) !OpenPosition {
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

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.open_maker_selector,
        &.{.{ .tuple = &.{
            .{ .address = holder },
            .{ .uint256 = @as(u256, margin_scaled) },
            .{ .int256 = @as(i256, tick_lower) },
            .{ .int256 = @as(i256, tick_upper) },
            .{ .uint256 = @as(u256, params.liquidity) },
            .{ .uint256 = params.max_amt0_in },
            .{ .uint256 = params.max_amt1_in },
        } }},
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

// ---------------------------------------------------------------------------
// adjustMaker / adjustTaker
// ---------------------------------------------------------------------------

pub fn adjustMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.AdjustMakerParams,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.adjust_maker_selector,
        &.{.{ .tuple = &.{
            .{ .uint256 = params.position_id },
            .{ .int256 = @as(i256, params.margin_delta) },
            .{ .int256 = @as(i256, params.liquidity_delta) },
            .{ .uint256 = params.amt0_limit },
            .{ .uint256 = params.amt1_limit },
        } }},
        0,
    );
}

pub fn adjustTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.AdjustTakerParams,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.adjust_taker_selector,
        &.{.{ .tuple = &.{
            .{ .uint256 = params.position_id },
            .{ .int256 = @as(i256, params.margin_delta) },
            .{ .int256 = params.perp_delta },
            .{ .uint256 = params.amt1_limit },
        } }},
        0,
    );
}

// ---------------------------------------------------------------------------
// liquidate / backstop
// ---------------------------------------------------------------------------

pub fn liquidateMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.LiquidateParams,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.liquidate_maker_selector,
        &.{
            .{ .uint256 = params.position_id },
            .{ .address = params.fee_recipient },
        },
        0,
    );
}

pub fn liquidateTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.LiquidateParams,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.liquidate_taker_selector,
        &.{
            .{ .uint256 = params.position_id },
            .{ .address = params.fee_recipient },
        },
        0,
    );
}

pub fn backstopMaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.BackstopParams,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.backstop_maker_selector,
        &.{
            .{ .uint256 = params.position_id },
            .{ .uint256 = @as(u256, params.margin_in) },
            .{ .address = params.position_recipient },
        },
        0,
    );
}

pub fn backstopTaker(
    ctx: *PerpCityContext,
    perp: types.Address,
    params: types.BackstopParams,
) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        perp,
        perp_abi.backstop_taker_selector,
        &.{
            .{ .uint256 = params.position_id },
            .{ .uint256 = @as(u256, params.margin_in) },
            .{ .address = params.position_recipient },
        },
        0,
    );
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
