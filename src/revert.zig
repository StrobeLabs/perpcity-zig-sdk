//! Decoding of Solidity revert data returned by a reverting `eth_call` /
//! `eth_estimateGas`, plus a retry hint a bot can branch on.
//!
//! The perpcity contracts (v1.0.0) revert with 4-byte custom-error selectors
//! (from `libraries/Errors.sol` and the interface files); the two standard Solidity
//! shapes `Error(string)` and `Panic(uint256)` are also handled. Selectors are
//! computed at comptime from the error signatures, so the table cannot drift
//! from a hand-copied hex constant.
//!
//! The decoder is allocation-free: a decoded `Error(string)` reason is a slice
//! that borrows the input `data`, so keep `data` alive while the reason is used.

const std = @import("std");
const eth = @import("eth");
const keccak = eth.keccak;

/// A recognized on-chain error. Names mirror the Solidity error identifiers
/// of perpcity-contracts v1.0.0.
pub const ContractError = enum {
    // libraries/Errors.sol (Perp)
    abdicated,
    aggregate_swap_fees_too_high,
    beacon_index_unreadable,
    deadline_expired,
    donations_restricted,
    ema_window_too_low,
    health_not_improved,
    identical_ticks,
    insufficient_liquidity_to_fill,
    invalid_callback_action,
    long_close_capacity_exceeded,
    margin_ratio_too_low,
    margin_too_high,
    margin_too_low,
    max_amt_exceeded,
    max_total_fee_exceeded,
    min_amt_unmet,
    negative_equity,
    negative_margin,
    non_maker_position,
    non_taker_position,
    no_surplus,
    no_system_funds,
    not_liquidatable,
    not_pool_manager,
    position_does_not_exist,
    price_impact_too_high,
    price_outside_range,
    reduce_only_violated,
    short_close_capacity_exceeded,
    stale_beacon_index,
    ticks_out_of_bounds,
    unauthorized_caller,
    zero_address,
    zero_amount,
    zero_capacity,
    zero_delta,
    zero_liquidity,
    // libraries/Errors.sol (WithdrawalController)
    already_initialized,
    amount_not_decreased,
    claim_is_paused,
    claim_not_paused,
    claim_not_pending,
    claim_not_ready,
    not_governor,
    not_guardian,
    not_perp,
    releases_are_paused,
    tvl_cap_exceeded,
    window_not_increased,
    zero_window,
    // IPerpFactory
    invalid_perp_implementation,
    not_a_contract,
    not_protocol_owner,
    // IPerpGuardHook / IProtocolFeeManager
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
/// Hashing 60 selectors at comptime blows the default eval-branch budget, so
/// raise it for this one initializer.
const table = blk: {
    @setEvalBranchQuota(4_000_000);
    break :blk [_]Entry{
        .{ .sel = keccak.selector("Abdicated()"), .err = .abdicated },
        .{ .sel = keccak.selector("AggregateSwapFeesTooHigh()"), .err = .aggregate_swap_fees_too_high },
        .{ .sel = keccak.selector("BeaconIndexUnreadable()"), .err = .beacon_index_unreadable },
        .{ .sel = keccak.selector("DeadlineExpired()"), .err = .deadline_expired },
        .{ .sel = keccak.selector("DonationsRestricted()"), .err = .donations_restricted },
        .{ .sel = keccak.selector("EmaWindowTooLow()"), .err = .ema_window_too_low },
        .{ .sel = keccak.selector("HealthNotImproved()"), .err = .health_not_improved },
        .{ .sel = keccak.selector("IdenticalTicks()"), .err = .identical_ticks },
        .{ .sel = keccak.selector("InsufficientLiquidityToFill()"), .err = .insufficient_liquidity_to_fill },
        .{ .sel = keccak.selector("InvalidCallbackAction()"), .err = .invalid_callback_action },
        .{ .sel = keccak.selector("LongCloseCapacityExceeded()"), .err = .long_close_capacity_exceeded },
        .{ .sel = keccak.selector("MarginRatioTooLow()"), .err = .margin_ratio_too_low },
        .{ .sel = keccak.selector("MarginTooHigh()"), .err = .margin_too_high },
        .{ .sel = keccak.selector("MarginTooLow()"), .err = .margin_too_low },
        .{ .sel = keccak.selector("MaxAmtExceeded()"), .err = .max_amt_exceeded },
        .{ .sel = keccak.selector("MaxTotalFeeExceeded()"), .err = .max_total_fee_exceeded },
        .{ .sel = keccak.selector("MinAmtUnmet()"), .err = .min_amt_unmet },
        .{ .sel = keccak.selector("NegativeEquity()"), .err = .negative_equity },
        .{ .sel = keccak.selector("NegativeMargin()"), .err = .negative_margin },
        .{ .sel = keccak.selector("NonMakerPosition()"), .err = .non_maker_position },
        .{ .sel = keccak.selector("NonTakerPosition()"), .err = .non_taker_position },
        .{ .sel = keccak.selector("NoSurplus()"), .err = .no_surplus },
        .{ .sel = keccak.selector("NoSystemFunds()"), .err = .no_system_funds },
        .{ .sel = keccak.selector("NotLiquidatable()"), .err = .not_liquidatable },
        .{ .sel = keccak.selector("NotPoolManager()"), .err = .not_pool_manager },
        .{ .sel = keccak.selector("PositionDoesNotExist()"), .err = .position_does_not_exist },
        .{ .sel = keccak.selector("PriceImpactTooHigh()"), .err = .price_impact_too_high },
        .{ .sel = keccak.selector("PriceOutsideRange()"), .err = .price_outside_range },
        .{ .sel = keccak.selector("ReduceOnlyViolated()"), .err = .reduce_only_violated },
        .{ .sel = keccak.selector("ShortCloseCapacityExceeded()"), .err = .short_close_capacity_exceeded },
        .{ .sel = keccak.selector("StaleBeaconIndex()"), .err = .stale_beacon_index },
        .{ .sel = keccak.selector("TicksOutOfBounds()"), .err = .ticks_out_of_bounds },
        .{ .sel = keccak.selector("UnauthorizedCaller()"), .err = .unauthorized_caller },
        .{ .sel = keccak.selector("ZeroAddress()"), .err = .zero_address },
        .{ .sel = keccak.selector("ZeroAmount()"), .err = .zero_amount },
        .{ .sel = keccak.selector("ZeroCapacity()"), .err = .zero_capacity },
        .{ .sel = keccak.selector("ZeroDelta()"), .err = .zero_delta },
        .{ .sel = keccak.selector("ZeroLiquidity()"), .err = .zero_liquidity },
        .{ .sel = keccak.selector("AlreadyInitialized()"), .err = .already_initialized },
        .{ .sel = keccak.selector("AmountNotDecreased()"), .err = .amount_not_decreased },
        .{ .sel = keccak.selector("ClaimIsPaused()"), .err = .claim_is_paused },
        .{ .sel = keccak.selector("ClaimNotPaused()"), .err = .claim_not_paused },
        .{ .sel = keccak.selector("ClaimNotPending()"), .err = .claim_not_pending },
        .{ .sel = keccak.selector("ClaimNotReady()"), .err = .claim_not_ready },
        .{ .sel = keccak.selector("NotGovernor()"), .err = .not_governor },
        .{ .sel = keccak.selector("NotGuardian()"), .err = .not_guardian },
        .{ .sel = keccak.selector("NotPerp()"), .err = .not_perp },
        .{ .sel = keccak.selector("ReleasesArePaused()"), .err = .releases_are_paused },
        .{ .sel = keccak.selector("TvlCapExceeded()"), .err = .tvl_cap_exceeded },
        .{ .sel = keccak.selector("WindowNotIncreased()"), .err = .window_not_increased },
        .{ .sel = keccak.selector("ZeroWindow()"), .err = .zero_window },
        .{ .sel = keccak.selector("InvalidPerpImplementation()"), .err = .invalid_perp_implementation },
        .{ .sel = keccak.selector("NotAContract()"), .err = .not_a_contract },
        .{ .sel = keccak.selector("NotProtocolOwner()"), .err = .not_protocol_owner },
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
    // The canonical encoding puts the string data at offset 0x20; reject any
    // non-canonical offset rather than reading a length from the wrong word.
    if (std.mem.readInt(u256, data[4..36], .big) != 32) return null;
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
            // Could not fill or back the requested size - a smaller amount may
            // succeed. (A partial liquidation that does not improve health
            // reverts `HealthNotImproved`, which stays `fatal`: the fix there
            // is a different size, not necessarily a smaller one.)
            .insufficient_liquidity_to_fill,
            .long_close_capacity_exceeded,
            .short_close_capacity_exceeded,
            => .retry_smaller,
            // Price, fees, or the oracle moved between quote and execution -
            // re-quote and retry. A stale or unreadable beacon clears once the
            // updater lands its next observation.
            .price_impact_too_high,
            .max_amt_exceeded,
            .min_amt_unmet,
            .max_total_fee_exceeded,
            .stale_beacon_index,
            .beacon_index_unreadable,
            // A claim inside its challenge window becomes releasable later.
            .claim_not_ready,
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
