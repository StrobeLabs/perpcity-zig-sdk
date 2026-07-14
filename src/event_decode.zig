//! eth-dependent log decoder for the typed event structs in `events.zig`.
//!
//! This module is deliberately separate from `events.zig`: the event structs,
//! `EventType`, `Topics`, and the subscription registry stay eth-free so they
//! can live in the pure-math `math_root` module, while the decoder below needs
//! eth.zig's `receipt.Log` + `abi_decode`. Only `root.zig` re-exports this file.
//!
//! Layout notes (see perpcity-contracts `libraries/Events.sol` and the
//! `Topics` signatures in `events.zig`): every field the existing event structs
//! declare is a non-indexed parameter, so it lives in `log.data`; `topics[0]`
//! is used only to identify the event. Indexed parameters (e.g. the `owner` on
//! the Maker/Taker events) are not among the declared struct fields, so
//! `topics[1..]` is not consulted here. Should an indexed field ever be added
//! to a struct, decode it from `topics[1..]` (an address is the low 20 bytes of
//! its 32-byte topic).
//!
//! Nested static tuples (`Modules`, `OpenInterest`, `Capacity`, and the
//! `SwapResult` on `TakerClosed`) are ABI-encoded inline, so they are decoded
//! by flattening their leaf fields into the type list.

const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const events = @import("events.zig");

const Log = eth.receipt.Log;
const AbiType = eth.abi_types.AbiType;
const AbiValue = eth.abi_encode.AbiValue;

pub const EventType = events.EventType;

/// A decoded log, tagged by `EventType`. Each variant carries the matching
/// typed event struct from `events.zig`. The `new_block` tag exists to satisfy
/// the `union(EventType)` exhaustiveness requirement; `decodeEvent` never
/// produces it (there is no `new_block` log).
pub const DecodedEvent = union(EventType) {
    perp_created: events.PerpCreatedEvent,
    maker_opened: events.MakerOpenedEvent,
    maker_adjusted: events.MakerAdjustedEvent,
    maker_closed: events.MakerClosedEvent,
    maker_converted: events.MakerConvertedEvent,
    maker_backstopped: events.MakerBackstoppedEvent,
    taker_opened: events.TakerOpenedEvent,
    taker_adjusted: events.TakerAdjustedEvent,
    taker_closed: events.TakerClosedEvent,
    taker_backstopped: events.TakerBackstoppedEvent,
    donated: events.DonatedEvent,
    open_interest_updated: events.OpenInterestUpdatedEvent,
    capacity_updated: events.CapacityUpdatedEvent,
    index_updated: events.IndexUpdatedEvent,
    new_block: void,
};

/// Zero-valued `SwapResult`, used to fill the `sr` field of the taker events
/// whose nested tuple is intentionally left undecoded (see `decodeEvent`).
const empty_swap_result = events.SwapResult{
    .delta = 0,
    .amm_price = 0,
    .total_fee_amt = 0,
    .lp_fee_amt = 0,
    .protocol_fee_amt = 0,
    .creator_fee_amt = 0,
    .insurance_fee_amt = 0,
};

