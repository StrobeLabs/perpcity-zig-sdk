const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const erc20_abi = @import("abi/erc20_abi.zig");

const contract = eth.contract;
const AbiValue = eth.abi_encode.AbiValue;

const PerpCityContext = context_mod.PerpCityContext;

pub const ApproveError = error{
    ZeroApprovalAmount,
    InvalidUsdcAddress,
    InvalidPerpManagerAddress,
    ApproveFailed,
};

/// Approve the PerpManager contract to spend `amount_scaled` USDC (6-decimal units).
/// Returns the transaction hash.
pub fn approveUsdc(ctx: *PerpCityContext, amount_scaled: u256) !types.Bytes32 {
    if (amount_scaled == 0) {
        return ApproveError.ZeroApprovalAmount;
    }

    if (std.mem.eql(u8, &ctx.deployments.usdc, &types.ZERO_ADDRESS)) {
        return ApproveError.InvalidUsdcAddress;
    }

    if (std.mem.eql(u8, &ctx.deployments.perp_manager, &types.ZERO_ADDRESS)) {
        return ApproveError.InvalidPerpManagerAddress;
    }

    const tx_hash = try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.usdc,
        erc20_abi.approve_selector,
        &.{ .{ .address = ctx.deployments.perp_manager }, .{ .uint256 = amount_scaled } },
    );

    // Wait for receipt and verify success
    const receipt = (try ctx.wallet.waitForReceipt(tx_hash, 10)) orelse
        return ApproveError.ApproveFailed;

    if (receipt.status != 1) return ApproveError.ApproveFailed;

    return tx_hash;
}

/// Approve maximum USDC for the PerpManager contract.
pub fn approveUsdcMax(ctx: *PerpCityContext) !types.Bytes32 {
    return approveUsdc(ctx, std.math.maxInt(u256));
}
