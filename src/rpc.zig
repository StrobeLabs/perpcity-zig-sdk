const std = @import("std");

/// Get the RPC URL from the PERPCITY_RPC_URL environment variable.
/// Returns error if not set.
pub fn getRpcUrl() ![]const u8 {
    return std.posix.getenv("PERPCITY_RPC_URL") orelse return error.RpcUrlNotSet;
}
