# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2026-11-11

Aligns the SDK with `perpcity-contracts` v1.0.0, the audited release. Every
selector, event topic, and custom error the SDK defines is pinned by test to
the value solc derives from the v1.0.0 interfaces.

**This release only works against markets deployed from contracts v1.0.0.**
Markets deployed from earlier releases need SDK v0.7.x: the liquidate, backstop,
open, adjust, and `createPerp` selectors all changed, as did every position
event's layout.

### Changed (BREAKING)

- **Deadlines and fee caps.** `OpenTakerPositionParams`, `OpenMakerPositionParams`, `AdjustTakerParams`, `AdjustMakerParams`, and `BackstopParams` gain `deadline` (unix seconds, default `types.NO_DEADLINE`). Taker open and adjust gain `max_total_fee` (default `types.NO_FEE_CAP`), and `AdjustTakerParams` gains `reduce_only` (default `false`). The defaults reproduce the old behavior; set a real deadline for anything that can wait in a mempool, and `reduce_only` on closes.
- **Liquidations take an amount.** `LiquidateParams` gains a required `amount` (perp atoms for a taker, liquidity for a maker), and `OpenPosition.liquidate` takes it as a second argument. Pass the full size for a full liquidation. A partial liquidation must improve health or it reverts `HealthNotImproved`.
- **Liquidations are reported by their own events.** `MakerClosed`, `MakerConverted`, and `TakerClosed` no longer carry `liq_fee` / `is_liquidation`. A liquidation emits the lifecycle event followed by `MakerLiquidated` / `TakerLiquidated` (new `DecodedEvent` variants) with the fee recipient and fee.
- **Event layouts.** `posId`, `owner`, and `feeRecipient` are now indexed and decoded from the log topics. The position events carry the owner, the margin and liquidity deltas, and the post-action balances; the per-side `long_util_fees` / `short_util_fees` on maker events are folded into `lp_fees`. `SwapResult` gains `fee_fund_fee_amt`. `PerpCreatedEvent` gains `latency` and no longer has name, symbol, or token URI. `decodeEvent` returns `error.MissingIndexedTopic` for a recognised event that lacks its indexed topics.
- **Positions are not ERC721 tokens.** `getPositionOwner` reads `positionOwner(posId)` and returns the zero address for an inactive id instead of erroring. `getPositionBalance` is removed (there is no `balanceOf`). `discoverOwnedPositions` is unchanged in use.
- **Margin ratios are not stored per position.** `PositionRawData` and `LiveDetails` lose `liq_margin_ratio` / `backstop_margin_ratio`. `position.liquidationPrice` takes the liquidation ratio as a new `liq_margin_ratio` argument (use `PerpData.taker_bounds` / `maker_bounds`).
- **Market creation.** `CreatePerpParams` drops `name`, `symbol`, and `token_uri`, and requires `governor`, `latency`, and `withdrawal_config`. `perp_factory.isPerp` is removed: the factory no longer keeps a registry of its markets.
- **Fees.** `IFees.fees` now prices the LP fee from pool liquidity and the spot-vs-EMA gap. `PerpData.fees.lp_fee` is the rate at current liquidity with no volatility surcharge, and the new `max_swap_fee` is the module's upper bound. `getPerpData` costs one extra round-trip.
- `MakerDetails` exposes the full `Maker` struct. `TakerDetails` fields are renamed to `last_util_payments_x96` / `last_reserve_util_payments_x96`.
- `module_registry_abi.Module` drops `lockup`; `price_impact` is now `4`.
- `revert.ContractError` follows the v1.0.0 error set. Removed: the timelock, `*_utilization_exceeded`, `starting_price_*`, and `transfer_not_allowed` variants. `retryHint` maps the new `long_close_capacity_exceeded` / `short_close_capacity_exceeded` to `retry_smaller`, and stale-beacon and fee-cap reverts to `retry`.
- **Gas limits.** `gas.GasLimits` is re-sized from the v1.0.0 gas benchmarks, where every call costs more than the old constants allowed (an `openTaker` runs 455k to 1.07M gas against the old 500k limit). `OPEN_TAKER_POS`, `OPEN_MAKER_POS`, `CLOSE_POSITION`, `ADJUST_NOTIONAL`, and `ADJUST_MARGIN` are raised, and `MOVE_MAKER`, `LIQUIDATE`, and `BACKSTOP` are new.
- `testing.setup.AnvilSetup.init` and `testing.anvil.AnvilProcess.start` take an explicit `std.Io` (pass `std.testing.io`).

