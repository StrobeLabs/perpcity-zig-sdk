// Golden ABI test: every selector and event topic the SDK defines, pinned to the
// value solc derives from the perpcity-contracts v1.0.0 interfaces
// (`forge inspect <Interface> methodIdentifiers` / `events` at tag v1.0.0).
//
// The SDK computes these at comptime from hand-written signature strings, so a
// typo in a string (a wrong tuple member, a missing `uint64 deadline`) would
// otherwise compile cleanly and only fail on-chain as an unknown selector or a
// silently unmatched log. Regenerate the tables from the contracts repo when
// the SDK moves to a new contracts release.
const std = @import("std");
const sdk = @import("perpcity_sdk");

const abi = sdk.abi;
const Topics = sdk.events.Topics;

fn expectSelector(comptime hex: *const [8]u8, actual: [4]u8) !void {
    var expected: [4]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, hex);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

fn expectTopic(comptime hex: *const [64]u8, actual: [32]u8) !void {
    var expected: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&expected, hex);
    try std.testing.expectEqualSlices(u8, &expected, &actual);
}

test "IPerp selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("3e7eea36", abi.perp_abi.accounted_tvl_selector); // accountedTvl
    try expectSelector("7bd08a1a", abi.perp_abi.adjust_maker_selector); // adjustMaker
    try expectSelector("4c124b86", abi.perp_abi.adjust_taker_selector); // adjustTaker
    try expectSelector("2965081d", abi.perp_abi.backstop_maker_selector); // backstopMaker
    try expectSelector("19eda872", abi.perp_abi.backstop_taker_selector); // backstopTaker
    try expectSelector("5cfc1a51", abi.perp_abi.capacity_selector); // capacity
    try expectSelector("7d31dcc0", abi.perp_abi.collect_creator_fees_selector); // collectCreatorFees
    try expectSelector("2a54db01", abi.perp_abi.collect_protocol_fees_selector); // collectProtocolFees
    try expectSelector("ddaf429d", abi.perp_abi.cumulatives_selector); // cumulatives
    try expectSelector("2f07ad80", abi.perp_abi.donate_selector); // donate
    try expectSelector("e51493bc", abi.perp_abi.ema_window_selector); // emaWindow
    try expectSelector("e394732b", abi.perp_abi.fee_fund_selector); // feeFund
    try expectSelector("b25cdccf", abi.perp_abi.funding_state_selector); // fundingState
    try expectSelector("0c340a24", abi.perp_abi.governor_selector); // governor
    try expectSelector("7c990b07", abi.perp_abi.latency_selector); // latency
    try expectSelector("14ca0f4c", abi.perp_abi.liquidate_maker_selector); // liquidateMaker
    try expectSelector("bfb4b1c7", abi.perp_abi.liquidate_taker_selector); // liquidateTaker
    try expectSelector("3f02ad20", abi.perp_abi.maker_details_selector); // makerDetails
    try expectSelector("f7e80e98", abi.perp_abi.modules_selector); // modules
    try expectSelector("e2471c97", abi.perp_abi.move_maker_selector); // moveMaker
    try expectSelector("cf95061a", abi.perp_abi.next_pos_id_selector); // nextPosId
    try expectSelector("fa5a2e62", abi.perp_abi.open_interest_selector); // openInterest
    try expectSelector("dbf66cd6", abi.perp_abi.open_maker_selector); // openMaker
    try expectSelector("1d920967", abi.perp_abi.open_taker_selector); // openTaker
    try expectSelector("8da5cb5b", abi.perp_abi.owner_selector); // owner
    try expectSelector("f03570c8", abi.perp_abi.permissionless_donations_enabled_selector); // permissionlessDonationsEnabled
    try expectSelector("b526e5ce", abi.perp_abi.physical_close_capacity_selector); // physicalCloseCapacity
    try expectSelector("641ad8a9", abi.perp_abi.pool_state_selector); // poolState
    try expectSelector("b3060d36", abi.perp_abi.position_owner_selector); // positionOwner
    try expectSelector("99fbab88", abi.perp_abi.positions_selector); // positions
    try expectSelector("4dd7c2a9", abi.perp_abi.preview_position_selector); // previewPosition
    try expectSelector("b0e21e8a", abi.perp_abi.protocol_fee_selector); // protocolFee
    try expectSelector("43f48fbd", abi.perp_abi.rates_selector); // rates
    try expectSelector("f382e606", abi.perp_abi.read_beacon_index_selector); // readBeaconIndex
    try expectSelector("7085ac95", abi.perp_abi.solvency_state_selector); // solvencyState
    try expectSelector("46a79d33", abi.perp_abi.sync_protocol_fee_selector); // syncProtocolFee
    try expectSelector("a681fa2d", abi.perp_abi.taker_details_selector); // takerDetails
    try expectSelector("a55526db", abi.perp_abi.touch_selector); // touch
    try expectSelector("3f23fa1a", abi.perp_abi.tvl_cap_selector); // tvlCap
    try expectSelector("2d04d2f5", abi.perp_abi.utilization_band_selector); // utilizationBand
    try expectSelector("b7d93508", abi.perp_abi.withdrawal_controller_selector); // withdrawalController
    try expectTopic("dbcafd00395fff98625ed30d465cca9eede44a0dae950cac30d32fb9d92e0487", abi.perp_abi.bad_debt_accounted_topic); // BadDebtAccounted
    try expectTopic("fe42fdaaba337eb89d0a1ba85925ff87357139fe3dfacc940d0cf9566b548d40", abi.perp_abi.capacity_updated_topic); // CapacityUpdated
    try expectTopic("af6f0ffd55e91192427c83d24821702e6ed9b3dfacf969394281590a5ed00d92", abi.perp_abi.donated_topic); // Donated
    try expectTopic("867c59df8ef3ea10a16a572ab85d718d1972f7feabfe847d83d818e60929ca1e", abi.perp_abi.maker_adjusted_topic); // MakerAdjusted
    try expectTopic("4b6aac8d4ce998ced2f6f6e6cffb9cef0aa49bdd783143813b6845e14ff871ba", abi.perp_abi.maker_backstopped_topic); // MakerBackstopped
    try expectTopic("181a101fe3eb4e5adcaea5a4409bc933dd26341a7c7179252d17b863b99fa671", abi.perp_abi.maker_closed_topic); // MakerClosed
    try expectTopic("5dfddc3ff94e76acf24a54b00d5a855ffd7704f0f7ff0eb2cb54f65df66bc8cc", abi.perp_abi.maker_converted_topic); // MakerConverted
    try expectTopic("ab8324c9ed835b7bd8a9b0411a39e508a1df4fa1707f159db06897b3dfee7f44", abi.perp_abi.maker_liquidated_topic); // MakerLiquidated
    try expectTopic("c475caf3ea500603e349cc0bb3f48dea0fe01b76bb5f65c0a35a62f34e59de7e", abi.perp_abi.maker_moved_topic); // MakerMoved
    try expectTopic("ea3ba68e0eb61c62cdf81a21ee41f306e2551414cbb0ed6cda3aad946e0eb738", abi.perp_abi.maker_opened_topic); // MakerOpened
    try expectTopic("2cfcd40a0a33efd1a2cc618e2df899730c84f9df55549afc46d02937b59bf3e6", abi.perp_abi.open_interest_updated_topic); // OpenInterestUpdated
    try expectTopic("d94f7512df329182d51ae5d209a5d368f4e5c6e4442ed632bc572ead1aa7b613", abi.perp_abi.physical_capacity_updated_topic); // PhysicalCapacityUpdated
    try expectTopic("84d4f777b8104806c9eb3a78d71a668383a852c0d4eceb873c808f805a718169", abi.perp_abi.position_owner_updated_topic); // PositionOwnerUpdated
    try expectTopic("481ed1985f6be40e5d23a087237aadd15cd8aa22302ab90d719de1525db56182", abi.perp_abi.quote_folded_topic); // QuoteFolded
    try expectTopic("24ade31ed405c75b2486b61b581337ddebf24e6601e85b988f30eaa1fb7ab9eb", abi.perp_abi.rates_and_emas_refreshed_topic); // RatesAndEmasRefreshed
    try expectTopic("c7ca5680aa92db12f83b06a5dcfa8e623c7d7e1e97ca9d16d3a11e1be98f98f8", abi.perp_abi.taker_adjusted_topic); // TakerAdjusted
    try expectTopic("c6779121432107396b73135fce3baa93eff302c7986be1b76d17e7b653c3db84", abi.perp_abi.taker_backstopped_topic); // TakerBackstopped
    try expectTopic("f75081db50efa183348fcf2b16f56ae49f811be3f2009f0ed5ad4f5fb5f49bf2", abi.perp_abi.taker_closed_topic); // TakerClosed
    try expectTopic("74e6ccfa6bab3e020c58093b8f8adbc3168136b94d24e8f27a6439c31c023ba6", abi.perp_abi.taker_liquidated_topic); // TakerLiquidated
    try expectTopic("1fa3ed5129b3c75e604c7878b4be8f6b301c308ece67791254ec60ab82d77c12", abi.perp_abi.taker_opened_topic); // TakerOpened
}

