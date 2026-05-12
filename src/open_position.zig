const std = @import("std");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const perp_contract = @import("perp_contract.zig");

const PerpCityContext = context_mod.PerpCityContext;

/// An open position on a PerpCity perpetual market in v0.1.0. Each `OpenPosition`
/// is tied to a single `Perp` contract address.
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
            .liq_margin_ratio = raw.liq_margin_ratio,
            .backstop_margin_ratio = raw.backstop_margin_ratio,
        };
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

    pub fn liquidate(self: *const OpenPosition, fee_recipient: types.Address) !types.Bytes32 {
        const params: types.LiquidateParams = .{
            .position_id = self.position_id,
            .fee_recipient = fee_recipient,
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
    ) !types.Bytes32 {
        const params: types.BackstopParams = .{
            .position_id = self.position_id,
            .margin_in = margin_in,
            .position_recipient = position_recipient,
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
