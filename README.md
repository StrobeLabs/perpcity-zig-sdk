# PerpCity Zig SDK

High-performance, low-level Zig SDK for the PerpCity perpetual futures protocol on Base. Built for HFT bots and latency-sensitive trading systems.

## Why Zig?

This SDK is designed for use cases where nanoseconds matter. Zig gives us:

- **Zero runtime overhead** -- no GC, no hidden allocations, no async coloring
- **Deterministic memory layout** -- cache-friendly structs with predictable performance
- **Comptime ABI encoding** -- function selectors computed at compile time, zero runtime cost
- **Direct hardware control** -- atomic nonce management, lock-free data structures

If you're building a trading bot in Python or TypeScript, use [perpcity-sdk](https://github.com/StrobeLabs/perpcity-sdk) or [perpcity-python-sdk](https://github.com/StrobeLabs/perpcity-python-sdk) instead. This SDK is for systems that need sub-millisecond transaction construction and direct EVM interaction with no abstraction tax.

## Features

- **Contract interaction** -- Read/write calls with comptime-computed selectors via [eth.zig](https://github.com/StrobeLabs/eth.zig)
- **Position management** -- Open/close taker and maker positions, adjust margin and notional
- **HFT nonce manager** -- Lock-free atomic nonce acquisition, no RPC round-trip per transaction
- **Gas cache** -- Pre-computed gas limits and fee caching to skip `estimateGas` calls
- **Transaction pipeline** -- Combines nonce manager + gas cache for fire-and-forget submission
- **Multi-RPC failover** -- Automatic failover across multiple RPC endpoints with latency tracking
- **State cache** -- Multi-layer caching (mark prices, perp configs) with configurable TTLs
- **Pure math** -- Tick/price conversions, sqrt price math, liquidity calculations -- all in pure Zig with no external deps
- **Event streaming** -- Subscription registry for on-chain event processing
- **Position manager** -- Stop-loss, take-profit, and trailing stop triggers
- **Latency observability** -- Rolling window latency tracking with p50/p95/p99 percentiles

## Installation

Add to your `build.zig.zon`:

```zig
.dependencies = .{
    .perpcity_sdk = .{
        .url = "git+https://github.com/StrobeLabs/perpcity-zig-sdk.git#<commit>",
    },
},
```

Then in `build.zig`:

```zig
const sdk_dep = b.dependency("perpcity_sdk", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("perpcity_sdk", sdk_dep.module("perpcity_sdk"));
```

Requires **Zig 0.16.0**.

## Quick Start

```zig
const sdk = @import("perpcity_sdk");

// Build a context -- it owns the RPC transport and wallet on the heap, so the
// value is safe to move around (no pointer fixups needed).
var ctx = try sdk.context.PerpCityContext.init(
    allocator,
    "https://arb1.arbitrum.io/rpc",
    private_key, // [32]u8
    deployments, // sdk.types.PerpCityDeployments
);
defer ctx.deinit();

// Approve USDC once for this market (max allowance).
try ctx.setupForTrading(perp);

// Size a 10x long from margin + price, then open the taker position.
const perp_delta = try sdk.sizing.derivePerpDelta(1000.0, 10.0, mark_price, true);
const position = try sdk.perp_contract.openTaker(&ctx, perp, .{
    .margin = 1000.0,
    .perp_delta = perp_delta, // signed: positive = long, negative = short
    .amt1_limit = 0, // USD-side slippage limit
});
```

## Architecture

```text
Pure math layer (no dependencies):
  types, constants, conversions, sizing, funding, liquidity, position, perp

HFT infrastructure (no dependencies):
  nonce, gas, tx_pipeline, state_cache, multi_rpc, connection,
  latency, events, position_manager

Contract interaction (requires eth.zig):
  chain_client (ChainClient seam + EthChainClient), context,
  perp_contract, perp_factory, approve

ABI definitions:
  perp_abi, perp_factory_abi, module_registry_abi, protocol_fee_manager_abi,
  fees_abi, margin_ratios_abi, funding_abi, pricing_abi, price_impact_abi,
  beacon_abi, erc20_abi
```

The pure math and HFT infrastructure layers have zero external dependencies and can be used standalone for off-chain calculations (mark price conversions, PnL estimation, liquidation checks) and trading infrastructure (nonce management, gas caching, latency tracking).

## Development

### Build

```bash
zig build
```

### Test

```bash
# Unit tests (pure math + HFT infrastructure, no network)
zig build test

# Integration tests (requires Anvil running locally)
anvil &
zig build integration-test
```

### Lint

```bash
zig fmt --check src/ tests/
```

## Environment Setup

Create a `.env.local` file:

```env
# Required for integration tests
PRIVATE_KEY=your_private_key_here
RPC_URL=https://your-rpc-url.com

# Contract addresses (Base Sepolia)
PERP_MANAGER_ADDRESS=0x...
USDC_ADDRESS=0x...
```

## License

MIT

## Links

- [Perp City Documentation](https://docs.perpcity.io)
- [Strobe Labs](https://strobelabs.io)
- [TypeScript SDK](https://github.com/StrobeLabs/perpcity-sdk)