test "IPerpFactory selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("2fdabe72", abi.perp_factory_abi.create_perp_selector); // createPerp
    try expectSelector("fa62e317", abi.perp_factory_abi.perp_implementation_selector); // perpImplementation
    try expectTopic("9e1124db88459a4e932f32dd28acc4bc6f1a1a2c4dde3f2778ef3dfd90189b6d", abi.perp_factory_abi.perp_created_topic); // PerpCreated
}

test "IModuleRegistry selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("8e78fbe9", abi.module_registry_abi.modules_selector); // modules
    try expectSelector("ad0d832c", abi.module_registry_abi.register_module_selector); // registerModule
    try expectSelector("28f81978", abi.module_registry_abi.unregister_module_selector); // unregisterModule
    try expectTopic("9f1315bdb042466232bcb7b5c4c70a161ac5d8c7c84ee950e96bb69b2b287cc6", abi.module_registry_abi.module_registered_topic); // ModuleRegistered
    try expectTopic("b64c797fe5c124f90bfd322d886d057d479319cbc8d998b490ff39db2c269c2a", abi.module_registry_abi.module_unregistered_topic); // ModuleUnregistered
}

test "IProtocolFeeManager selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("4908c53c", abi.protocol_fee_manager_abi.can_collect_protocol_fees_selector); // canCollectProtocolFees
    try expectSelector("8da5cb5b", abi.protocol_fee_manager_abi.owner_selector); // owner
    try expectSelector("b0e21e8a", abi.protocol_fee_manager_abi.protocol_fee_selector); // protocolFee
    try expectSelector("787dce3d", abi.protocol_fee_manager_abi.set_protocol_fee_selector); // setProtocolFee
    try expectTopic("db5aafdb29539329e37d4e3ee869bc4031941fd55a5dfc92824fbe34b204e30d", abi.protocol_fee_manager_abi.protocol_fee_set_topic); // ProtocolFeeSet
}

