//! Wrappers for a market's WithdrawalController (perpcity-contracts v1.0.0).
//!
//! Every accounted payout a market makes - a margin withdrawal, the residual
//! equity of a close, a liquidation fee, collected creator or protocol fees -
//! goes through the market's controller. While the controller's rate limit has
//! room the USDC is paid in the same transaction (`InstantPayout`). Otherwise
//! it is escrowed as a claim (`ClaimCreated`) that anyone may `release` to its
//! recipient once the challenge window has elapsed.
//!
//! So a write that "withdraws" can succeed without the wallet's balance moving.
//! Find the claim id with `claimIdFromReceipt` and pay it out later with
//! `release`. Resolve the controller address with
//! `PerpCityContext.getWithdrawalController`; the zero address means the market
//! pays out directly and has no controller.

const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const chain_client = @import("chain_client.zig");
const abi = @import("abi/withdrawal_controller_abi.zig");

const PerpCityContext = context_mod.PerpCityContext;

/// One escrowed claim (`claims(claimId)`). A claim id that was never created
/// reads as all zeros with `status == 0` (none).
pub fn getClaim(ctx: *PerpCityContext, controller: types.Address, claim_id: u256) !types.Claim {
    const result = try chain_client.readContract(
        &ctx.client,
        ctx.allocator,
        controller,
        abi.claims_selector,
        &.{.{ .uint256 = claim_id }},
        &.{ .uint128, .uint128, .address, .uint48, .uint8, .bool },
    );
    defer chain_client.freeReturnValues(result, ctx.allocator);

    return types.Claim{
        .original_amount = @intCast(result[0].uint256),
        .current_amount = @intCast(result[1].uint256),
        .recipient = result[2].address,
        .created_at = @intCast(result[3].uint256),
        .status = @intCast(result[4].uint256),
        .paused = result[5].boolean,
    };
}

/// The claim release delay in seconds (`challengeWindow()`). A pending claim
/// is releasable once this much time has passed since its `created_at`; the
/// window in force at release time applies, not the one at creation.
pub fn getChallengeWindow(ctx: *PerpCityContext, controller: types.Address) !u64 {
    const result = try chain_client.readContract(
        &ctx.client,
        ctx.allocator,
        controller,
        abi.challenge_window_selector,
        &.{},
        &.{.uint48},
    );
    defer chain_client.freeReturnValues(result, ctx.allocator);
    return @intCast(result[0].uint256);
}

/// Pay out a pending claim to its recorded recipient. Permissionless. Reverts
/// `ClaimNotReady` before the challenge window has elapsed, `ClaimNotPending`
/// once it has been released or cancelled, and `ClaimIsPaused` /
/// `ReleasesArePaused` while the guardian has it on hold.
pub fn release(ctx: *PerpCityContext, controller: types.Address, claim_id: u256) !types.Bytes32 {
    return chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        controller,
        abi.release_selector,
        &.{.{ .uint256 = claim_id }},
        0,
    );
}

/// Opt-in revert preflight for `release`: runs the same calldata through
/// eth_call. Returns normally if the release would not revert.
pub fn simulateRelease(ctx: *PerpCityContext, controller: types.Address, claim_id: u256) !void {
    const from = try ctx.client.address();
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        controller,
        abi.release_selector,
        &.{.{ .uint256 = claim_id }},
        from,
    );
}

/// The id of the claim that `controller` created for `recipient` in the
/// transaction `tx_hash`, or null when the payout was instant (or the
/// transaction paid `recipient` nothing). `claimId` and `recipient` are the
/// indexed parameters of `ClaimCreated`. Returns the first match; a single
/// transaction creates at most one claim per payout.
pub fn claimIdFromReceipt(
    ctx: *PerpCityContext,
    controller: types.Address,
    tx_hash: types.Bytes32,
    recipient: types.Address,
) !?u256 {
    const receipt = (try ctx.client.getReceipt(ctx.allocator, tx_hash, 10)) orelse
        return error.ReceiptNotFound;

    for (receipt.logs) |log| {
        if (!std.mem.eql(u8, &log.address, &controller)) continue;
        if (log.topics.len < 3) continue;
        if (!std.mem.eql(u8, &log.topics[0], &abi.claim_created_topic)) continue;
        if (!std.mem.eql(u8, log.topics[2][12..32], &recipient)) continue;
        return std.mem.readInt(u256, &log.topics[1], .big);
    }
    return null;
}
