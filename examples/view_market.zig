const std = @import("std");
const sdk = @import("perpcity_sdk");

pub fn main(init: std.process.Init) !void {
    const rpc_url = init.environ_map.get("RPC_URL") orelse {
        std.debug.print("error: set RPC_URL (an Arbitrum RPC endpoint)\n", .{});
        std.process.exit(1);
    };

    const perp_hex = init.environ_map.get("PERP_ADDRESS") orelse {
        std.debug.print("error: set PERP_ADDRESS (a market contract address)\n", .{});
        std.process.exit(1);
    };

    // Decode the hex market address into a 20-byte Address object
    const hex = if (std.mem.startsWith(u8, perp_hex, "0x")) perp_hex[2..] else perp_hex;
    var perp: sdk.types.Address = undefined;
    _ = std.fmt.hexToBytes(&perp, hex) catch {
        std.debug.print("error: PERP_ADDRESS must be a 20-byte hex address\n", .{});
        std.process.exit(1);
    };

    // Read-only context: the write-path fields (private key, deployments) are
    // never touched by the reads below, so a zeroed key and placeholder
    // deployments are sufficient.
    const dummy_key: [32]u8 = @splat(0);
    const deployments = sdk.types.PerpCityDeployments{
        .perp_factory = sdk.types.ZERO_ADDRESS,
        .module_registry = sdk.types.ZERO_ADDRESS,
        .protocol_fee_manager = sdk.types.ZERO_ADDRESS,
        .usdc = sdk.types.ZERO_ADDRESS,
    };

    var ctx = try sdk.context.PerpCityContext.init(init.gpa, rpc_url, dummy_key, deployments);
    defer ctx.deinit();

    const data = try ctx.getPerpData(perp);
    const funding = try ctx.getFundingRate(perp);
    const index_raw = try ctx.getIndexValue(data.beacon);
    const index = try sdk.conversions.scaleFromX96(index_raw);
    const tick_spacing = sdk.constants.TICK_SPACING;

    std.debug.print("market 0x{x}\n", .{perp});
    std.debug.print("  mark price:    {d}\n", .{data.mark});
    std.debug.print("  index:         {d}\n", .{index});
    std.debug.print("  funding/day:   {d}%\n", .{funding.rate_per_day});
    std.debug.print("  tick spacing:  {d}\n", .{tick_spacing});
    std.debug.print("  fees: creator={d} insurance={d} lp={d} liq={d}\n", .{
        data.fees.creator_fee, data.fees.insurance_fee,
        data.fees.lp_fee,      data.fees.liquidation_fee,
    });
}
