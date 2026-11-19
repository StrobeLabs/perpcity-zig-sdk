//! eth-dependent log decoder for the typed event structs in `events.zig`.
//!
//! This module is deliberately separate from `events.zig`: the event structs,
//! `EventType`, `Topics`, and the subscription registry stay eth-free so they
//! can live in the pure-math `math_root` module, while the decoder below needs
//! eth.zig's `receipt.Log` + `abi_decode`. Only `root.zig` re-exports this file.
//!
//! Layout notes (perpcity-contracts v1.0.0 `IPerp.sol`): `topics[0]` identifies
//! the event. Indexed parameters live in `topics[1..]` in declaration order -
//! `posId` on every position event, plus `owner` / `feeRecipient` where the
//! event has one - and are read with `topicU256` / `topicAddress` (an address is
//! the low 20 bytes of its 32-byte topic). Everything else is in `log.data`.
//!
//! Nested static tuples (`Modules`, `OpenInterest`, `Capacity`, `MakerFunding`,
//! `Rates`, `PricePair`, `SwapResult`) are ABI-encoded inline, so they are
//! decoded by flattening their leaf fields into the type list.

const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const events = @import("events.zig");

const Log = eth.receipt.Log;
const AbiType = eth.abi_types.AbiType;
const AbiValue = eth.abi_encode.AbiValue;

pub const EventType = events.EventType;

pub const DecodeError = error{
    /// The log has fewer topics than the event's indexed parameters require.
    MissingIndexedTopic,
};

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
    maker_liquidated: events.MakerLiquidatedEvent,
    maker_moved: events.MakerMovedEvent,
    taker_opened: events.TakerOpenedEvent,
    taker_adjusted: events.TakerAdjustedEvent,
    taker_closed: events.TakerClosedEvent,
    taker_backstopped: events.TakerBackstoppedEvent,
    taker_liquidated: events.TakerLiquidatedEvent,
    position_owner_updated: events.PositionOwnerUpdatedEvent,
    quote_folded: events.QuoteFoldedEvent,
    donated: events.DonatedEvent,
    open_interest_updated: events.OpenInterestUpdatedEvent,
    capacity_updated: events.CapacityUpdatedEvent,
    physical_capacity_updated: events.PhysicalCapacityUpdatedEvent,
    rates_and_emas_refreshed: events.RatesAndEmasRefreshedEvent,
    bad_debt_accounted: events.BadDebtAccountedEvent,
    index_updated: events.IndexUpdatedEvent,
    new_block: void,
};

/// The position id a `DecodedEvent` refers to, or `null` for market-wide events
/// that are not tied to a single position.
pub fn positionId(ev: DecodedEvent) ?u256 {
    return switch (ev) {
        .maker_opened => |e| e.pos_id,
        .maker_adjusted => |e| e.pos_id,
        .maker_closed => |e| e.pos_id,
        .maker_converted => |e| e.pos_id,
        .maker_backstopped => |e| e.pos_id,
        .maker_liquidated => |e| e.pos_id,
        .maker_moved => |e| e.pos_id,
        .taker_opened => |e| e.pos_id,
        .taker_adjusted => |e| e.pos_id,
        .taker_closed => |e| e.pos_id,
        .taker_backstopped => |e| e.pos_id,
        .taker_liquidated => |e| e.pos_id,
        .position_owner_updated => |e| e.pos_id,
        .quote_folded => |e| e.pos_id,
        .perp_created,
        .donated,
        .open_interest_updated,
        .capacity_updated,
        .physical_capacity_updated,
        .rates_and_emas_refreshed,
        .bad_debt_accounted,
        .index_updated,
        .new_block,
        => null,
    };
}

/// The indexed parameter held in `topics[i]`, as a u256.
pub fn topicU256(log: Log, i: usize) DecodeError!u256 {
    if (log.topics.len <= i) return DecodeError.MissingIndexedTopic;
    return std.mem.readInt(u256, &log.topics[i], .big);
}

/// The indexed address held in `topics[i]` (the low 20 bytes of the topic).
pub fn topicAddress(log: Log, i: usize) DecodeError!types.Address {
    if (log.topics.len <= i) return DecodeError.MissingIndexedTopic;
    return log.topics[i][12..32].*;
}

