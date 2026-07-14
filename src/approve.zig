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

/// The `(to, selector, args)` for an ERC20 `approve` of a Perp market, plus the
/// shared input validation. Built once so the write path and the `simulate`
/// preflight encode byte-identical calldata.
const ApproveCall = struct {
    to: types.Address,
    selector: [4]u8,
    args: [2]AbiValue,
};

fn buildApprove(
    ctx: *PerpCityContext,
    perp: types.Address,
    amount_scaled: u256,
) !ApproveCall {
    if (amount_scaled == 0) return ApproveError.ZeroApprovalAmount;

    if (std.mem.eql(u8, &ctx.deployments.usdc, &types.ZERO_ADDRESS)) {
        return ApproveError.InvalidUsdcAddress;
    }

    if (std.mem.eql(u8, &perp, &types.ZERO_ADDRESS)) {
        return ApproveError.InvalidPerpAddress;
    }

    return .{
        .to = ctx.deployments.usdc,
        .selector = erc20_abi.approve_selector,
        .args = .{ .{ .address = perp }, .{ .uint256 = amount_scaled } },
    };
}

/// Approve `perp` (a deployed Perp market) to spend `amount_scaled` USDC
/// (6-decimal units). Returns the approval transaction hash.
pub fn approveUsdc(
    ctx: *PerpCityContext,
    perp: types.Address,
    amount_scaled: u256,
) !types.Bytes32 {
    const c = try buildApprove(ctx, perp, amount_scaled);

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &c.args,
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

/// Opt-in revert preflight for `approveUsdc`: encodes the same calldata and runs
/// it through eth_call. Returns normally if the approval would not revert;
/// propagates the revert as an error. Does not send a transaction.
pub fn simulateApproveUsdc(
    ctx: *PerpCityContext,
    perp: types.Address,
    amount_scaled: u256,
) !void {
    const c = try buildApprove(ctx, perp, amount_scaled);
    const from = try ctx.client.address();
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &c.args,
        from,
    );
}

/// Opt-in revert preflight for `approveUsdcMax`.
pub fn simulateApproveUsdcMax(ctx: *PerpCityContext, perp: types.Address) !void {
    return simulateApproveUsdc(ctx, perp, std.math.maxInt(u256));
}