### Added

- `perp_contract.moveMaker` / `simulateMoveMaker` and `OpenPosition.moveMaker`: replace a maker range atomically on the same position id.
- `PerpCityContext.getPositionPreview` and `OpenPosition.preview`: the contract's settled view of a position (equity, pending funding and fees, `liquidatable`, `backstoppable`), accrued to the current block.
- `withdrawal_controller` module and ABI: `getClaim`, `getChallengeWindow`, `release`, `simulateRelease`, and `claimIdFromReceipt`, for payouts the market escrows instead of paying instantly. `PerpCityContext.getWithdrawalController` resolves a market's controller.
- `PerpCityContext.getRates`, `getPhysicalCloseCapacity`, `getTvlState`, and `getIndexObservation` (beacon index plus its `updated_at`; `IBeacon.index()` returns both as of beacons v1.0.0).
- Decoding for `MakerMoved`, `PositionOwnerUpdated`, `QuoteFolded`, `RatesAndEmasRefreshed` (the only place the EMAs are published), `BadDebtAccounted`, and `PhysicalCapacityUpdated`.
- `tests/contract/abi_golden_test.zig`, pinning every selector, event topic, and custom error the SDK defines to the v1.0.0 artifacts.

### Fixed

- The integration tests were silently skipping since the Zig 0.17 migration: the harness spawned Anvil through an `Io` that cannot start a process, and the failure was treated as "Anvil not installed". They now run, and cover an end-to-end create, trade, move, backstop, liquidate, and event-decode flow against v1.0.0-shaped mocks.

## [0.7.0] - 2026-10-10

### Changed

- **Breaking:** requires Zig 0.17.0 (`minimum_zig_version`), and CI is pinned to 0.17.0. Consumers on Zig 0.16 should stay on v0.6.x.
- Bumped eth.zig to v0.10.0 (the eth.zig Zig 0.17 release). Consumers pinning eth.zig directly must also use v0.10.0 to avoid duplicate-instance link collisions.

## [0.6.2] - 2026-09-22

### Fixed

