const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const keccak = eth.keccak;

// IModuleRegistry v1.0.0
// enum Module { Pricing, Funding, Fees, MarginRatios, PriceImpact }

pub const Module = enum(u8) {
    pricing = 0,
    funding = 1,
    fees = 2,
    margin_ratios = 3,
    price_impact = 4,
};

pub const register_module: Function = .{
    .name = "registerModule",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "moduleType", .abi_type = .uint8 },
        .{ .name = "module", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const register_module_selector = keccak.selector("registerModule(uint8,address)");

pub const unregister_module: Function = .{
    .name = "unregisterModule",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "moduleType", .abi_type = .uint8 },
        .{ .name = "module", .abi_type = .address },
    },
    .outputs = &.{},
};
pub const unregister_module_selector = keccak.selector("unregisterModule(uint8,address)");

pub const modules: Function = .{
    .name = "modules",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "moduleType", .abi_type = .uint8 },
        .{ .name = "module", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .bool },
    },
};
pub const modules_selector = keccak.selector("modules(uint8,address)");

pub const module_registered_event: Event = .{
    .name = "ModuleRegistered",
    .inputs = &.{
        .{ .name = "moduleType", .abi_type = .uint8 },
        .{ .name = "module", .abi_type = .address },
    },
};
pub const module_registered_topic = keccak.hash("ModuleRegistered(uint8,address)");

pub const module_unregistered_event: Event = .{
    .name = "ModuleUnregistered",
    .inputs = &.{
        .{ .name = "moduleType", .abi_type = .uint8 },
        .{ .name = "module", .abi_type = .address },
    },
};
pub const module_unregistered_topic = keccak.hash("ModuleUnregistered(uint8,address)");
