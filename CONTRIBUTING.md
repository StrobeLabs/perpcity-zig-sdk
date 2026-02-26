# Contributing to PerpCity Zig SDK

## Prerequisites

- [Zig 0.15.2](https://ziglang.org/download/)
- [Anvil](https://book.getfoundry.sh/anvil/) (for integration tests)

## Getting Started

1. Clone the repository:
   ```bash
   git clone https://github.com/StrobeLabs/perpcity-zig-sdk.git
   cd perpcity-zig-sdk
   ```

2. Build the project:
   ```bash
   zig build
   ```

3. Run unit tests:
   ```bash
   zig build test
   ```

## Development Commands

| Command | Description |
|---------|-------------|
| `zig build` | Build the SDK |
| `zig build test` | Run unit tests (pure math, no network) |
| `zig build integration-test` | Run integration tests (requires Anvil) |
| `zig fmt --check src/ tests/` | Check formatting |
| `zig fmt src/ tests/` | Auto-format code |

## Project Structure

```
src/
  root.zig              # Full SDK module (with eth.zig dependency)
  math_root.zig         # Pure math module (no external deps)
  context.zig           # SDK context with RPC provider and wallet
  approve.zig           # USDC approval helpers
  perp_manager.zig      # Core contract interactions
  open_position.zig     # Position operations
  types.zig             # Shared type definitions
  constants.zig         # Protocol constants
  conversions.zig       # Tick/price conversions
  liquidity.zig         # Liquidity calculations
  position.zig          # Position math
  perp.zig              # Perp math
  nonce.zig             # Lock-free nonce management
  gas.zig               # Gas price cache and pre-computed limits
  tx_pipeline.zig       # Transaction pipeline
  state_cache.zig       # Multi-layer state cache
  multi_rpc.zig         # Multi-endpoint failover
  connection.zig        # Connection management
  latency.zig           # Latency tracking
  events.zig            # Event streaming
  position_manager.zig  # Position tracking with triggers
  abi/                  # ABI definitions
tests/
  unit_tests.zig        # Unit test runner
  unit/                 # Unit test files
  integration_tests.zig # Integration test runner
  integration/          # Integration test files
```

## Code Style

- Run `zig fmt` before committing. CI enforces formatting.
- All time-dependent methods accept explicit `now_ms: i64` parameters for deterministic testing. Do not use OS-level clock calls in library code.
- Use comptime where possible for ABI encoding and type-level computation.
- Avoid heap allocations on the hot path. Prefer stack-allocated buffers with bounded sizes.
- Keep the pure math layer (`math_root.zig`) free of external dependencies.

## Pull Request Workflow

1. Create a feature branch from `main`
2. Make your changes
3. Run CI checks locally:
   ```bash
   zig build && zig build test && zig fmt --check src/ tests/
   ```
4. Open a pull request against `main`
5. All CI checks must pass before merge

## Reporting Issues

Open an issue on [GitHub](https://github.com/StrobeLabs/perpcity-zig-sdk/issues) with:

- A description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Zig version (`zig version`)
