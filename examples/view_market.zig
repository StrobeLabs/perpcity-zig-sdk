const std = @import("std");
const sdk = @import("perpcity_sdk");

pub fn main(init: std.process.Init) !void {
    const rpc_url = init.environ_map.get("RPC_URL") orelse {
        std.debug.print("error: set RPC_URL (an Arbitrum RPC endpoint)\n", .{});
        std.process.exit(1);
    };

    const perp_hex = init.environ_map.get("PERP_MANAGER_ADDRESS") orelse {
        std.debug.print("error: set PERP_MANAGER_ADDRESS (a market contract address)\n", .{});
        std.process.exit(1);
    };

    std.debug.print("RPC_URL = {s}\n", .{rpc_url});
    std.debug.print("PERP_MANAGER_ADDRESS = {s}\n", .{perp_hex});

    // TODO: decode perp_hex -> sdk.types.Address
    // TODO: var ctx = try sdk.context.PerpCityContext.init(init.gpa, rpc_url, ...); defer ctx.deinit();
    // TODO: getPerpData / getFundingRate / getIndexValue / TICK_SPACING, then print
}
