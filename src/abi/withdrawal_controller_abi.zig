const eth = @import("eth");
const Function = eth.abi_types.Function;
const Event = eth.abi_types.Event;
const keccak = eth.keccak;

// IWithdrawalController surface of perpcity-contracts v1.0.0 that a trader or
// keeper needs: each market routes accounted payouts through its controller,
// which pays instantly while the rate limit has room and otherwise escrows the
// payout as a claim that anyone may `release` after the challenge window. The
// guardian and governor functions are intentionally not wrapped.

/// `enum ClaimStatus { None, Pending, Completed, Cancelled }`.
pub const ClaimStatus = enum(u8) {
    none = 0,
    pending = 1,
    completed = 2,
    cancelled = 3,
};

pub const claims: Function = .{
    .name = "claims",
    .state_mutability = .view,
    .inputs = &.{
        .{ .name = "claimId", .abi_type = .uint256 },
    },
    .outputs = &.{
        .{ .name = "originalAmount", .abi_type = .uint128 },
        .{ .name = "currentAmount", .abi_type = .uint128 },
        .{ .name = "recipient", .abi_type = .address },
        .{ .name = "createdAt", .abi_type = .uint48 },
        .{ .name = "status", .abi_type = .uint8 },
        .{ .name = "paused", .abi_type = .bool },
    },
};
pub const claims_selector = keccak.selector("claims(uint256)");

pub const next_claim_id: Function = .{
    .name = "nextClaimId",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const next_claim_id_selector = keccak.selector("nextClaimId()");

pub const challenge_window: Function = .{
    .name = "challengeWindow",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint48 },
    },
};
pub const challenge_window_selector = keccak.selector("challengeWindow()");

pub const rate_limit: Function = .{
    .name = "rateLimit",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "capacity", .abi_type = .uint128 },
        .{ .name = "available", .abi_type = .uint128 },
        .{ .name = "refillPerSecond", .abi_type = .uint128 },
        .{ .name = "lastUpdated", .abi_type = .uint48 },
    },
};
pub const rate_limit_selector = keccak.selector("rateLimit()");

pub const releases_paused: Function = .{
    .name = "releasesPaused",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .bool },
    },
};
pub const releases_paused_selector = keccak.selector("releasesPaused()");

pub const total_reserved: Function = .{
    .name = "totalReserved",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .uint256 },
    },
};
pub const total_reserved_selector = keccak.selector("totalReserved()");

pub const perp: Function = .{
    .name = "perp",
    .state_mutability = .view,
    .inputs = &.{},
    .outputs = &.{
        .{ .name = "", .abi_type = .address },
    },
};
pub const perp_selector = keccak.selector("perp()");

/// Pays out a pending claim once its challenge window has elapsed.
/// Permissionless; the USDC always goes to the claim's recorded recipient.
pub const release: Function = .{
    .name = "release",
    .state_mutability = .nonpayable,
    .inputs = &.{
        .{ .name = "claimId", .abi_type = .uint256 },
    },
    .outputs = &.{},
};
pub const release_selector = keccak.selector("release(uint256)");

pub const claim_created_event: Event = .{
    .name = "ClaimCreated",
    .inputs = &.{
        .{ .name = "claimId", .abi_type = .uint256, .indexed = true },
        .{ .name = "recipient", .abi_type = .address, .indexed = true },
        .{ .name = "amount", .abi_type = .uint128 },
    },
};
pub const claim_created_topic = keccak.hash("ClaimCreated(uint256,address,uint128)");

pub const claim_released_event: Event = .{
    .name = "ClaimReleased",
    .inputs = &.{
        .{ .name = "claimId", .abi_type = .uint256, .indexed = true },
        .{ .name = "recipient", .abi_type = .address, .indexed = true },
        .{ .name = "amount", .abi_type = .uint128 },
    },
};
pub const claim_released_topic = keccak.hash("ClaimReleased(uint256,address,uint128)");

pub const instant_payout_event: Event = .{
    .name = "InstantPayout",
    .inputs = &.{
        .{ .name = "recipient", .abi_type = .address, .indexed = true },
        .{ .name = "amount", .abi_type = .uint128 },
        .{ .name = "availableAfter", .abi_type = .uint128 },
    },
};
pub const instant_payout_topic = keccak.hash("InstantPayout(address,uint128,uint128)");