test "IFees selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("709db758", abi.fees_abi.fees_selector); // fees
    try expectSelector("3fb0da64", abi.fees_abi.liq_fee_selector); // liqFee
    try expectSelector("66edecce", abi.fees_abi.max_swap_fee_selector); // maxSwapFee
    try expectSelector("87ba6600", abi.fees_abi.util_fees_selector); // utilFees
}

test "IFunding selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("0a0185c6", abi.funding_abi.funding_selector); // funding
}

test "IMarginRatios selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("b583a929", abi.margin_ratios_abi.maker_margin_ratios_selector); // makerMarginRatios
    try expectSelector("97019e5c", abi.margin_ratios_abi.taker_margin_ratios_selector); // takerMarginRatios
}

test "IPriceImpact selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("2fbcd3b4", abi.price_impact_abi.sqrt_price_bounds_selector); // sqrtPriceBounds
}

test "IPricing selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("0fa23b8a", abi.pricing_abi.fair_price_selector); // fairPrice
}

test "IWithdrawalController selectors and topics match perpcity-contracts v1.0.0" {
    try expectSelector("861a1412", abi.withdrawal_controller_abi.challenge_window_selector); // challengeWindow
    try expectSelector("a888c2cd", abi.withdrawal_controller_abi.claims_selector); // claims
    try expectSelector("a0021cf1", abi.withdrawal_controller_abi.next_claim_id_selector); // nextClaimId
    try expectSelector("bfa4c00c", abi.withdrawal_controller_abi.perp_selector); // perp
    try expectSelector("61e08e72", abi.withdrawal_controller_abi.rate_limit_selector); // rateLimit
    try expectSelector("37bdc99b", abi.withdrawal_controller_abi.release_selector); // release
    try expectSelector("5fbddf7f", abi.withdrawal_controller_abi.releases_paused_selector); // releasesPaused
    try expectSelector("c71b0e1c", abi.withdrawal_controller_abi.total_reserved_selector); // totalReserved
    try expectTopic("77dd07aa5019a7b0e605b437e1f8ad5a0deadf8dda64522419ab0de18e50c75f", abi.withdrawal_controller_abi.claim_created_topic); // ClaimCreated
    try expectTopic("ecf3943f26adb0c755676784624d7478e112a05b849000ad53177207ebc7ec9f", abi.withdrawal_controller_abi.claim_released_topic); // ClaimReleased
    try expectTopic("d9a1d5251230456f9abd0e2a5019c4306119467d275cca3412a717b2658b8f0e", abi.withdrawal_controller_abi.instant_payout_topic); // InstantPayout
}

