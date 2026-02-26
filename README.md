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

Requires **Zig 0.15.2**.

## Quick Start

```zig
const sdk = @import("perpcity_sdk");

// Initialize context
var ctx = sdk.context.PerpCityContext.init(
    allocator,
    "https://your-rpc-url.com",
    private_key,
    deployments,
);
ctx.fixPointers();
defer ctx.deinit();

// Approve USDC once at startup (max allowance)
try ctx.setupForTrading();

// Open a 10x long taker position
const position = try sdk.perp_manager.openTakerPosition(&ctx, perp_id, .{
    .margin = 1000.0,
    .leverage = 10.0,
    .is_long = true,
    .unspecified_amount_limit = 0,
});
```

## Architecture

```
Pure math layer (no dependencies):
  types, constants, conversions, liquidity, position, perp

HFT infrastructure (no dependencies):
  nonce, gas, tx_pipeline, state_cache, multi_rpc, connection,
  latency, events, position_manager

Contract interaction (requires eth.zig):
  context, approve, perp_manager, open_position

ABI definitions:
  perp_manager_abi, erc20_abi, fees_abi, margin_ratios_abi, beacon_abi
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

- [Perp City Documentation](https://docs.perp.city)
- [Strobe Labs](https://strobelabs.io)
- [TypeScript SDK](https://github.com/StrobeLabs/perpcity-sdk)
