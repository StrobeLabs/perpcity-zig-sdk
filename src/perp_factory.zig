const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const perp_factory_abi = @import("abi/perp_factory_abi.zig");

const contract = eth.contract;
const AbiValue = eth.abi_encode.AbiValue;

const PerpCityContext = context_mod.PerpCityContext;

pub const FactoryError = error{
    EmaWindowTooLow,
    StartingPriceTooLow,
    StartingPriceTooHigh,
    EventDecodeFailed,
    TransactionReverted,
};

fn bytes32ToFixedBytes(data: [32]u8) AbiValue.FixedBytes {
    var fb: AbiValue.FixedBytes = .{ .len = 32 };
    @memcpy(&fb.data, &data);
    return fb;
}

/// Deploys a new Perp market via the factory. Returns the deployed Perp
/// contract address (decoded from the `PerpCreated` event).
pub fn createPerp(ctx: *PerpCityContext, params: types.CreatePerpParams) !types.Address {
    if (params.ema_window == 0) return FactoryError.EmaWindowTooLow;

    const tx_hash = try contract.contractWrite(
        ctx.allocator,
        &ctx.wallet,
        ctx.deployments.perp_factory,
        perp_factory_abi.create_perp_selector,
        &.{
            .{ .address = params.owner },
            .{ .string = params.name },
            .{ .string = params.symbol },
            .{ .string = params.token_uri },
            .{ .tuple = &.{
                .{ .address = params.modules.beacon },
                .{ .address = params.modules.fees },
                .{ .address = params.modules.funding },
                .{ .address = params.modules.margin_ratios },
                .{ .address = params.modules.price_impact },
                .{ .address = params.modules.pricing },
            } },
            .{ .uint256 = @as(u256, params.ema_window) },
            .{ .fixed_bytes = bytes32ToFixedBytes(params.salt) },
        },
    );

    const receipt = (try ctx.wallet.waitForReceipt(tx_hash, 10)) orelse
        return FactoryError.EventDecodeFailed;

    if (receipt.status != 1) return FactoryError.TransactionReverted;

    // PerpCreated is non-indexed in v0.1.0: decode the first ABI word
    // (offset 0..32) of the log `data` to get the `perp` address. Filter
    // by emitter so we don't pick up a same-signature event from another
    // contract that ran in the same tx.
    const factory_addr = ctx.deployments.perp_factory;
    for (receipt.logs) |log| {
        if (!std.mem.eql(u8, &log.address, &factory_addr)) continue;
        if (log.topics.len == 0) continue;
        if (!std.mem.eql(u8, &log.topics[0], &perp_factory_abi.perp_created_topic)) continue;
        if (log.data.len < 32) continue;
        var addr: types.Address = undefined;
        @memcpy(&addr, log.data[12..32]);
        return addr;
    }

    return FactoryError.EventDecodeFailed;
}

/// Returns true if `perp` was deployed by this factory.
pub fn isPerp(ctx: *PerpCityContext, perp: types.Address) !bool {
    const result = try contract.contractRead(
        ctx.allocator,
        &ctx.provider,
        ctx.deployments.perp_factory,
        perp_factory_abi.perps_selector,
        &.{.{ .address = perp }},
        &.{.bool},
    );
    defer contract.freeReturnValues(result, ctx.allocator);
    return result[0].boolean;
}
