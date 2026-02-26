const std = @import("std");
const sdk = @import("perpcity_sdk");
const errors = sdk.errors;

// =============================================================================
// getErrorDebugInfo - user_error category
// =============================================================================

test "getErrorDebugInfo - InvalidMargin is a user_error" {
    const info = errors.getErrorDebugInfo(error.InvalidMargin);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.user_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.perp_manager, info.?.source);
    try std.testing.expectEqual(false, info.?.can_retry);
}

test "getErrorDebugInfo - InvalidLevX96 is a user_error" {
    const info = errors.getErrorDebugInfo(error.InvalidLevX96);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.user_error, info.?.category);
    try std.testing.expectEqual(false, info.?.can_retry);
}

test "getErrorDebugInfo - MarginMustBePositive is a user_error" {
    const info = errors.getErrorDebugInfo(error.MarginMustBePositive);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.user_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.perp_manager, info.?.source);
    try std.testing.expectEqual(false, info.?.can_retry);
}

test "getErrorDebugInfo - LeverageMustBePositive is a user_error" {
    const info = errors.getErrorDebugInfo(error.LeverageMustBePositive);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.user_error, info.?.category);
    try std.testing.expectEqual(false, info.?.can_retry);
}

// =============================================================================
// getErrorDebugInfo - state_error category
// =============================================================================

test "getErrorDebugInfo - PriceImpactTooHigh is a state_error" {
    const info = errors.getErrorDebugInfo(error.PriceImpactTooHigh);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.state_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.pool_manager, info.?.source);
    try std.testing.expectEqual(true, info.?.can_retry);
}

test "getErrorDebugInfo - SwapReverted is a state_error" {
    const info = errors.getErrorDebugInfo(error.SwapReverted);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.state_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.pool_manager, info.?.source);
    try std.testing.expectEqual(true, info.?.can_retry);
}

// =============================================================================
// getErrorDebugInfo - system_error category
// =============================================================================

test "getErrorDebugInfo - RpcError is a system_error" {
    const info = errors.getErrorDebugInfo(error.RpcError);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.system_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.unknown, info.?.source);
    try std.testing.expectEqual(true, info.?.can_retry);
}

test "getErrorDebugInfo - TransactionReverted is a system_error" {
    const info = errors.getErrorDebugInfo(error.TransactionReverted);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.system_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.unknown, info.?.source);
    try std.testing.expectEqual(true, info.?.can_retry);
}

// =============================================================================
// getErrorDebugInfo - config_error category
// =============================================================================

test "getErrorDebugInfo - PerpNotFound is a config_error" {
    const info = errors.getErrorDebugInfo(error.PerpNotFound);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.config_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.perp_manager, info.?.source);
    try std.testing.expectEqual(false, info.?.can_retry);
}

test "getErrorDebugInfo - ModuleAddressRequired is a config_error" {
    const info = errors.getErrorDebugInfo(error.ModuleAddressRequired);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(errors.ErrorCategory.config_error, info.?.category);
    try std.testing.expectEqual(errors.ErrorSource.perp_manager, info.?.source);
    try std.testing.expectEqual(false, info.?.can_retry);
}

// =============================================================================
// getErrorDebugInfo - unclassified errors return null
// =============================================================================

test "getErrorDebugInfo - Unexpected returns null" {
    const info = errors.getErrorDebugInfo(error.Unexpected);
    try std.testing.expectEqual(@as(?errors.ErrorDebugInfo, null), info);
}

test "getErrorDebugInfo - PriceMustBePositive returns null" {
    const info = errors.getErrorDebugInfo(error.PriceMustBePositive);
    try std.testing.expectEqual(@as(?errors.ErrorDebugInfo, null), info);
}

test "getErrorDebugInfo - InvalidTickRange returns null" {
    const info = errors.getErrorDebugInfo(error.InvalidTickRange);
    try std.testing.expectEqual(@as(?errors.ErrorDebugInfo, null), info);
}

test "getErrorDebugInfo - InsufficientFunds returns null" {
    const info = errors.getErrorDebugInfo(error.InsufficientFunds);
    try std.testing.expectEqual(@as(?errors.ErrorDebugInfo, null), info);
}

test "getErrorDebugInfo - TransactionRejected returns null" {
    const info = errors.getErrorDebugInfo(error.TransactionRejected);
    try std.testing.expectEqual(@as(?errors.ErrorDebugInfo, null), info);
}

test "getErrorDebugInfo - ZeroSizePosition returns null" {
    const info = errors.getErrorDebugInfo(error.ZeroSizePosition);
    try std.testing.expectEqual(@as(?errors.ErrorDebugInfo, null), info);
}

// =============================================================================
// Behavior verification: can_retry semantics
// =============================================================================

test "user_errors are never retryable" {
    const user_errors = [_]errors.SdkError{
        error.InvalidMargin,
        error.InvalidLevX96,
        error.MarginMustBePositive,
        error.LeverageMustBePositive,
    };
    for (user_errors) |err| {
        const info = errors.getErrorDebugInfo(err);
        if (info) |i| {
            try std.testing.expectEqual(false, i.can_retry);
        }
    }
}

test "state_errors are retryable" {
    const state_errors = [_]errors.SdkError{
        error.PriceImpactTooHigh,
        error.SwapReverted,
    };
    for (state_errors) |err| {
        const info = errors.getErrorDebugInfo(err);
        if (info) |i| {
            try std.testing.expectEqual(true, i.can_retry);
        }
    }
}

test "system_errors are retryable" {
    const system_errors = [_]errors.SdkError{
        error.RpcError,
        error.TransactionReverted,
    };
    for (system_errors) |err| {
        const info = errors.getErrorDebugInfo(err);
        if (info) |i| {
            try std.testing.expectEqual(true, i.can_retry);
        }
    }
}

test "config_errors are not retryable" {
    const config_errors = [_]errors.SdkError{
        error.PerpNotFound,
        error.ModuleAddressRequired,
    };
    for (config_errors) |err| {
        const info = errors.getErrorDebugInfo(err);
        if (info) |i| {
            try std.testing.expectEqual(false, i.can_retry);
        }
    }
}

// =============================================================================
// ErrorCategory and ErrorSource enum coverage
// =============================================================================

test "ErrorCategory enum has expected variants" {
    // Just ensure all variants are accessible
    const cats = [_]errors.ErrorCategory{
        .user_error,
        .state_error,
        .system_error,
        .config_error,
    };
    try std.testing.expectEqual(@as(usize, 4), cats.len);
}

test "ErrorSource enum has expected variants" {
    const sources = [_]errors.ErrorSource{
        .perp_manager,
        .pool_manager,
        .unknown,
    };
    try std.testing.expectEqual(@as(usize, 3), sources.len);
}
