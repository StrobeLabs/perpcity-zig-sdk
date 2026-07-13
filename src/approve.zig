const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const chain_client = @import("chain_client.zig");
const erc20_abi = @import("abi/erc20_abi.zig");

const AbiValue = eth.abi_encode.AbiValue;

const PerpCityContext = context_mod.PerpCityContext;

pub const ApproveError = error{
    ZeroApprovalAmount,
    InvalidUsdcAddress,
    InvalidPerpAddress,
    ApproveFailed,
};

/// Approve `perp` (a deployed Perp market) to spend `amount_scaled` USDC
/// (6-decimal units). Returns the approval transaction hash.
pub fn approveUsdc(
    ctx: *PerpCityContext,
    perp: types.Address,
    amount_scaled: u256,
) !types.Bytes32 {
    if (amount_scaled == 0) return ApproveError.ZeroApprovalAmount;

    if (std.mem.eql(u8, &ctx.deployments.usdc, &types.ZERO_ADDRESS)) {
        return ApproveError.InvalidUsdcAddress;
    }

    if (std.mem.eql(u8, &perp, &types.ZERO_ADDRESS)) {
        return ApproveError.InvalidPerpAddress;
    }

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        ctx.deployments.usdc,
        erc20_abi.approve_selector,
        &.{ .{ .address = perp }, .{ .uint256 = amount_scaled } },
        0,
    );

    const receipt = (try ctx.client.getReceipt(ctx.allocator, tx_hash, 10)) orelse
        return ApproveError.ApproveFailed;

    if (receipt.status != 1) return ApproveError.ApproveFailed;

    return tx_hash;
}

/// Approve maximum USDC for a Perp market.
pub fn approveUsdcMax(ctx: *PerpCityContext, perp: types.Address) !types.Bytes32 {
    return approveUsdc(ctx, perp, std.math.maxInt(u256));
}