// Flattened leaf types of `SwapResult` (8 static words).
const swap_result_types = [_]AbiType{
    .int256, .uint256, .int256, .uint256, .uint256, .uint256, .uint256, .uint256,
};

fn swapResultAt(v: []const AbiValue, at: usize) events.SwapResult {
    return .{
        .delta = v[at].int256,
        .amm_price = v[at + 1].uint256,
        .total_fee_amt = v[at + 2].int256,
        .lp_fee_amt = v[at + 3].uint256,
        .protocol_fee_amt = v[at + 4].uint256,
        .creator_fee_amt = v[at + 5].uint256,
        .insurance_fee_amt = v[at + 6].uint256,
        .fee_fund_fee_amt = v[at + 7].uint256,
    };
}

/// Decode a single log into its typed event struct.
///
/// Returns `null` when `topics[0]` matches no known event (or the log carries
/// no topics), so callers can skip unrecognized logs. Indexed fields are read
/// from the topics and the rest from `log.data`; the decoded `AbiValue`s hold
/// no inner allocations (every field is a static leaf), so they are freed with
/// a plain `allocator.free` inside this function and nothing is left for the
/// caller.
pub fn decodeEvent(allocator: std.mem.Allocator, log: Log) !?DecodedEvent {
    if (log.topics.len == 0) return null;
    const event_type = events.identifyEvent(log.topics[0]) orelse return null;

    return switch (event_type) {
        .perp_created => blk: {
            // perp, poolId, Modules(6 addresses, inline), initialIndex,
            // emaWindow, latency, protocolFee, sqrtPriceX96, tick, owner.
            const v = try decode(allocator, log.data, &.{
                .address, .bytes32, .address, .address, .address,
                .address, .address, .address, .uint256, .uint24,
                .uint32,  .uint256, .uint160, .int24,   .address,
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
                .latency = @intCast(v[10].uint256),
                .protocol_fee = v[11].uint256,
                .sqrt_price_x96 = v[12].uint256,
                .tick = @intCast(v[13].int256),
                .owner = v[14].address,
            } };
        },
        .maker_opened => blk: {
            // tickLower, tickUpper, liquidity, delta, lastCumlFundingX96,
            // MakerFunding(belowX96, withinInventoryX192).
            const v = try decode(allocator, log.data, &.{
                .int24, .int24, .uint128, .int256, .int256, .int256, .int256,
            });
            defer allocator.free(v);
            break :blk .{ .maker_opened = .{
                .pos_id = try topicU256(log, 1),
                .owner = try topicAddress(log, 2),
                .tick_lower = @intCast(v[0].int256),
                .tick_upper = @intCast(v[1].int256),
                .liquidity = @intCast(v[2].uint256),
                .delta = v[3].int256,
                .last_cuml_funding_x96 = v[4].int256,
                .last_cuml_funding = .{
                    .below_x96 = v[5].int256,
                    .within_inventory_x192 = v[6].int256,
                },
            } };
        },
        .maker_adjusted => .{ .maker_adjusted = try decodeMakerLifecycle(allocator, log) },
        .maker_closed => .{ .maker_closed = try decodeMakerLifecycle(allocator, log) },
        .maker_converted => .{ .maker_converted = try decodeMakerLifecycle(allocator, log) },
        .maker_backstopped => blk: {
            // marginIn, posRecipient, funding, lpFees, margin, delta,
            // liquidity, lastCumlFundingX96, MakerFunding.
            const v = try decode(allocator, log.data, &.{
                .uint128, .address, .int256, .uint256, .uint128,
                .int256,  .uint128, .int256, .int256,  .int256,
            });
            defer allocator.free(v);
            break :blk .{ .maker_backstopped = .{
                .pos_id = try topicU256(log, 1),
                .margin_in = @intCast(v[0].uint256),
                .pos_recipient = v[1].address,
                .funding = v[2].int256,
                .lp_fees = v[3].uint256,
                .margin = @intCast(v[4].uint256),
                .delta = v[5].int256,
                .liquidity = @intCast(v[6].uint256),
                .last_cuml_funding_x96 = v[7].int256,
                .last_cuml_funding = .{
                    .below_x96 = v[8].int256,
                    .within_inventory_x192 = v[9].int256,
                },
            } };
        },
        .maker_liquidated => blk: {
            const v = try decode(allocator, log.data, &.{ .uint128, .uint256 });
            defer allocator.free(v);
            break :blk .{ .maker_liquidated = .{
                .pos_id = try topicU256(log, 1),
                .fee_recipient = try topicAddress(log, 2),
                .liquidity_amount = @intCast(v[0].uint256),
                .liq_fee = v[1].uint256,
            } };
        },
        .maker_moved => blk: {
            const v = try decode(allocator, log.data, &.{
                .int24,   .int24,  .int24,  .int24,   .uint128,
                .uint128, .int128, .int256, .uint256,
            });
            defer allocator.free(v);
            break :blk .{ .maker_moved = .{
                .pos_id = try topicU256(log, 1),
                .owner = try topicAddress(log, 2),
                .old_tick_lower = @intCast(v[0].int256),
                .old_tick_upper = @intCast(v[1].int256),
                .new_tick_lower = @intCast(v[2].int256),
                .new_tick_upper = @intCast(v[3].int256),
                .old_liquidity = @intCast(v[4].uint256),
                .new_liquidity = @intCast(v[5].uint256),
                .margin_delta = @intCast(v[6].int256),
                .funding = v[7].int256,
                .lp_fees = v[8].uint256,
            } };
        },
        .taker_opened => blk: {
            // margin, SwapResult (static, inline), lastCumlFundingX96.
            const v = try decode(allocator, log.data, &([_]AbiType{.uint128} ++ swap_result_types ++ [_]AbiType{.int256}));
            defer allocator.free(v);
            break :blk .{ .taker_opened = .{
                .pos_id = try topicU256(log, 1),
                .owner = try topicAddress(log, 2),
                .margin = @intCast(v[0].uint256),
                .sr = swapResultAt(v, 1),
                .last_cuml_funding_x96 = v[9].int256,
            } };
        },
        .taker_adjusted => .{ .taker_adjusted = try decodeTakerLifecycle(allocator, log) },
        .taker_closed => .{ .taker_closed = try decodeTakerLifecycle(allocator, log) },
        .taker_backstopped => blk: {
            // marginIn, posRecipient, funding, utilFees, delta, margin,
            // lastCumlFundingX96.
            const v = try decode(allocator, log.data, &.{
                .uint128, .address, .int256, .uint256, .int256, .uint128, .int256,
            });
            defer allocator.free(v);
            break :blk .{ .taker_backstopped = .{
                .pos_id = try topicU256(log, 1),
                .margin_in = @intCast(v[0].uint256),
                .pos_recipient = v[1].address,
                .funding = v[2].int256,
                .util_fees = v[3].uint256,
                .delta = v[4].int256,
                .margin = @intCast(v[5].uint256),
                .last_cuml_funding_x96 = v[6].int256,
            } };
        },
        .taker_liquidated => blk: {
            const v = try decode(allocator, log.data, &.{ .uint128, .uint256 });
            defer allocator.free(v);
            break :blk .{ .taker_liquidated = .{
                .pos_id = try topicU256(log, 1),
                .fee_recipient = try topicAddress(log, 2),
                .perp_amount = @intCast(v[0].uint256),
                .liq_fee = v[1].uint256,
            } };
        },
        // All three parameters are indexed; the log carries no data.
        .position_owner_updated => .{ .position_owner_updated = .{
            .pos_id = try topicU256(log, 1),
            .old_owner = try topicAddress(log, 2),
            .new_owner = try topicAddress(log, 3),
        } },
        .quote_folded => blk: {
            const v = try decode(allocator, log.data, &.{.int256});
            defer allocator.free(v);
            break :blk .{ .quote_folded = .{
                .pos_id = try topicU256(log, 1),
                .amount = v[0].int256,
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
        .physical_capacity_updated => blk: {
            const v = try decode(allocator, log.data, &.{ .uint256, .uint256 });
            defer allocator.free(v);
            break :blk .{ .physical_capacity_updated = .{
                .long_close_x64 = v[0].uint256,
                .short_close_x64 = v[1].uint256,
            } };
        },
        .rates_and_emas_refreshed => blk: {
            // Rates(5 fields, inline), index, PricePair(ammPrice, index).
            const v = try decode(allocator, log.data, &.{
                .int88, .uint64, .uint64, .uint40, .uint256, .uint128, .uint128, .uint128,
            });
            defer allocator.free(v);
            break :blk .{ .rates_and_emas_refreshed = .{
                .rates = .{
                    .funding_per_day = v[0].int256,
                    .long_util_fee_per_day = @intCast(v[1].uint256),
                    .short_util_fee_per_day = @intCast(v[2].uint256),
                    .last_touch = @intCast(v[3].uint256),
                    .last_mark = v[4].uint256,
                },
                .index = @intCast(v[5].uint256),
                .emas = .{
                    .amm_price = @intCast(v[6].uint256),
                    .index = @intCast(v[7].uint256),
                },
            } };
        },
        .bad_debt_accounted => blk: {
            const v = try decode(allocator, log.data, &.{ .uint256, .uint256, .uint256, .uint128 });
            defer allocator.free(v);
            break :blk .{ .bad_debt_accounted = .{
                .bad_debt = v[0].uint256,
                .insurance_consumed = v[1].uint256,
                .insurance_after = v[2].uint256,
                .bad_debt_after = @intCast(v[3].uint256),
            } };
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

/// Decode a batch of raw logs into their typed events, skipping any log whose
/// `topic0` is unrecognized. Caller owns the returned slice (the `DecodedEvent`s
/// hold no allocations); free with `allocator.free`. Shared by the pull-based
/// `pollEvents` and the real-time `PerpEventWatcher`.
pub fn decodeLogs(allocator: std.mem.Allocator, logs: []const Log) ![]DecodedEvent {
    var decoded: std.ArrayList(DecodedEvent) = .empty;
    defer decoded.deinit(allocator);
    for (logs) |log| {
        if (try decodeEvent(allocator, log)) |ev| try decoded.append(allocator, ev);
    }
    return decoded.toOwnedSlice(allocator);
}

/// Decode the shared layout of `MakerAdjusted` / `MakerClosed` /
/// `MakerConverted`: indexed `(posId, owner)`, then `(marginDelta,
/// liquidityDelta, funding, lpFees, delta, margin, liquidity,
/// lastCumlFundingX96, MakerFunding)` in the data.
fn decodeMakerLifecycle(allocator: std.mem.Allocator, log: Log) !events.MakerAdjustedEvent {
    const v = try decode(allocator, log.data, &.{
        .int128,  .int128,  .int256, .uint256, .int256,
        .uint128, .uint128, .int256, .int256,  .int256,
    });
    defer allocator.free(v);
    return .{
        .pos_id = try topicU256(log, 1),
        .owner = try topicAddress(log, 2),
        .margin_delta = @intCast(v[0].int256),
        .liquidity_delta = @intCast(v[1].int256),
        .funding = v[2].int256,
        .lp_fees = v[3].uint256,
        .delta = v[4].int256,
        .margin = @intCast(v[5].uint256),
        .liquidity = @intCast(v[6].uint256),
        .last_cuml_funding_x96 = v[7].int256,
        .last_cuml_funding = .{
            .below_x96 = v[8].int256,
            .within_inventory_x192 = v[9].int256,
        },
    };
}

/// Decode the shared layout of `TakerAdjusted` / `TakerClosed`: indexed
/// `(posId, owner)`, then `(marginDelta, SwapResult, funding, utilFees, delta,
/// margin, lastCumlFundingX96)` in the data.
fn decodeTakerLifecycle(allocator: std.mem.Allocator, log: Log) !events.TakerAdjustedEvent {
    const v = try decode(allocator, log.data, &([_]AbiType{.int128} ++ swap_result_types ++ [_]AbiType{
        .int256, .uint256, .int256, .uint128, .int256,
    }));
    defer allocator.free(v);
    return .{
        .pos_id = try topicU256(log, 1),
        .owner = try topicAddress(log, 2),
        .margin_delta = @intCast(v[0].int256),
        .sr = swapResultAt(v, 1),
        .funding = v[9].int256,
        .util_fees = v[10].uint256,
        .delta = v[11].int256,
        .margin = @intCast(v[12].uint256),
        .last_cuml_funding_x96 = v[13].int256,
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
