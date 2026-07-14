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

// The KMS constructors are referenced here so a signature change breaks the
// build. They are not invoked: KmsSigner.init calls kms:GetPublicKey (a network
// call needing AWS credentials), so the KMS signing path is exercised only by
// integration tests, not CI.
test "KMS constructors are wired (compile-time reference only)" {
    const ctx_kms = @TypeOf(sdk.context.PerpCityContext.initWithKms);
    const ec_kms = @TypeOf(EthChainClient.createWithKms);
    try std.testing.expect(@typeInfo(ctx_kms) == .@"fn");
    try std.testing.expect(@typeInfo(ec_kms) == .@"fn");
}
