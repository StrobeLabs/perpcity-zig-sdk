const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// All tests in this module are placeholders. They skip via `error.SkipZigTest`
// because they require a live Anvil node with the v0.1.0 mock stack deployed.
// Enable them once the integration harness wires up `sdk.testing.setup.AnvilSetup`.

test "approveUsdc - 100 USDC sets correct allowance" {
    // Approve 100 USDC for a deployed Perp market and verify the on-chain
    // allowance matches.
    //
    //   var harness = try sdk.testing.setup.AnvilSetup.init(allocator, io);
    //   defer harness.deinit();
    //   const perp = try sdk.perp_factory.createPerp(&harness.context, params);
    //   const tx_hash = try sdk.approve.approveUsdc(&harness.context, perp, 100_000_000);
    return error.SkipZigTest;
}

test "approveUsdc - zero amount is rejected" {
    // Approving zero should return `ApproveError.ZeroApprovalAmount` without
    // submitting a transaction.
    //
    //   const result = sdk.approve.approveUsdc(&ctx, perp, 0);
    //   try std.testing.expectError(error.ZeroApprovalAmount, result);
    return error.SkipZigTest;
}

test "approveUsdc - max uint256 sets max allowance" {
    // Verify infinite-approval pattern via approveUsdcMax.
    //
    //   const tx_hash = try sdk.approve.approveUsdcMax(&ctx, perp);
    return error.SkipZigTest;
}

test "approveUsdc - sequential approvals update correctly" {
    // ERC20 approve replaces (does not add). Verify two sequential calls leave
    // the allowance at the second value, not the sum.
    return error.SkipZigTest;
}

test "ensureApproval is idempotent per perp" {
    // ensureApproval should only submit one approve tx per Perp address, but
    // should approve again for a different perp.
    return error.SkipZigTest;
}

comptime {
    _ = &types.ZERO_BYTES32;
}