test "events.Topics match perpcity-contracts v1.0.0" {
    try expectTopic("dbcafd00395fff98625ed30d465cca9eede44a0dae950cac30d32fb9d92e0487", Topics.BAD_DEBT_ACCOUNTED); // BadDebtAccounted
    try expectTopic("fe42fdaaba337eb89d0a1ba85925ff87357139fe3dfacc940d0cf9566b548d40", Topics.CAPACITY_UPDATED); // CapacityUpdated
    try expectTopic("af6f0ffd55e91192427c83d24821702e6ed9b3dfacf969394281590a5ed00d92", Topics.DONATED); // Donated
    try expectTopic("867c59df8ef3ea10a16a572ab85d718d1972f7feabfe847d83d818e60929ca1e", Topics.MAKER_ADJUSTED); // MakerAdjusted
    try expectTopic("4b6aac8d4ce998ced2f6f6e6cffb9cef0aa49bdd783143813b6845e14ff871ba", Topics.MAKER_BACKSTOPPED); // MakerBackstopped
    try expectTopic("181a101fe3eb4e5adcaea5a4409bc933dd26341a7c7179252d17b863b99fa671", Topics.MAKER_CLOSED); // MakerClosed
    try expectTopic("5dfddc3ff94e76acf24a54b00d5a855ffd7704f0f7ff0eb2cb54f65df66bc8cc", Topics.MAKER_CONVERTED); // MakerConverted
    try expectTopic("ab8324c9ed835b7bd8a9b0411a39e508a1df4fa1707f159db06897b3dfee7f44", Topics.MAKER_LIQUIDATED); // MakerLiquidated
    try expectTopic("c475caf3ea500603e349cc0bb3f48dea0fe01b76bb5f65c0a35a62f34e59de7e", Topics.MAKER_MOVED); // MakerMoved
    try expectTopic("ea3ba68e0eb61c62cdf81a21ee41f306e2551414cbb0ed6cda3aad946e0eb738", Topics.MAKER_OPENED); // MakerOpened
    try expectTopic("2cfcd40a0a33efd1a2cc618e2df899730c84f9df55549afc46d02937b59bf3e6", Topics.OPEN_INTEREST_UPDATED); // OpenInterestUpdated
    try expectTopic("9e1124db88459a4e932f32dd28acc4bc6f1a1a2c4dde3f2778ef3dfd90189b6d", Topics.PERP_CREATED); // PerpCreated
    try expectTopic("d94f7512df329182d51ae5d209a5d368f4e5c6e4442ed632bc572ead1aa7b613", Topics.PHYSICAL_CAPACITY_UPDATED); // PhysicalCapacityUpdated
    try expectTopic("84d4f777b8104806c9eb3a78d71a668383a852c0d4eceb873c808f805a718169", Topics.POSITION_OWNER_UPDATED); // PositionOwnerUpdated
    try expectTopic("481ed1985f6be40e5d23a087237aadd15cd8aa22302ab90d719de1525db56182", Topics.QUOTE_FOLDED); // QuoteFolded
    try expectTopic("24ade31ed405c75b2486b61b581337ddebf24e6601e85b988f30eaa1fb7ab9eb", Topics.RATES_AND_EMAS_REFRESHED); // RatesAndEmasRefreshed
    try expectTopic("c7ca5680aa92db12f83b06a5dcfa8e623c7d7e1e97ca9d16d3a11e1be98f98f8", Topics.TAKER_ADJUSTED); // TakerAdjusted
    try expectTopic("c6779121432107396b73135fce3baa93eff302c7986be1b76d17e7b653c3db84", Topics.TAKER_BACKSTOPPED); // TakerBackstopped
    try expectTopic("f75081db50efa183348fcf2b16f56ae49f811be3f2009f0ed5ad4f5fb5f49bf2", Topics.TAKER_CLOSED); // TakerClosed
    try expectTopic("74e6ccfa6bab3e020c58093b8f8adbc3168136b94d24e8f27a6439c31c023ba6", Topics.TAKER_LIQUIDATED); // TakerLiquidated
    try expectTopic("1fa3ed5129b3c75e604c7878b4be8f6b301c308ece67791254ec60ab82d77c12", Topics.TAKER_OPENED); // TakerOpened
}

