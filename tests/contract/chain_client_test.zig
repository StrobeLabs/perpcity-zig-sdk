const std = @import("std");
const sdk = @import("perpcity_sdk");

const EthChainClient = sdk.chain_client.EthChainClient;

// The raw-key path constructs and tears down without a network call (the
// address derives locally from the key), so this regression-guards the
// `destroy` changes made for the KMS variant: the `kms_signer == null` branch
// must free cleanly under the testing allocator.
test "EthChainClient raw-key create/destroy is leak-clean and has no KMS signer" {
    const alloc = std.testing.allocator;
    const private_key = [_]u8{0x11} ** 32;

    const ec = try EthChainClient.create(alloc, "http://localhost:8545", private_key);
    defer ec.destroy();

    try std.testing.expect(ec.kms_signer == null);
    try std.testing.expect(ec.kms_key_id == null);

    // Address derivation is local (secp256k1), so this needs no node.
    var cc = ec.client();
    const addr = try cc.address();
    var all_zero = true;
    for (addr) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

// createWithFallback constructs without any network call (transports connect
// lazily), so this regression-guards the fallback allocation/free discipline:
// the provider + owned URL copies must free cleanly under the testing allocator.
test "createWithFallback builds a multi-endpoint read client, leak-clean" {
    const alloc = std.testing.allocator;
    const private_key = [_]u8{0x22} ** 32;
    const urls = [_][]const u8{ "http://primary:8545", "http://backup:8545" };

    const ec = try EthChainClient.createWithFallback(alloc, &urls, private_key, .{});
    defer ec.destroy();

    try std.testing.expect(ec.fallback != null);
    try std.testing.expect(ec.fallback_urls != null);
    try std.testing.expectEqual(@as(usize, 2), ec.fallback_urls.?.len);
    // The URLs are owned copies, not the caller's slices.
    try std.testing.expect(ec.fallback_urls.?[0].ptr != urls[0].ptr);
    try std.testing.expectEqualStrings("http://primary:8545", ec.fallback_urls.?[0]);
}

test "createWithFallback accepts a single endpoint and rejects an empty list" {
    const alloc = std.testing.allocator;
    const private_key = [_]u8{0x33} ** 32;

    const one = [_][]const u8{"http://only:8545"};
    const ec = try EthChainClient.createWithFallback(alloc, &one, private_key, .{});
    defer ec.destroy();
    try std.testing.expectEqual(@as(usize, 1), ec.fallback_urls.?.len);

    const empty = [_][]const u8{};
    try std.testing.expectError(error.NoEndpoints, EthChainClient.createWithFallback(alloc, &empty, private_key, .{}));
}

// The KMS constructors' exact signatures are asserted at compile time, so a
// change to parameter order/types or the return payload breaks the build. They
// are not invoked: KmsSigner.init calls kms:GetPublicKey (a network call needing
// AWS credentials), so the KMS signing path is exercised by integration, not CI.
test "KMS constructors have the intended signatures (compile-time)" {
    const create_info = @typeInfo(@TypeOf(EthChainClient.createWithKms)).@"fn";
    try std.testing.expectEqual(@as(usize, 4), create_info.params.len);
    try std.testing.expect(create_info.params[0].type.? == std.mem.Allocator);
    try std.testing.expect(create_info.params[1].type.? == []const u8); // rpc_url
    try std.testing.expect(create_info.params[2].type.? == []const u8); // region
    try std.testing.expect(create_info.params[3].type.? == []const u8); // key_id
    try std.testing.expect(@typeInfo(create_info.return_type.?).error_union.payload == *EthChainClient);

    const init_info = @typeInfo(@TypeOf(sdk.context.PerpCityContext.initWithKms)).@"fn";
    try std.testing.expectEqual(@as(usize, 5), init_info.params.len);
    try std.testing.expect(init_info.params[0].type.? == std.mem.Allocator);
    try std.testing.expect(init_info.params[1].type.? == []const u8); // rpc_url
    try std.testing.expect(init_info.params[2].type.? == []const u8); // region
    try std.testing.expect(init_info.params[3].type.? == []const u8); // key_id
    try std.testing.expect(init_info.params[4].type.? == sdk.types.PerpCityDeployments);
    try std.testing.expect(@typeInfo(init_info.return_type.?).error_union.payload == sdk.context.PerpCityContext);
}
