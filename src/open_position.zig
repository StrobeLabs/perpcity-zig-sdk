const std = @import("std");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const perp_manager = @import("perp_manager.zig");

const PerpCityContext = context_mod.PerpCityContext;

/// An open position on a PerpCity perpetual market.
pub const OpenPosition = struct {
    ctx: *PerpCityContext,
    perp_id: types.Bytes32,
    position_id: u256,
    is_long: ?bool,
    is_maker: ?bool,
    tx_hash: ?types.Bytes32,

    pub fn closePosition(self: *const OpenPosition, params: types.ClosePositionParams) !types.ClosePositionResult {
        return perp_manager.closePosition(self.ctx, self.perp_id, self.position_id, params);
    }

    pub fn liveDetails(self: *const OpenPosition) !types.LiveDetails {
        const data = try self.ctx.getOpenPositionData(
            self.perp_id,
            self.position_id,
            self.is_long orelse false,
            self.is_maker orelse false,
        );
        return data.live_details;
    }

    pub fn adjustNotional(self: *const OpenPosition, usd_delta: i128, perp_limit: u128) !types.Bytes32 {
        return perp_manager.adjustNotional(self.ctx, .{
            .position_id = self.position_id,
            .usd_delta = usd_delta,
            .perp_limit = perp_limit,
        });
    }

    pub fn adjustMargin(self: *const OpenPosition, margin_delta: i128) !types.Bytes32 {
        return perp_manager.adjustMargin(self.ctx, .{
            .position_id = self.position_id,
            .margin_delta = margin_delta,
        });
    }

    pub fn perpIdHex(self: *const OpenPosition) [64]u8 {
        return std.fmt.bytesToHex(self.perp_id, .lower);
    }
};