test "IBeacon selectors and topics match beacons v1.0.0" {
    try expectSelector("2986c0e5", abi.beacon_abi.index_selector); // index
    try expectSelector("4686cef7", abi.beacon_abi.tw_avg_selector); // twAvg
    try expectTopic("acfc085c9be45d2b3f9e5c09a19d4a95749cc16939519c13e090de3a4cb192c6", Topics.INDEX_UPDATED); // IndexUpdated
}

test "revert table decodes every custom error declared by perpcity-contracts v1.0.0" {
    // Names are those of `libraries/Errors.sol` plus the errors declared on
    // IPerpFactory, IPerpGuardHook, and IProtocolFeeManager at tag v1.0.0.
    const cases = [_]struct { []const u8, sdk.revert.ContractError }{
        .{ "281df4aa", .abdicated }, // Abdicated
        .{ "d08a3568", .aggregate_swap_fees_too_high }, // AggregateSwapFeesTooHigh
        .{ "6c776dda", .beacon_index_unreadable }, // BeaconIndexUnreadable
        .{ "1ab7da6b", .deadline_expired }, // DeadlineExpired
        .{ "3532c744", .donations_restricted }, // DonationsRestricted
        .{ "c657a809", .ema_window_too_low }, // EmaWindowTooLow
        .{ "0e8c9a42", .health_not_improved }, // HealthNotImproved
        .{ "63c8ca5d", .identical_ticks }, // IdenticalTicks
        .{ "ed126f97", .insufficient_liquidity_to_fill }, // InsufficientLiquidityToFill
        .{ "99571bc0", .invalid_callback_action }, // InvalidCallbackAction
        .{ "84d09fb1", .long_close_capacity_exceeded }, // LongCloseCapacityExceeded
        .{ "b2c649db", .margin_ratio_too_low }, // MarginRatioTooLow
        .{ "00562c4f", .margin_too_high }, // MarginTooHigh
        .{ "38f5e1a7", .margin_too_low }, // MarginTooLow
        .{ "24f14ba6", .max_amt_exceeded }, // MaxAmtExceeded
        .{ "c89df80f", .max_total_fee_exceeded }, // MaxTotalFeeExceeded
        .{ "0470009e", .min_amt_unmet }, // MinAmtUnmet
        .{ "fece0035", .negative_equity }, // NegativeEquity
        .{ "e94943ae", .negative_margin }, // NegativeMargin
        .{ "dbcefbf3", .non_maker_position }, // NonMakerPosition
        .{ "12d39e8a", .non_taker_position }, // NonTakerPosition
        .{ "c0ef17d3", .no_surplus }, // NoSurplus
        .{ "5c64c19c", .no_system_funds }, // NoSystemFunds
        .{ "ddeb79ba", .not_liquidatable }, // NotLiquidatable
        .{ "ae18210a", .not_pool_manager }, // NotPoolManager
        .{ "f7b3b391", .position_does_not_exist }, // PositionDoesNotExist
        .{ "fb30d03a", .price_impact_too_high }, // PriceImpactTooHigh
        .{ "e10dffe6", .price_outside_range }, // PriceOutsideRange
        .{ "46e46f2e", .reduce_only_violated }, // ReduceOnlyViolated
        .{ "deacb1fc", .short_close_capacity_exceeded }, // ShortCloseCapacityExceeded
        .{ "61200552", .stale_beacon_index }, // StaleBeaconIndex
        .{ "d6acf910", .ticks_out_of_bounds }, // TicksOutOfBounds
        .{ "5c427cd9", .unauthorized_caller }, // UnauthorizedCaller
        .{ "d92e233d", .zero_address }, // ZeroAddress
        .{ "1f2a2005", .zero_amount }, // ZeroAmount
        .{ "0bcb6784", .zero_capacity }, // ZeroCapacity
        .{ "6f0f5899", .zero_delta }, // ZeroDelta
        .{ "10074548", .zero_liquidity }, // ZeroLiquidity
        .{ "0dc149f0", .already_initialized }, // AlreadyInitialized
        .{ "26a19fe0", .amount_not_decreased }, // AmountNotDecreased
        .{ "17e94742", .claim_is_paused }, // ClaimIsPaused
        .{ "af67ab56", .claim_not_paused }, // ClaimNotPaused
        .{ "48f8d3b1", .claim_not_pending }, // ClaimNotPending
        .{ "57155ae3", .claim_not_ready }, // ClaimNotReady
        .{ "ee3675d4", .not_governor }, // NotGovernor
        .{ "ef6d0f02", .not_guardian }, // NotGuardian
        .{ "0a0a1dbe", .not_perp }, // NotPerp
        .{ "7a539c7c", .releases_are_paused }, // ReleasesArePaused
        .{ "b0e52638", .tvl_cap_exceeded }, // TvlCapExceeded
        .{ "c705313f", .window_not_increased }, // WindowNotIncreased
        .{ "4acbbb65", .zero_window }, // ZeroWindow
        .{ "a457695f", .invalid_perp_implementation }, // InvalidPerpImplementation
        .{ "09ee12d5", .not_a_contract }, // NotAContract
        .{ "fb6fc0b7", .not_protocol_owner }, // NotProtocolOwner
        .{ "b7cc5070", .unauthorized_pool_action }, // UnauthorizedPoolAction
        .{ "499fddb1", .protocol_fee_too_high }, // ProtocolFeeTooHigh
    };
    for (cases) |case| {
        var data: [4]u8 = undefined;
        _ = try std.fmt.hexToBytes(&data, case[0]);
        try std.testing.expectEqual(sdk.revert.Revert{ .contract_error = case[1] }, sdk.revert.decode(&data));
    }
}
