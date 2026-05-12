const eth = @import("eth");
const Function = eth.abi_types.Function;
const keccak = eth.keccak;

// IMarginRatios v0.1.0 surface (perpcity-contracts).
// Both functions return (init, liq, backstop) scaled by 1e6.

pub const maker_margin_ratios: Function = .{
    .name = "makerMarginRatios",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "init", .abi_type = .uint24 },
        .{ .name = "liq", .abi_type = .uint24 },
        .{ .name = "backstop", .abi_type = .uint24 },
    },
};
pub const maker_margin_ratios_selector = keccak.selector("makerMarginRatios()");

pub const taker_margin_ratios: Function = .{
    .name = "takerMarginRatios",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "init", .abi_type = .uint24 },
        .{ .name = "liq", .abi_type = .uint24 },
        .{ .name = "backstop", .abi_type = .uint24 },
    },
};
pub const taker_margin_ratios_selector = keccak.selector("takerMarginRatios()");