- Bumped eth.zig to v0.9.2 to fix a WebSocket double free when receiving a close frame or an invalid opcode (StrobeLabs/eth.zig#131). Consumers pinning eth.zig directly must also use v0.9.2 to avoid duplicate-instance link collisions.

## [0.6.1] - 2026-08-19

### Changed

- Bumped eth.zig to v0.9.1, which adds `HttpTransport.lastFailure()` diagnostics for transport-level failures (StrobeLabs/eth.zig#115). Consumers pinning both this SDK and eth.zig directly must pin the same eth.zig version to avoid duplicate-instance link collisions.

## [0.3.0] - 2026-05-19

### Note

- The `v0.2.0` tag was cut before the `perpcity-contracts` v0.1.0 alignment work (PR #6) actually landed on `main`, so consumers pinning `v0.2.0` got an inconsistent snapshot. `v0.3.0` is the first published tag that actually reflects the v0.2.0 changelog entry below plus the PR #7 testing harness fixes.

### Added

- Integration test job wired into CI, plus testing-harness fixes for zig 0.15.2 (PR #7).

## [0.2.0] - 2026-05-11

### Changed (BREAKING)

- Align SDK with `perpcity-contracts` v0.1.0. The monolithic `PerpManager` is gone; each market is a separate `Perp` contract deployed by `PerpFactory`.
- `PerpCityDeployments`: drop `perp_manager`, `lockup_period_module`, `sqrt_price_impact_limit_module`; add `perp_factory`, `module_registry`, `protocol_fee_manager`, `funding_module`, `pricing_module`, `price_impact_module`.
- New high-level wrappers: `sdk.perp_factory` (createPerp, isPerp) and `sdk.perp_contract` (openMaker/openTaker, adjustMaker/adjustTaker, liquidateMaker/Taker, backstopMaker/Taker, donate, touch, syncProtocolFee, collectCreatorFees, collectProtocolFees). `sdk.perp_manager` removed.
- `OpenTakerPositionParams`: replace `(is_long, leverage, unspecified_amount_limit)` with `(margin, perp_delta, amt1_limit)`. Signed `perp_delta` encodes direction.
- `OpenMakerPositionParams`: amount limits widened to `u256`.
- `OpenPosition`: keyed by `perp: Address` instead of `perp_id: Bytes32`; methods now include `adjustMaker/adjustTaker/liquidate/backstop`. `closePosition`, `adjustNotional`, `adjustMargin` removed.
- `MarginRatios` fields renamed `(min, max, liq)` -> `(init, liq, backstop)` to match v0.1.0 `IMarginRatios`.
- `IFees` ABI: `fees()` (no params), `utilFees(long, short)` returning `(uint64, uint64)`, `liqFee()`. Per-constant getters removed.
- `IMarginRatios` ABI: `makerMarginRatios()` and `takerMarginRatios()`. Per-constant getters removed.
- New module ABIs: `funding_abi`, `pricing_abi`, `price_impact_abi`, `module_registry_abi`, `protocol_fee_manager_abi`.
- Events: v0.1.0 `Maker{Opened,Adjusted,Closed,Converted,Backstopped}`, `Taker{Opened,Adjusted,Closed,Backstopped}`, `Donated`, `OpenInterestUpdated`, `CapacityUpdated`. Topic hashes precomputed at comptime in `src/events.zig`.
- `EventRegistry.perp_filter` is now an `Address` (was `Bytes32`).
- `position.zig`: BalanceDelta pack/unpack helpers, `positionSize`, `currentLeverage`, etc. Removed entry-delta-based math that v0.1.0 no longer exposes.
- Testing harness: rewrites `MockFees`, `MockMarginRatios`; adds `MockPerpFactory`, `MockPerp`, `MockFunding`, `MockPricing`, `MockPriceImpact`, `MockBeacon`, `MockModuleRegistry`, `MockProtocolFeeManager`. Foundry profile bumped to solc 0.8.30.
- `beacons` v0.0.1 is API-compatible with the existing `beacon_abi.zig`; no changes required there.

## [0.1.0] - 2026-02-25

### Added

- **Contract interaction** -- Read/write calls with comptime-computed ABI selectors via eth.zig (zabi)
- **Position management** -- `openTakerPosition`, `openMakerPosition`, `closePosition`, `adjustNotional`, `adjustMargin`
- **HFT nonce manager** -- Lock-free atomic nonce acquisition with `std.atomic.Value(u64)`, zero RPC round-trips per transaction
- **Gas cache** -- Pre-computed gas limits for all contract operations, configurable TTL with urgency-based multipliers (low/normal/high/critical)
- **Transaction pipeline** -- Combines nonce manager + gas cache for fire-and-forget transaction submission with gas bump support
- **Multi-RPC failover** -- Automatic endpoint selection based on health status and latency, 30s cooldown on unhealthy endpoints
- **Connection management** -- Dual HTTP/WebSocket connection support with multi-RPC failover
- **State cache** -- Multi-layer caching with configurable TTLs (slow: 60s for fees/bounds, fast: 2s for prices/funding)
- **Pure math** -- Tick/price conversions, sqrt price math, liquidity calculations, position PnL -- all in pure Zig with no external deps
- **Event streaming** -- Comptime keccak256 topic hashes, event identification from logs, subscription registry
- **Position manager** -- Position tracking with stop-loss, take-profit, and trailing stop triggers
- **Latency observability** -- Rolling window latency tracker with min/max/avg/p50/p95/p99 percentiles
- **Pre-approved USDC** -- `setupForTrading()` approves max allowance once at startup, eliminating per-trade approval transactions
- **View functions** -- `getFundingRate`, `getUtilFee`, `getInsurance`, `getOpenInterest` for market data reads
- **Quote functions** -- ABI definitions for `quoteOpenTakerPosition`, `quoteOpenMakerPosition` simulation
- Unit tests for all HFT infrastructure modules (150+ tests)
- Integration test framework with Anvil support
- CI pipeline with build, test, and format checks
