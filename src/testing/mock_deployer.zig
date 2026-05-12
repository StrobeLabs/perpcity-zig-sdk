const std = @import("std");
const eth = @import("eth");
const types = @import("../types.zig");
const perp_factory_abi = @import("../abi/perp_factory_abi.zig");
const module_registry_abi = @import("../abi/module_registry_abi.zig");

const Wallet = eth.wallet.Wallet;
const Provider = eth.provider.Provider;
const HttpTransport = eth.http_transport.HttpTransport;
const AbiValue = eth.abi_encode.AbiValue;

/// Concrete addresses produced by `deployAll`. Per-market `Perp` addresses are
/// created via `MockPerpFactory.createPerp(...)` and are not returned here --
/// integration tests call the SDK's `perp_factory.createPerp` to instantiate
/// markets against the deployed factory.
pub const DeployedContracts = struct {
    perp_factory: types.Address,
    module_registry: types.Address,
    protocol_fee_manager: types.Address,
    usdc: types.Address,
    fees: types.Address,
    margin_ratios: types.Address,
    funding: types.Address,
    pricing: types.Address,
    price_impact: types.Address,
    beacon: types.Address,
};

// ---------------------------------------------------------------------------
// Well-known Anvil accounts
// ---------------------------------------------------------------------------

pub const DEPLOYER_ADDRESS: types.Address = hexToAddress("f39Fd6e51aad88F6F4ce6aB8827279cffFb92266");
pub const DEPLOYER_PRIVATE_KEY: [32]u8 = hexToKey("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

// ---------------------------------------------------------------------------
// Constructor argument constants
// ---------------------------------------------------------------------------

pub const MOCK_FEES_ARGS = .{
    .creator_fee = @as(u24, 1000),
    .insurance_fee = @as(u24, 500),
    .lp_fee = @as(u24, 2000),
    .liq_fee = @as(u24, 5000),
    .util_fee_per_day = @as(u64, 10_000_000_000_000_000), // 0.01 scaled 1e18
};

pub const MOCK_MARGIN_RATIOS_ARGS = .{
    .init_maker = @as(u24, 1_000_000),
    .liq_maker = @as(u24, 900_000),
    .backstop_maker = @as(u24, 800_000),
    .init_taker = @as(u24, 100_000),
    .liq_taker = @as(u24, 50_000),
    .backstop_taker = @as(u24, 20_000),
};

/// 1 << 96, the on-chain "price = 1" beacon index.
pub const MOCK_BEACON_INITIAL_INDEX: u256 = 79_228_162_514_264_337_593_543_950_336;

pub const MINT_AMOUNT: u256 = 1_000_000 * 1_000_000;
pub const ARTIFACT_DIR: []const u8 = "tests/contracts/out";

// ---------------------------------------------------------------------------
// Bytecode loading
// ---------------------------------------------------------------------------

pub fn loadBytecode(allocator: std.mem.Allocator, artifact_path: []const u8) ![]const u8 {
    const file_contents = std.fs.cwd().readFileAlloc(allocator, artifact_path, 10 * 1024 * 1024) catch {
        return error.ArtifactNotFound;
    };
    defer allocator.free(file_contents);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, file_contents, .{}) catch {
        return error.InvalidArtifactJson;
    };
    defer parsed.deinit();

    const root = parsed.value;
    const bytecode_obj = root.object.get("bytecode") orelse return error.MissingBytecodeField;
    const object_val = bytecode_obj.object.get("object") orelse return error.MissingBytecodeField;

    const hex_str = switch (object_val) {
        .string => |s| s,
        else => return error.MissingBytecodeField,
    };

    const hex_data = if (hex_str.len >= 2 and hex_str[0] == '0' and hex_str[1] == 'x')
        hex_str[2..]
    else
        hex_str;

    if (hex_data.len % 2 != 0) return error.InvalidBytecodeHex;
    const byte_len = hex_data.len / 2;
    const bytecode = try allocator.alloc(u8, byte_len);
    errdefer allocator.free(bytecode);

    for (0..byte_len) |i| {
        bytecode[i] = std.fmt.parseUnsigned(u8, hex_data[i * 2 ..][0..2], 16) catch {
            return error.InvalidBytecodeHex;
        };
    }

    return bytecode;
}

// ---------------------------------------------------------------------------
// Deployment orchestration (v0.1.0 layout)
// ---------------------------------------------------------------------------