/// Decode a single log into its typed event struct.
///
/// Returns `null` when `topics[0]` matches no known event (or the log carries
/// no topics), so callers can skip unrecognized logs. The non-indexed fields
/// are decoded from `log.data`; the decoded `AbiValue`s hold no inner
/// allocations (every field is a static leaf), so they are freed with a plain
/// `allocator.free` inside this function and nothing is left for the caller.
pub fn decodeEvent(allocator: std.mem.Allocator, log: Log) !?DecodedEvent {
    if (log.topics.len == 0) return null;
    const event_type = events.identifyEvent(log.topics[0]) orelse return null;

    return switch (event_type) {
        .perp_created => blk: {
            // perp, poolId, Modules(6 addresses, inline), initialIndex,
            // emaWindow, protocolFee, sqrtPriceX96, tick, owner. The trailing
            // (name, symbol, tokenUri) strings are dynamic and sit after every
            // field the struct declares, so decoding the leading static words
            // ignores them safely.
            const v = try decode(allocator, log.data, &.{
                .address, .bytes32, .address, .address, .address,
                .address, .address, .address, .uint256, .uint24,
                .uint256, .uint160, .int24,   .address,
            });
            defer allocator.free(v);
            break :blk .{ .perp_created = .{
                .perp = v[0].address,
                .pool_id = v[1].fixed_bytes.data,
                .modules = .{
                    .beacon = v[2].address,
                    .fees = v[3].address,
                    .funding = v[4].address,
                    .margin_ratios = v[5].address,
                    .price_impact = v[6].address,
                    .pricing = v[7].address,
                },
                .initial_index = v[8].uint256,
                .ema_window = @intCast(v[9].uint256),
                .protocol_fee = v[10].uint256,
                .sqrt_price_x96 = v[11].uint256,
                .tick = @intCast(v[12].int256),
                .owner = v[13].address,
            } };
        },
        .maker_opened => blk: {
            const v = try decode(allocator, log.data, &.{.uint256});
            defer allocator.free(v);
            break :blk .{ .maker_opened = .{ .pos_id = v[0].uint256 } };
        },
        .maker_adjusted => blk: {
            const v = try decode(allocator, log.data, &.{
                .uint256, .int256, .uint256, .uint256, .uint256,
            });
            defer allocator.free(v);
            break :blk .{ .maker_adjusted = .{
                .pos_id = v[0].uint256,
                .funding = v[1].int256,
                .long_util_fees = v[2].uint256,
                .short_util_fees = v[3].uint256,
                .lp_fees = v[4].uint256,
            } };
        },
        .maker_closed => blk: {
            break :blk .{ .maker_closed = try decodeMakerCloseLike(allocator, log.data) };
        },
        .maker_converted => blk: {
            const c = try decodeMakerCloseLike(allocator, log.data);
            break :blk .{ .maker_converted = .{
                .pos_id = c.pos_id,
                .funding = c.funding,
                .long_util_fees = c.long_util_fees,
                .short_util_fees = c.short_util_fees,
                .lp_fees = c.lp_fees,
                .liq_fee = c.liq_fee,
                .is_liquidation = c.is_liquidation,
            } };
        },
        .maker_backstopped => blk: {
            const v = try decode(allocator, log.data, &.{
                .uint256, .uint128, .address, .int256, .uint256, .uint256, .uint256,
            });
            defer allocator.free(v);
            break :blk .{ .maker_backstopped = .{
                .pos_id = v[0].uint256,
                .margin_in = @intCast(v[1].uint256),
                .pos_recipient = v[2].address,
                .funding = v[3].int256,
                .long_util_fees = v[4].uint256,
                .short_util_fees = v[5].uint256,
                .lp_fees = v[6].uint256,
            } };
        },
        .taker_opened => blk: {
            // Only the leading `posId` is decoded; the trailing `SwapResult`
            // tuple is left zero-valued.
            // TODO: SwapResult fields not yet decoded.
            const v = try decode(allocator, log.data, &.{.uint256});
            defer allocator.free(v);
            break :blk .{ .taker_opened = .{
                .pos_id = v[0].uint256,
                .sr = empty_swap_result,
            } };
        },
        .taker_adjusted => blk: {
            // Only the leading `posId` is decoded; `sr`, `funding`, and
            // `util_fees` sit at/after the nested tuple and are left unset.
            // TODO: SwapResult fields not yet decoded.
            const v = try decode(allocator, log.data, &.{.uint256});
            defer allocator.free(v);
            break :blk .{ .taker_adjusted = .{
                .pos_id = v[0].uint256,
                .sr = empty_swap_result,
                .funding = 0,
                .util_fees = 0,
            } };
        },
        .taker_closed => blk: {
            // `SwapResult` is a fully static tuple, so it is ABI-encoded inline;
            // the trailing flat fields (funding/util_fees/liq_fee/isLiquidation)
            // are only reachable past it, so it is flattened and fully decoded
            // here (unlike taker_opened / taker_adjusted, whose flat fields all
            // precede the tuple).
            const v = try decode(allocator, log.data, &.{
                .uint256, // posId
                .int256, .uint256, .int256, .uint256, .uint256, .uint256, .uint256, // SwapResult
                .int256, // funding
                .uint256, // utilFees
                .uint256, // liqFee
                .bool, // isLiquidation
            });
            defer allocator.free(v);
            break :blk .{ .taker_closed = .{
                .pos_id = v[0].uint256,
                .sr = .{
                    .delta = v[1].int256,
                    .amm_price = v[2].uint256,
                    .total_fee_amt = v[3].int256,
                    .lp_fee_amt = v[4].uint256,
                    .protocol_fee_amt = v[5].uint256,
                    .creator_fee_amt = v[6].uint256,
                    .insurance_fee_amt = v[7].uint256,
                },
                .funding = v[8].int256,
                .util_fees = v[9].uint256,
                .liq_fee = v[10].uint256,
                .is_liquidation = v[11].boolean,
            } };
        },
        .taker_backstopped => blk: {
            const v = try decode(allocator, log.data, &.{
                .uint256, .uint128, .address, .int256, .uint256,
            });
            defer allocator.free(v);
            break :blk .{ .taker_backstopped = .{
                .pos_id = v[0].uint256,
                .margin_in = @intCast(v[1].uint256),
                .pos_recipient = v[2].address,
                .funding = v[3].int256,
                .util_fees = v[4].uint256,
            } };
        },
        .donated => blk: {
            const v = try decode(allocator, log.data, &.{
                .address, .uint128, .uint128, .uint80,
            });
            defer allocator.free(v);
            break :blk .{ .donated = .{
                .donor = v[0].address,
                .amount = @intCast(v[1].uint256),
                .bad_debt = @intCast(v[2].uint256),
                .insurance = @intCast(v[3].uint256),
            } };
        },
        .open_interest_updated => blk: {
            // OpenInterest(uint128 long, uint128 short) -- static, inline.
            const v = try decode(allocator, log.data, &.{ .uint128, .uint128 });
            defer allocator.free(v);
            break :blk .{ .open_interest_updated = .{ .oi = .{
                .long = @intCast(v[0].uint256),
                .short = @intCast(v[1].uint256),
            } } };
        },
        .capacity_updated => blk: {
            // Capacity(uint128 long, uint128 short) -- static, inline.
            const v = try decode(allocator, log.data, &.{ .uint128, .uint128 });
            defer allocator.free(v);
            break :blk .{ .capacity_updated = .{ .cap = .{
                .long = @intCast(v[0].uint256),
                .short = @intCast(v[1].uint256),
            } } };
        },
        .index_updated => blk: {
            const v = try decode(allocator, log.data, &.{.uint256});
            defer allocator.free(v);
            break :blk .{ .index_updated = .{ .index = v[0].uint256 } };
        },
        // Not a log-backed event; identifyEvent never returns it.
        .new_block => null,
    };
}

/// Decode the shared `(posId, funding, longUtilFees, shortUtilFees, lpFees,
/// liqFee, isLiquidation)` layout of `MakerClosed` / `MakerConverted`.
fn decodeMakerCloseLike(allocator: std.mem.Allocator, data: []const u8) !events.MakerClosedEvent {
    const v = try decode(allocator, data, &.{
        .uint256, .int256, .uint256, .uint256, .uint256, .uint256, .bool,
    });
    defer allocator.free(v);
    return .{
        .pos_id = v[0].uint256,
        .funding = v[1].int256,
        .long_util_fees = v[2].uint256,
        .short_util_fees = v[3].uint256,
        .lp_fees = v[4].uint256,
        .liq_fee = v[5].uint256,
        .is_liquidation = v[6].boolean,
    };
}

/// Thin wrapper over `eth.abi_decode.decodeValues`. Every type passed here is a
/// static leaf (int/uint/address/bool/bytesN), so the returned values own no
/// inner allocations and the caller frees the slice with `allocator.free`.
fn decode(allocator: std.mem.Allocator, data: []const u8, type_list: []const AbiType) ![]AbiValue {
    return eth.abi_decode.decodeValues(data, type_list, allocator);
}

test {
    std.testing.refAllDecls(@This());
}
