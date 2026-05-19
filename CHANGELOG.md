# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