pub fn deployAll(allocator: std.mem.Allocator, rpc_url: []const u8) !DeployedContracts {
    var transport = HttpTransport.init(allocator, rpc_url);
    defer transport.deinit();

    var provider = Provider.init(allocator, &transport);
    var wallet = Wallet.init(allocator, DEPLOYER_PRIVATE_KEY, &provider);

    const usdc = try deployArtifact(allocator, &wallet, "MockUSDC", &.{});
    const fees = try deployArtifact(allocator, &wallet, "MockFees", &.{
        .{ .uint256 = MOCK_FEES_ARGS.creator_fee },
        .{ .uint256 = MOCK_FEES_ARGS.insurance_fee },
        .{ .uint256 = MOCK_FEES_ARGS.lp_fee },
        .{ .uint256 = MOCK_FEES_ARGS.liq_fee },
        .{ .uint256 = MOCK_FEES_ARGS.util_fee_per_day },
    });
    const margin_ratios = try deployArtifact(allocator, &wallet, "MockMarginRatios", &.{
        .{ .uint256 = MOCK_MARGIN_RATIOS_ARGS.init_maker },
        .{ .uint256 = MOCK_MARGIN_RATIOS_ARGS.liq_maker },
        .{ .uint256 = MOCK_MARGIN_RATIOS_ARGS.backstop_maker },
        .{ .uint256 = MOCK_MARGIN_RATIOS_ARGS.init_taker },
        .{ .uint256 = MOCK_MARGIN_RATIOS_ARGS.liq_taker },
        .{ .uint256 = MOCK_MARGIN_RATIOS_ARGS.backstop_taker },
    });
    const funding = try deployArtifact(allocator, &wallet, "MockFunding", &.{
        .{ .int256 = 0 },
    });
    const pricing = try deployArtifact(allocator, &wallet, "MockPricing", &.{});
    const price_impact = try deployArtifact(allocator, &wallet, "MockPriceImpact", &.{});
    const beacon = try deployArtifact(allocator, &wallet, "MockBeacon", &.{
        .{ .uint256 = MOCK_BEACON_INITIAL_INDEX },
    });
    const module_registry = try deployArtifact(allocator, &wallet, "MockModuleRegistry", &.{});
    const protocol_fee_manager = try deployArtifact(allocator, &wallet, "MockProtocolFeeManager", &.{
        .{ .uint256 = 0 },
    });
    const perp_factory = try deployArtifact(allocator, &wallet, "MockPerpFactory", &.{});

    return DeployedContracts{
        .perp_factory = perp_factory,
        .module_registry = module_registry,
        .protocol_fee_manager = protocol_fee_manager,
        .usdc = usdc,
        .fees = fees,
        .margin_ratios = margin_ratios,
        .funding = funding,
        .pricing = pricing,
        .price_impact = price_impact,
        .beacon = beacon,
    };
}

fn deployArtifact(
    allocator: std.mem.Allocator,
    wallet: *Wallet,
    contract_name: []const u8,
    constructor_args: []const AbiValue,
) !types.Address {
    const path = try artifactPath(allocator, contract_name);
    defer allocator.free(path);

    const bytecode = try loadBytecode(allocator, path);
    defer allocator.free(bytecode);

    if (constructor_args.len == 0) {
        return deployRawBytes(wallet, bytecode);
    }

    const encoded_args = try eth.abi_encode.encodeValues(allocator, constructor_args);
    defer allocator.free(encoded_args);

    const init_code = try allocator.alloc(u8, bytecode.len + encoded_args.len);
    defer allocator.free(init_code);
    @memcpy(init_code[0..bytecode.len], bytecode);
    @memcpy(init_code[bytecode.len..], encoded_args);

    return deployRawBytes(wallet, init_code);
}

fn deployRawBytes(wallet: *Wallet, init_code: []const u8) !types.Address {
    // Set a generous fixed gas limit so we don't call eth_estimateGas, which
    // anvil rejects for contract creation with a zero `to` placeholder.
    const tx_hash = try wallet.sendTransaction(.{
        .to = null,
        .data = init_code,
        .gas_limit = 8_000_000,
    });

    const receipt = (try wallet.waitForReceipt(tx_hash, 10)) orelse
        return error.DeploymentFailed;

    return receipt.contract_address orelse return error.DeploymentFailed;
}

pub fn artifactPath(allocator: std.mem.Allocator, contract_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/{s}.sol/{s}.json",
        .{ ARTIFACT_DIR, contract_name, contract_name },
    );
}

