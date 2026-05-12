const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const keccak = eth.keccak;

pub const protocol_fee: Function = .{
    .name = "protocolFee",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const protocol_fee_selector = keccak.selector("protocolFee()");

pub const set_protocol_fee: Function = .{
    .name = "setProtocolFee",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "newProtocolFee", .abi_type = .uint256 },
    },
    .outputs = &.{},
};
pub const set_protocol_fee_selector = keccak.selector("setProtocolFee(uint256)");

pub const can_collect_protocol_fees: Function = .{
    .name = "canCollectProtocolFees",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "caller", .abi_type = .address },
    },
    .outputs = &.{
        .{ .name = "", .abi_type = .bool },
    },
};
pub const can_collect_protocol_fees_selector = keccak.selector("canCollectProtocolFees(address)");

pub const protocol_fee_set_event: Event = .{
    .name = "ProtocolFeeSet",
    .inputs = &.{
        .{ .name = "protocolFee", .abi_type = .uint256 },
    },
};
pub const protocol_fee_set_topic = keccak.hash("ProtocolFeeSet(uint256)");
