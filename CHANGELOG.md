# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
