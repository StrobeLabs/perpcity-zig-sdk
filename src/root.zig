/// Pure math and types (no external dependency).
pub const types = @import("types.zig");
pub const constants = @import("constants.zig");
pub const conversions = @import("conversions.zig");
pub const liquidity = @import("liquidity.zig");
pub const position = @import("position.zig");
pub const perp = @import("perp.zig");
pub const sizing = @import("sizing.zig");
pub const funding = @import("funding.zig");
pub const user = @import("user.zig");
pub const errors = @import("errors.zig");

/// Multi-layer state cache for HFT workloads.
pub const state_cache = @import("state_cache.zig");

/// Connection management and multi-RPC failover.
pub const multi_rpc = @import("multi_rpc.zig");
pub const connection = @import("connection.zig");

/// Contract interaction layer (requires eth.zig).
pub const chain_client = @import("chain_client.zig");
pub const context = @import("context.zig");
pub const approve = @import("approve.zig");
pub const nonce = @import("nonce.zig");
pub const open_position = @import("open_position.zig");
pub const perp_factory = @import("perp_factory.zig");
pub const perp_contract = @import("perp_contract.zig");
pub const latency = @import("latency.zig");
pub const gas = @import("gas.zig");
pub const tx_pipeline = @import("tx_pipeline.zig");

/// Event streaming types and subscription registry.
pub const events = @import("events.zig");

/// Higher-level position management with stop-loss/take-profit triggers.
pub const position_manager = @import("position_manager.zig");

/// ABI definitions (perpcity-contracts v0.1.0).
pub const abi = struct {
    pub const perp_factory_abi = @import("abi/perp_factory_abi.zig");
    pub const perp_abi = @import("abi/perp_abi.zig");
    pub const module_registry_abi = @import("abi/module_registry_abi.zig");
    pub const protocol_fee_manager_abi = @import("abi/protocol_fee_manager_abi.zig");
    pub const fees_abi = @import("abi/fees_abi.zig");
    pub const margin_ratios_abi = @import("abi/margin_ratios_abi.zig");
    pub const funding_abi = @import("abi/funding_abi.zig");
    pub const pricing_abi = @import("abi/pricing_abi.zig");
    pub const price_impact_abi = @import("abi/price_impact_abi.zig");
    pub const beacon_abi = @import("abi/beacon_abi.zig");
    pub const erc20_abi = @import("abi/erc20_abi.zig");
};

/// Testing infrastructure for integration tests.
pub const testing = struct {
    pub const anvil = @import("testing/anvil.zig");
    pub const mock_deployer = @import("testing/mock_deployer.zig");
    pub const mock_chain_client = @import("testing/mock_chain_client.zig");
    pub const setup = @import("testing/setup.zig");
};

test {
    @import("std").testing.refAllDecls(@This());
}
