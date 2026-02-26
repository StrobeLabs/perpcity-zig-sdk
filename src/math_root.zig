/// Pure math and types module -- no external dependency.
/// Used by unit tests that only need conversion, liquidity, and position math.
pub const types = @import("types.zig");
pub const constants = @import("constants.zig");
pub const conversions = @import("conversions.zig");
pub const liquidity = @import("liquidity.zig");
pub const position = @import("position.zig");
pub const perp = @import("perp.zig");
pub const user = @import("user.zig");
pub const errors = @import("errors.zig");

/// Multi-layer state cache for HFT workloads.
pub const state_cache = @import("state_cache.zig");

/// Connection management and multi-RPC failover.
pub const multi_rpc = @import("multi_rpc.zig");
pub const connection = @import("connection.zig");

/// Latency tracking for HFT observability.
pub const latency = @import("latency.zig");

/// Gas optimization for HFT (pre-computed limits and fee caching).
pub const gas = @import("gas.zig");

/// Local nonce management for HFT (lock-free nonce acquisition).
pub const nonce = @import("nonce.zig");

/// Transaction pipeline combining nonce manager and gas cache.
pub const tx_pipeline = @import("tx_pipeline.zig");

/// Event streaming types and subscription registry.
pub const events = @import("events.zig");

/// Higher-level position management with stop-loss/take-profit triggers.
pub const position_manager = @import("position_manager.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
