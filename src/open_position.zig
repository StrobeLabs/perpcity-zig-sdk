const std = @import("std");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const perp_contract = @import("perp_contract.zig");

const PerpCityContext = context_mod.PerpCityContext;

/// An open position on a PerpCity perpetual market. Each `OpenPosition` is tied
/// to a single `Perp` contract address.
pub const OpenPosition = struct {
    ctx: *PerpCityContext,
    perp: types.Address,
    position_id: u256,
    is_maker: bool,
    tx_hash: ?types.Bytes32,

    pub fn liveDetails(self: *const OpenPosition) !types.LiveDetails {
        const raw = try self.ctx.getPositionRawData(self.perp, self.position_id);
        return types.LiveDetails{
            .margin = @as(f64, @floatFromInt(raw.margin)) / 1_000_000.0,
            .perp_delta = raw.delta,
        };
    }

    /// The contract's own settled view of this position: equity, pending
    /// funding and fees, and the liquidatable / backstoppable flags.
    pub fn preview(self: *const OpenPosition) !types.PositionPreview {
        return self.ctx.getPositionPreview(self.perp, self.position_id);
    }

    pub fn moveMaker(self: *const OpenPosition, params: types.MoveMakerParams) !types.Bytes32 {
        var p = params;
        p.position_id = self.position_id;
        return perp_contract.moveMaker(self.ctx, self.perp, p);
    }

    pub fn adjustMaker(self: *const OpenPosition, params: types.AdjustMakerParams) !types.Bytes32 {
        var p = params;
        p.position_id = self.position_id;
        return perp_contract.adjustMaker(self.ctx, self.perp, p);
    }

    pub fn adjustTaker(self: *const OpenPosition, params: types.AdjustTakerParams) !types.Bytes32 {
        var p = params;
        p.position_id = self.position_id;
        return perp_contract.adjustTaker(self.ctx, self.perp, p);
    }

    /// Liquidate `amount` of this position: liquidity for a maker, absolute
    /// perp exposure for a taker.
    pub fn liquidate(self: *const OpenPosition, fee_recipient: types.Address, amount: u128) !types.Bytes32 {
        const params: types.LiquidateParams = .{
            .position_id = self.position_id,
            .fee_recipient = fee_recipient,
            .amount = amount,
        };
        return if (self.is_maker)
            perp_contract.liquidateMaker(self.ctx, self.perp, params)
        else
            perp_contract.liquidateTaker(self.ctx, self.perp, params);
    }

    pub fn backstop(
        self: *const OpenPosition,
        margin_in: u128,
        position_recipient: types.Address,
        deadline: u64,
    ) !types.Bytes32 {
        const params: types.BackstopParams = .{
            .position_id = self.position_id,
            .margin_in = margin_in,
            .position_recipient = position_recipient,
            .deadline = deadline,
        };
        return if (self.is_maker)
            perp_contract.backstopMaker(self.ctx, self.perp, params)
        else
            perp_contract.backstopTaker(self.ctx, self.perp, params);
    }

    pub fn perpHex(self: *const OpenPosition) [40]u8 {
        return std.fmt.bytesToHex(self.perp, .lower);
    }
};
