//! Decoding of Solidity revert data returned by a reverting `eth_call` /
//! `eth_estimateGas`, plus a retry hint a bot can branch on.
//!
//! The perpcity contracts revert with 4-byte custom-error selectors (from
//! `libraries/Errors.sol` and the interface files); the two standard Solidity
//! shapes `Error(string)` and `Panic(uint256)` are also handled. Selectors are
//! computed at comptime from the error signatures, so the table cannot drift
//! from a hand-copied hex constant.
//!
//! The decoder is allocation-free: a decoded `Error(string)` reason is a slice
//! that borrows the input `data`, so keep `data` alive while the reason is used.

const std = @import("std");
const eth = @import("eth");
const keccak = eth.keccak;

/// A recognized on-chain error. Names mirror the Solidity error identifiers.
pub const ContractError = enum {
    // libraries/Errors.sol (Perp core)
    abdicated,
    zero_delta,
    min_amt_unmet,
    margin_too_low,
    no_system_funds,
    zero_liquidity,
    max_amt_exceeded,
    negative_equity,
    negative_margin,
    not_pool_manager,
    not_liquidatable,
    non_maker_position,
    non_taker_position,
    ticks_out_of_bounds,
    data_not_timelocked,
    health_not_improved,
    margin_ratio_too_low,
    data_already_pending,
    price_impact_too_high,
    timelock_not_expired,
    unauthorized_caller,
    position_does_not_exist,
    long_utilization_exceeded,
    short_utilization_exceeded,
    insufficient_liquidity_to_fill,
    // PerpFactory
    ema_window_too_low,
    starting_price_too_low,
    starting_price_too_high,
    // AccountingToken
    already_initialized,
    transfer_not_allowed,
    // PerpGuardHook / ProtocolFeeManager
    unauthorized_pool_action,
    protocol_fee_too_high,
    // Solady SafeTransferLib
    transfer_from_failed,
    transfer_failed,
    approve_failed,
    eth_transfer_failed,
};

/// A decoded revert payload.
pub const Revert = union(enum) {
    /// A recognized 4-byte custom-error selector.
    contract_error: ContractError,
    /// `Error(string)`: the ABI-decoded reason, borrowing the input `data`.
    reason: []const u8,
    /// `Panic(uint256)`: the panic code (e.g. `0x11` arithmetic overflow).
    panic: u256,
    /// A 4-byte selector that matched no known error.
    unknown_selector: [4]u8,
    /// No revert data (empty return) - a bare `revert()`, out-of-gas, or a
    /// non-revert failure. Indistinguishable at this layer.
    empty,
};

/// What a caller (e.g. a liquidation bot) should do about a decoded revert.
pub const RetryHint = enum {
    /// The target is gone or ineligible - drop this candidate, do not retry.
    /// (e.g. `NotLiquidatable`, `PositionDoesNotExist`, `NonTakerPosition`.)
    skip,
    /// The full size could not be filled - retry with a smaller amount.
    /// (`InsufficientLiquidityToFill`.)
    retry_smaller,
    /// Transient / price-moved / unknown - safe to retry as-is (bounded).
    retry,
    /// A definitive input or state error - retrying unchanged will fail again.
    fatal,
};

const error_string_selector: [4]u8 = keccak.selector("Error(string)");
const panic_selector: [4]u8 = keccak.selector("Panic(uint256)");

const Entry = struct { sel: [4]u8, err: ContractError };

/// Selector -> error table, computed at comptime from the signatures. All
/// perpcity custom errors are zero-argument, so the signature is `Name()`.
/// Hashing 35 selectors at comptime blows the default eval-branch budget, so
/// raise it for this one initializer.
const table = blk: {
    @setEvalBranchQuota(2_000_000);
    break :blk [_]Entry{
        .{ .sel = keccak.selector("Abdicated()"), .err = .abdicated },
        .{ .sel = keccak.selector("ZeroDelta()"), .err = .zero_delta },
        .{ .sel = keccak.selector("MinAmtUnmet()"), .err = .min_amt_unmet },
        .{ .sel = keccak.selector("MarginTooLow()"), .err = .margin_too_low },
        .{ .sel = keccak.selector("NoSystemFunds()"), .err = .no_system_funds },
        .{ .sel = keccak.selector("ZeroLiquidity()"), .err = .zero_liquidity },
        .{ .sel = keccak.selector("MaxAmtExceeded()"), .err = .max_amt_exceeded },
        .{ .sel = keccak.selector("NegativeEquity()"), .err = .negative_equity },
        .{ .sel = keccak.selector("NegativeMargin()"), .err = .negative_margin },
        .{ .sel = keccak.selector("NotPoolManager()"), .err = .not_pool_manager },
        .{ .sel = keccak.selector("NotLiquidatable()"), .err = .not_liquidatable },
        .{ .sel = keccak.selector("NonMakerPosition()"), .err = .non_maker_position },
        .{ .sel = keccak.selector("NonTakerPosition()"), .err = .non_taker_position },
        .{ .sel = keccak.selector("TicksOutOfBounds()"), .err = .ticks_out_of_bounds },
        .{ .sel = keccak.selector("DataNotTimelocked()"), .err = .data_not_timelocked },
        .{ .sel = keccak.selector("HealthNotImproved()"), .err = .health_not_improved },
        .{ .sel = keccak.selector("MarginRatioTooLow()"), .err = .margin_ratio_too_low },
        .{ .sel = keccak.selector("DataAlreadyPending()"), .err = .data_already_pending },
        .{ .sel = keccak.selector("PriceImpactTooHigh()"), .err = .price_impact_too_high },
        .{ .sel = keccak.selector("TimelockNotExpired()"), .err = .timelock_not_expired },
        .{ .sel = keccak.selector("UnauthorizedCaller()"), .err = .unauthorized_caller },
        .{ .sel = keccak.selector("PositionDoesNotExist()"), .err = .position_does_not_exist },
        .{ .sel = keccak.selector("LongUtilizationExceeded()"), .err = .long_utilization_exceeded },
        .{ .sel = keccak.selector("ShortUtilizationExceeded()"), .err = .short_utilization_exceeded },
        .{ .sel = keccak.selector("InsufficientLiquidityToFill()"), .err = .insufficient_liquidity_to_fill },
        .{ .sel = keccak.selector("EmaWindowTooLow()"), .err = .ema_window_too_low },
        .{ .sel = keccak.selector("StartingPriceTooLow()"), .err = .starting_price_too_low },
        .{ .sel = keccak.selector("StartingPriceTooHigh()"), .err = .starting_price_too_high },
        .{ .sel = keccak.selector("AlreadyInitialized()"), .err = .already_initialized },
        .{ .sel = keccak.selector("TransferNotAllowed()"), .err = .transfer_not_allowed },
        .{ .sel = keccak.selector("UnauthorizedPoolAction()"), .err = .unauthorized_pool_action },
        .{ .sel = keccak.selector("ProtocolFeeTooHigh()"), .err = .protocol_fee_too_high },
        .{ .sel = keccak.selector("TransferFromFailed()"), .err = .transfer_from_failed },
        .{ .sel = keccak.selector("TransferFailed()"), .err = .transfer_failed },
        .{ .sel = keccak.selector("ApproveFailed()"), .err = .approve_failed },
        .{ .sel = keccak.selector("ETHTransferFailed()"), .err = .eth_transfer_failed },
    };
};

