pub const ErrorCategory = enum {
    user_error,
    state_error,
    system_error,
    config_error,
};

pub const ErrorSource = enum {
    perp_manager,
    pool_manager,
    unknown,
};

pub const SdkError = error{
    // Contract errors
    InvalidBeaconAddress,
    InvalidMargin,
    InvalidLevX96,
    PriceImpactTooHigh,
    SwapReverted,
    ZeroSizePosition,
    MakerPositionLocked,
    PositionDoesNotExist,
    PerpNotFound,

    // Validation
    PriceMustBePositive,
    PriceTooLarge,
    AmountTooLarge,
    ValueTooLarge,
    MarginRatioMustBePositive,
    MarginMustBePositive,
    LeverageMustBePositive,
    InvalidTickRange,
    InvalidPriceRange,

    // RPC
    RpcError,
    TransactionReverted,
    TransactionRejected,
    InsufficientFunds,

    // Module
    ModuleAddressRequired,

    // Generic
    Unexpected,
};

pub const ErrorDebugInfo = struct {
    category: ErrorCategory,
    source: ErrorSource,
    can_retry: bool,
};

pub fn getErrorDebugInfo(err: SdkError) ?ErrorDebugInfo {
    return switch (err) {
        error.InvalidMargin,
        error.InvalidLevX96,
        error.MarginMustBePositive,
        error.LeverageMustBePositive,
        => .{
            .category = .user_error,
            .source = .perp_manager,
            .can_retry = false,
        },
        error.PriceImpactTooHigh,
        error.SwapReverted,
        => .{
            .category = .state_error,
            .source = .pool_manager,
            .can_retry = true,
        },
        error.RpcError,
        error.TransactionReverted,
        => .{
            .category = .system_error,
            .source = .unknown,
            .can_retry = true,
        },
        error.PerpNotFound,
        error.ModuleAddressRequired,
        => .{
            .category = .config_error,
            .source = .perp_manager,
            .can_retry = false,
        },
        else => null,
    };
}

test "getErrorDebugInfo returns correct category for user errors" {
    const std = @import("std");
    const info = getErrorDebugInfo(error.InvalidMargin);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(ErrorCategory.user_error, info.?.category);
    try std.testing.expectEqual(false, info.?.can_retry);
}

test "getErrorDebugInfo returns correct category for state errors" {
    const std = @import("std");
    const info = getErrorDebugInfo(error.PriceImpactTooHigh);
    try std.testing.expect(info != null);
    try std.testing.expectEqual(ErrorCategory.state_error, info.?.category);
    try std.testing.expectEqual(true, info.?.can_retry);
}

test "getErrorDebugInfo returns null for unclassified errors" {
    const std = @import("std");
    const info = getErrorDebugInfo(error.Unexpected);
    try std.testing.expectEqual(@as(?ErrorDebugInfo, null), info);
}
