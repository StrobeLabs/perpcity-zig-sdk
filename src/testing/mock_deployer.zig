const std = @import("std");
const eth = @import("eth");
const types = @import("../types.zig");

const Wallet = eth.wallet.Wallet;
const Provider = eth.provider.Provider;
const HttpTransport = eth.http_transport.HttpTransport;

pub const DeployedContracts = struct {
    perp_manager: types.Address,
    usdc: types.Address,
    fees: types.Address,
    margin_ratios: types.Address,
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
    .liquidation_fee = @as(u24, 5000),
};

pub const MOCK_MARGIN_RATIOS_ARGS = .{
    .min_taker = @as(u24, 100000),
    .max_taker = @as(u24, 500000),
    .liq_taker = @as(u24, 50000),
    .min_maker = @as(u24, 100000),
    .max_maker = @as(u24, 500000),
    .liq_maker = @as(u24, 50000),
};

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
// Deployment orchestration
// ---------------------------------------------------------------------------

pub fn deployAll(allocator: std.mem.Allocator, rpc_url: []const u8) !DeployedContracts {
    var transport = HttpTransport.init(allocator, rpc_url);
    defer transport.deinit();

    var provider = Provider.init(allocator, &transport);
    var wallet = Wallet.init(allocator, DEPLOYER_PRIVATE_KEY, &provider);

    // Deploy MockFees
    const fees_bytecode = try loadBytecode(allocator, "tests/contracts/out/MockFees.sol/MockFees.json");
    defer allocator.free(fees_bytecode);
    const fees_addr = try deployContract(&wallet, fees_bytecode);

    // Deploy MockMarginRatios
    const margin_bytecode = try loadBytecode(allocator, "tests/contracts/out/MockMarginRatios.sol/MockMarginRatios.json");
    defer allocator.free(margin_bytecode);
    const margin_addr = try deployContract(&wallet, margin_bytecode);

    // Deploy MockUSDC
    const usdc_bytecode = try loadBytecode(allocator, "tests/contracts/out/MockUSDC.sol/MockUSDC.json");
    defer allocator.free(usdc_bytecode);
    const usdc_addr = try deployContract(&wallet, usdc_bytecode);

    // Deploy MockPerpManager
    const pm_bytecode = try loadBytecode(allocator, "tests/contracts/out/MockPerpManager.sol/MockPerpManager.json");
    defer allocator.free(pm_bytecode);
    const pm_addr = try deployContract(&wallet, pm_bytecode);

    return DeployedContracts{
        .perp_manager = pm_addr,
        .usdc = usdc_addr,
        .fees = fees_addr,
        .margin_ratios = margin_addr,
    };
}

fn deployContract(wallet: *Wallet, bytecode: []const u8) !types.Address {
    const tx_hash = try wallet.sendTransaction(.{
        .to = null,
        .data = bytecode,
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

// ---------------------------------------------------------------------------
// Hex helpers
// ---------------------------------------------------------------------------

fn hexToAddress(comptime hex: *const [40]u8) [20]u8 {
    return std.fmt.hexToBytes(20, hex) catch unreachable;
}

fn hexToKey(comptime hex: *const [64]u8) [32]u8 {
    return std.fmt.hexToBytes(32, hex) catch unreachable;
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
    try std.testing.expectEqual(@as(u24, 5000), MOCK_FEES_ARGS.liquidation_fee);
}

test "MOCK_MARGIN_RATIOS_ARGS has expected values" {
    try std.testing.expectEqual(@as(u24, 100000), MOCK_MARGIN_RATIOS_ARGS.min_taker);
    try std.testing.expectEqual(@as(u24, 500000), MOCK_MARGIN_RATIOS_ARGS.max_taker);
    try std.testing.expectEqual(@as(u24, 50000), MOCK_MARGIN_RATIOS_ARGS.liq_taker);
    try std.testing.expectEqual(@as(u24, 100000), MOCK_MARGIN_RATIOS_ARGS.min_maker);
    try std.testing.expectEqual(@as(u24, 500000), MOCK_MARGIN_RATIOS_ARGS.max_maker);
    try std.testing.expectEqual(@as(u24, 50000), MOCK_MARGIN_RATIOS_ARGS.liq_maker);
}

test "MINT_AMOUNT equals 1M USDC in 6-decimal units" {
    try std.testing.expectEqual(@as(u256, 1_000_000_000_000), MINT_AMOUNT);
}

test "artifactPath builds correct path" {
    const path = try artifactPath(std.testing.allocator, "MockFees");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("tests/contracts/out/MockFees.sol/MockFees.json", path);
}
