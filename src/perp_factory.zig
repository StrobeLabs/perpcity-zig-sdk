const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const context_mod = @import("context.zig");
const chain_client = @import("chain_client.zig");
const perp_factory_abi = @import("abi/perp_factory_abi.zig");

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

/// The `(to, selector, args)` for a `createPerp` call. Holds the params and the
/// nested `modules` tuple storage so a single `abiArgs()` builds byte-identical
/// calldata for both the write path and the `simulate` preflight. The dynamic
/// `string` args borrow `params`' slices, which the caller owns and must keep
/// alive for the duration of the call.
const CreatePerpCall = struct {
    to: types.Address,
    selector: [4]u8,
    modules: [6]AbiValue,
    params: types.CreatePerpParams,

    fn abiArgs(self: *const CreatePerpCall) [7]AbiValue {
        return .{
            .{ .address = self.params.owner },
            .{ .string = self.params.name },
            .{ .string = self.params.symbol },
            .{ .string = self.params.token_uri },
            .{ .tuple = &self.modules },
            .{ .uint256 = @as(u256, self.params.ema_window) },
            .{ .fixed_bytes = bytes32ToFixedBytes(self.params.salt) },
        };
    }
};

fn buildCreatePerp(ctx: *PerpCityContext, params: types.CreatePerpParams) !CreatePerpCall {
    if (params.ema_window == 0) return FactoryError.EmaWindowTooLow;

    return .{
        .to = ctx.deployments.perp_factory,
        .selector = perp_factory_abi.create_perp_selector,
        .modules = .{
            .{ .address = params.modules.beacon },
            .{ .address = params.modules.fees },
            .{ .address = params.modules.funding },
            .{ .address = params.modules.margin_ratios },
            .{ .address = params.modules.price_impact },
            .{ .address = params.modules.pricing },
        },
        .params = params,
    };
}

/// Deploys a new Perp market via the factory. Returns the deployed Perp
/// contract address (decoded from the `PerpCreated` event).
pub fn createPerp(ctx: *PerpCityContext, params: types.CreatePerpParams) !types.Address {
    const c = try buildCreatePerp(ctx, params);
    const args = c.abiArgs();

    const tx_hash = try chain_client.writeContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &args,
        0,
    );

    const receipt = (try ctx.client.getReceipt(ctx.allocator, tx_hash, 10)) orelse
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

/// Opt-in revert preflight for `createPerp`: encodes the same calldata and runs
/// it through eth_call. Returns normally if the deployment would not revert;
/// propagates the revert as an error. Does not send a transaction.
pub fn simulateCreatePerp(ctx: *PerpCityContext, params: types.CreatePerpParams) !void {
    const c = try buildCreatePerp(ctx, params);
    const args = c.abiArgs();
    return chain_client.simulateContract(
        &ctx.client,
        ctx.allocator,
        c.to,
        c.selector,
        &args,
    );
}

/// Returns true if `perp` was deployed by this factory.
pub fn isPerp(ctx: *PerpCityContext, perp: types.Address) !bool {
    const result = try chain_client.readContract(
        &ctx.client,
        ctx.allocator,
        ctx.deployments.perp_factory,
        perp_factory_abi.perps_selector,
        &.{.{ .address = perp }},
        &.{.bool},
    );
    defer chain_client.freeReturnValues(result, ctx.allocator);
    return result[0].boolean;
}
