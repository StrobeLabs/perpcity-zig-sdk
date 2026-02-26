# perpcity-zig-sdk

High-performance, low-level Zig SDK for the PerpCity perpetual futures protocol. Built for HFT bots and latency-sensitive trading systems.

## Why Zig?

This SDK is designed for use cases where nanoseconds matter. Zig gives us:

- **Zero runtime overhead** -- no GC, no hidden allocations, no async coloring
- **Deterministic memory layout** -- cache-friendly structs with predictable performance
- **Comptime ABI encoding** -- function selectors computed at compile time, zero runtime cost
- **Direct hardware control** -- atomic nonce management, lock-free data structures

If you're building a trading bot in Python or TypeScript, this is not the SDK for you. This is for systems that need sub-millisecond transaction construction and direct EVM interaction with no abstraction tax.

## Features

- **Contract interaction** -- Read/write calls with comptime-computed selectors via [eth.zig](https://github.com/StrobeLabs/eth.zig)
- **Position management** -- Open/close taker and maker positions, adjust margin and notional
- **HFT nonce manager** -- Lock-free atomic nonce acquisition, no RPC round-trip per transaction
- **Gas cache** -- Pre-computed gas limits and fee caching to skip `estimateGas` calls
- **Transaction pipeline** -- Combines nonce manager + gas cache for fire-and-forget submission
- **Multi-RPC failover** -- Automatic failover across multiple RPC endpoints
- **State cache** -- Multi-layer caching (mark prices, perp configs) with configurable TTLs
- **Pure math** -- Tick/price conversions, sqrt price math, liquidity calculations -- all in pure Zig with no external deps
- **Event streaming** -- Subscription registry for on-chain event processing

## Quick Start

```zig
const eth = @import("eth");
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

// Ensure USDC approval
try ctx.setupForTrading();

// Open a 10x long taker position
const position = try sdk.perp_manager.openTakerPosition(&ctx, perp_id, .{
    .margin = 1000.0,
    .leverage = 10.0,
    .is_long = true,
    .unspecified_amount_limit = 0,
});
```

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

## Architecture

```
Pure math layer (no dependencies):
  types, constants, conversions, liquidity, position, perp

HFT infrastructure:
  nonce manager, gas cache, tx pipeline, state cache, multi-rpc

Contract interaction (requires eth.zig):
  context, approve, perp_manager, open_position

ABI definitions:
  perp_manager_abi, erc20_abi, fees_abi, margin_ratios_abi, beacon_abi
```

The pure math layer has zero external dependencies and can be used standalone for off-chain calculations (mark price conversions, PnL estimation, liquidation checks).

## Testing

```bash
# Unit tests (pure math, no network)
zig build test

# Integration tests (requires Anvil)
anvil &
zig build integration-test
```

## License

MIT