/// Decode raw revert `data` (the bytes returned by a reverting call, including
/// the 4-byte selector) into a typed `Revert`. Never allocates; a `reason`
/// borrows `data`.
pub fn decode(data: []const u8) Revert {
    if (data.len < 4) return .empty;
    const sel: [4]u8 = data[0..4].*;

    if (std.mem.eql(u8, &sel, &error_string_selector)) {
        if (decodeErrorString(data)) |s| return .{ .reason = s };
        return .{ .unknown_selector = sel };
    }
    if (std.mem.eql(u8, &sel, &panic_selector)) {
        if (data.len >= 36) return .{ .panic = std.mem.readInt(u256, data[4..36], .big) };
        return .{ .unknown_selector = sel };
    }

    inline for (table) |e| {
        if (std.mem.eql(u8, &sel, &e.sel)) return .{ .contract_error = e.err };
    }
    return .{ .unknown_selector = sel };
}

/// Decode a JSON-RPC `error.data` hex string (the revert payload a node returns
/// under `error.data`, with or without a `0x` prefix) into `dest` and classify
/// it. The returned `Revert` borrows `dest`, so keep it alive. Propagates a hex
/// error if `hex` is malformed or `dest` is too small for the decoded bytes.
///
/// eth.zig's `Provider` currently drops `error.data` (it keeps only the JSON-RPC
/// code + message), so a caller that wants byte-level custom-error decoding must
/// read `error.data` off the raw transport response and pass it here.
pub fn fromHex(dest: []u8, hex: []const u8) !Revert {
    const h = if (hex.len >= 2 and hex[0] == '0' and (hex[1] == 'x' or hex[1] == 'X'))
        hex[2..]
    else
        hex;
    const bytes = try eth.hex.hexToBytes(dest, h);
    return decode(bytes);
}

/// ABI-decode an `Error(string)` payload: after the 4-byte selector, a 32-byte
/// offset (always 0x20), a 32-byte length, then the UTF-8 bytes. Returns null
/// on any malformed / out-of-bounds layout. The returned slice borrows `data`.
fn decodeErrorString(data: []const u8) ?[]const u8 {
    if (data.len < 68) return null; // 4 + 32 (offset) + 32 (length)
    const len_word = std.mem.readInt(u256, data[36..68], .big);
    if (len_word > data.len - 68) return null;
    const len: usize = @intCast(len_word);
    return data[68 .. 68 + len];
}

/// Map a decoded revert to a retry hint. The mapping is intentionally
/// conservative: anything not clearly skip/retry-smaller is `fatal` (a definite
/// input/state error) or `retry` (transient/price-moved/unknown).
pub fn retryHint(r: Revert) RetryHint {
    return switch (r) {
        .contract_error => |e| switch (e) {
            // The target position is gone or the wrong kind - stop pursuing it.
            .not_liquidatable,
            .position_does_not_exist,
            .non_maker_position,
            .non_taker_position,
            .abdicated,
            => .skip,
            // Could not fill the requested size - a smaller amount may succeed.
            .insufficient_liquidity_to_fill => .retry_smaller,
            // Price/impact moved between quote and execution - re-quote and retry.
            .price_impact_too_high,
            .max_amt_exceeded,
            .min_amt_unmet,
            .long_utilization_exceeded,
            .short_utilization_exceeded,
            => .retry,
            // Everything else is a definitive input/state/config failure.
            else => .fatal,
        },
        // A bare revert / OOG / unknown selector: retry once, bounded.
        .empty, .unknown_selector => .retry,
        // A string reason or panic is a definitive failure with no safe retry.
        .reason, .panic => .fatal,
    };
}

/// True when a decoded revert means a liquidation candidate should be dropped
/// (not retried) - a convenience over `retryHint(r) == .skip`.
pub fn isSkip(r: Revert) bool {
    return retryHint(r) == .skip;
}
