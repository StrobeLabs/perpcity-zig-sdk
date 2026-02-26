const std = @import("std");
const types = @import("../types.zig");
const anvil_mod = @import("anvil.zig");
const mock_deployer = @import("mock_deployer.zig");
const context_mod = @import("../context.zig");

const AnvilProcess = anvil_mod.AnvilProcess;
const DeployedContracts = mock_deployer.DeployedContracts;
const PerpCityContext = context_mod.PerpCityContext;

/// Full integration test setup: Anvil node + deployed mock contracts + SDK context.
pub const AnvilSetup = struct {
    anvil: AnvilProcess,
    contracts: DeployedContracts,
    context: PerpCityContext,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, io: std.Io) !AnvilSetup {
        var anvil_proc = try AnvilProcess.start(allocator, AnvilProcess.DEFAULT_PORT, io);
        errdefer anvil_proc.stop();

        const contracts = try mock_deployer.deployAll(allocator, anvil_proc.rpc_url, io);

        const ctx = try PerpCityContext.init(
            allocator,
            anvil_proc.rpc_url,
            mock_deployer.DEPLOYER_PRIVATE_KEY,
            .{
                .perp_manager = contracts.perp_manager,
                .usdc = contracts.usdc,
                .fees_module = contracts.fees,
                .margin_ratios_module = contracts.margin_ratios,
            },
            io,
        );

        return AnvilSetup{
            .anvil = anvil_proc,
            .contracts = contracts,
            .context = ctx,
            .allocator = allocator,
        };
    }

    pub fn initWithPort(allocator: std.mem.Allocator, port: u16, io: std.Io) !AnvilSetup {
        var anvil_proc = try AnvilProcess.start(allocator, port, io);
        errdefer anvil_proc.stop();

        const contracts = try mock_deployer.deployAll(allocator, anvil_proc.rpc_url, io);

        const ctx = try PerpCityContext.init(
            allocator,
            anvil_proc.rpc_url,
            mock_deployer.DEPLOYER_PRIVATE_KEY,
            .{
                .perp_manager = contracts.perp_manager,
                .usdc = contracts.usdc,
                .fees_module = contracts.fees,
                .margin_ratios_module = contracts.margin_ratios,
            },
            io,
        );

        return AnvilSetup{
            .anvil = anvil_proc,
            .contracts = contracts,
            .context = ctx,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AnvilSetup) void {
        self.context.deinit();
        self.anvil.stop();
        self.* = undefined;
    }

    pub fn rpcUrl(self: *const AnvilSetup) []const u8 {
        return self.anvil.rpc_url;
    }

    pub fn deployerAddress(self: *const AnvilSetup) types.Address {
        _ = self;
        return mock_deployer.DEPLOYER_ADDRESS;
    }

    pub fn deployerPrivateKey(self: *const AnvilSetup) [32]u8 {
        _ = self;
        return mock_deployer.DEPLOYER_PRIVATE_KEY;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AnvilSetup struct fields are accessible" {
    const T = AnvilSetup;
    try std.testing.expect(@sizeOf(T) > 0);
}

test "deployerAddress returns Anvil default account" {
    const expected = mock_deployer.DEPLOYER_ADDRESS;
    var dummy: AnvilSetup = undefined;
    const addr = dummy.deployerAddress();
    try std.testing.expectEqualSlices(u8, &expected, &addr);
}

test "deployerPrivateKey returns Anvil default key" {
    const expected = mock_deployer.DEPLOYER_PRIVATE_KEY;
    var dummy: AnvilSetup = undefined;
    const key = dummy.deployerPrivateKey();
    try std.testing.expectEqualSlices(u8, &expected, &key);
}
