const std = @import("std");
const sdk = @import("perpcity_sdk");
const types = sdk.types;

// =============================================================================
// approveUsdc - standard amounts
// =============================================================================

test "approveUsdc - 100 USDC sets correct allowance" {
    // Approve 100 USDC (100_000_000 in 6-decimal scaled units) for the
    // PerpManager contract and verify the on-chain allowance matches.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const amount_scaled: u256 = 100_000_000; // 100 USDC
    // const tx_hash = try sdk.approve.approveUsdc(&ctx, amount_scaled);
    //
    // try std.testing.expect(!std.mem.eql(u8, &tx_hash, &types.ZERO_BYTES32));
    //
    // // Verify on-chain allowance by reading the USDC contract
    // // const allowance = try readUsdcAllowance(&ctx, test_wallet_address, ctx.deployments.perp_manager);
    // // try std.testing.expectEqual(amount_scaled, allowance);
    return error.SkipZigTest;
}

test "approveUsdc - 1000 USDC sets correct allowance" {
    // Approve 1000 USDC (1_000_000_000 in 6-decimal scaled units) and
    // verify the transaction succeeds with a valid tx_hash.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const amount_scaled: u256 = 1_000_000_000; // 1000 USDC
    // const tx_hash = try sdk.approve.approveUsdc(&ctx, amount_scaled);
    //
    // try std.testing.expect(!std.mem.eql(u8, &tx_hash, &types.ZERO_BYTES32));
    return error.SkipZigTest;
}

// =============================================================================
// approveUsdc - edge cases
// =============================================================================

test "approveUsdc - zero amount revokes approval" {
    // Approving zero should be rejected by the SDK validation layer
    // (ZeroApprovalAmount error), since a zero-amount approval is
    // treated as an error to prevent accidental revocation.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const result = sdk.approve.approveUsdc(&ctx, 0);
    // try std.testing.expectError(error.ZeroApprovalAmount, result);
    return error.SkipZigTest;
}

test "approveUsdc - max uint256 sets max allowance" {
    // Approve the maximum uint256 value (infinite approval pattern).
    // This should succeed and set the allowance to type(uint256).max.
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // const tx_hash = try sdk.approve.approveUsdcMax(&ctx);
    //
    // try std.testing.expect(!std.mem.eql(u8, &tx_hash, &types.ZERO_BYTES32));
    //
    // // Verify the allowance is max uint256
    // // const allowance = try readUsdcAllowance(&ctx, test_wallet_address, ctx.deployments.perp_manager);
    // // try std.testing.expectEqual(std.math.maxInt(u256), allowance);
    return error.SkipZigTest;
}

// =============================================================================
// approveUsdc - sequential approvals
// =============================================================================

test "approveUsdc - sequential approvals update correctly" {
    // Verify that calling approveUsdc multiple times correctly updates
    // the on-chain allowance each time (ERC-20 approve replaces, not adds).
    //
    // TODO: Enable when zabi integration is complete
    // var ctx = try createTestContext(std.testing.allocator);
    // defer ctx.deinit();
    //
    // // First approval: 100 USDC
    // const tx1 = try sdk.approve.approveUsdc(&ctx, 100_000_000);
    // try std.testing.expect(!std.mem.eql(u8, &tx1, &types.ZERO_BYTES32));
    //
    // // Second approval: 500 USDC (replaces the 100 USDC approval)
    // const tx2 = try sdk.approve.approveUsdc(&ctx, 500_000_000);
    // try std.testing.expect(!std.mem.eql(u8, &tx2, &types.ZERO_BYTES32));
    //
    // // The current allowance should be 500 USDC, not 600 USDC
    // // const allowance = try readUsdcAllowance(&ctx, test_wallet_address, ctx.deployments.perp_manager);
    // // try std.testing.expectEqual(@as(u256, 500_000_000), allowance);
    //
    // // Third approval: max uint256
    // const tx3 = try sdk.approve.approveUsdcMax(&ctx);
    // try std.testing.expect(!std.mem.eql(u8, &tx3, &types.ZERO_BYTES32));
    return error.SkipZigTest;
}