/// Helper: register all module mocks with the deployed `MockModuleRegistry`.
/// Use this in integration tests that need the registry populated before
/// creating perps via the factory.
pub fn registerModules(
    allocator: std.mem.Allocator,
    rpc_url: []const u8,
    contracts: DeployedContracts,
) !void {
    var transport = HttpTransport.init(allocator, rpc_url);
    defer transport.deinit();

    var provider = Provider.init(allocator, &transport);
    var wallet = Wallet.init(allocator, DEPLOYER_PRIVATE_KEY, &provider);

    const entries = [_]struct { kind: module_registry_abi.Module, addr: types.Address }{
        .{ .kind = .fees, .addr = contracts.fees },
        .{ .kind = .margin_ratios, .addr = contracts.margin_ratios },
        .{ .kind = .funding, .addr = contracts.funding },
        .{ .kind = .pricing, .addr = contracts.pricing },
        .{ .kind = .price_impact, .addr = contracts.price_impact },
    };

    for (entries) |entry| {
        const calldata = try eth.abi_encode.encodeFunctionCall(
            allocator,
            module_registry_abi.register_module_selector,
            &.{
                .{ .uint256 = @as(u256, @intFromEnum(entry.kind)) },
                .{ .address = entry.addr },
            },
        );
        defer allocator.free(calldata);
        const tx_hash = try wallet.sendTransaction(.{
            .to = contracts.module_registry,
            .data = calldata,
            .gas_limit = 200_000,
        });
        _ = (try wallet.waitForReceipt(tx_hash, 10)) orelse return error.RegisterModuleFailed;
    }
}

pub fn deploymentsFrom(contracts: DeployedContracts) types.PerpCityDeployments {
    return .{
        .perp_factory = contracts.perp_factory,
        .module_registry = contracts.module_registry,
        .protocol_fee_manager = contracts.protocol_fee_manager,
        .usdc = contracts.usdc,
        .fees_module = contracts.fees,
        .margin_ratios_module = contracts.margin_ratios,
        .funding_module = contracts.funding,
        .pricing_module = contracts.pricing,
        .price_impact_module = contracts.price_impact,
    };
}

// ---------------------------------------------------------------------------
// Hex helpers
// ---------------------------------------------------------------------------

fn hexToAddress(comptime hex: *const [40]u8) [20]u8 {
    var out: [20]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, hex) catch unreachable;
    return out;
}

fn hexToKey(comptime hex: *const [64]u8) [32]u8 {
    var out: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&out, hex) catch unreachable;
    return out;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "DEPLOYER_ADDRESS matches Anvil default account" {
    const expected = [_]u8{
        0xf3, 0x9F, 0xd6, 0xe5, 0x1a, 0xad, 0x88, 0xF6, 0xF4, 0xce,
        0x6a, 0xB8, 0x82, 0x72, 0x79, 0xcf, 0xfF, 0xb9, 0x22, 0x66,
    };
    try std.testing.expectEqualSlices(u8, &expected, &DEPLOYER_ADDRESS);
}

test "MOCK_FEES_ARGS has expected values" {
    try std.testing.expectEqual(@as(u24, 1000), MOCK_FEES_ARGS.creator_fee);
    try std.testing.expectEqual(@as(u24, 500), MOCK_FEES_ARGS.insurance_fee);
    try std.testing.expectEqual(@as(u24, 2000), MOCK_FEES_ARGS.lp_fee);
    try std.testing.expectEqual(@as(u24, 5000), MOCK_FEES_ARGS.liq_fee);
}

test "MOCK_MARGIN_RATIOS_ARGS has expected values" {
    try std.testing.expectEqual(@as(u24, 1_000_000), MOCK_MARGIN_RATIOS_ARGS.init_maker);
    try std.testing.expectEqual(@as(u24, 100_000), MOCK_MARGIN_RATIOS_ARGS.init_taker);
    try std.testing.expectEqual(@as(u24, 50_000), MOCK_MARGIN_RATIOS_ARGS.liq_taker);
}

test "MINT_AMOUNT equals 1M USDC in 6-decimal units" {
    try std.testing.expectEqual(@as(u256, 1_000_000_000_000), MINT_AMOUNT);
}

test "artifactPath builds correct path" {
    const path = try artifactPath(std.testing.allocator, "MockFees");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("tests/contracts/out/MockFees.sol/MockFees.json", path);
}

test "deploymentsFrom maps fields correctly" {
    const a1: types.Address = [_]u8{1} ** 20;
    const a2: types.Address = [_]u8{2} ** 20;
    const a3: types.Address = [_]u8{3} ** 20;
    const a4: types.Address = [_]u8{4} ** 20;

    const dc: DeployedContracts = .{
        .perp_factory = a1,
        .module_registry = a2,
        .protocol_fee_manager = a3,
        .usdc = a4,
        .fees = a1,
        .margin_ratios = a2,
        .funding = a3,
        .pricing = a4,
        .price_impact = a1,
        .beacon = a2,
    };
    const d = deploymentsFrom(dc);
    try std.testing.expectEqualSlices(u8, &a1, &d.perp_factory);
    try std.testing.expectEqualSlices(u8, &a4, &d.usdc);
    try std.testing.expect(d.fees_module != null);
}
