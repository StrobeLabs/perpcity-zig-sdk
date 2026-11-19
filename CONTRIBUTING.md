# Contributing to PerpCity Zig SDK

## Prerequisites

- [Zig 0.17.0](https://ziglang.org/download/)
- [Foundry](https://book.getfoundry.sh/) (`forge` and `anvil`, for integration tests)

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
| `zig build integration-test` | Run integration tests (needs `anvil` on PATH and the mocks built with `forge build` in `tests/contracts`; skips otherwise) |
| `zig fmt --check src/ tests/` | Check formatting |
| `zig fmt src/ tests/` | Auto-format code |

## Project Structure

```
src/
  root.zig              # Full SDK module (with eth.zig dependency)
  math_root.zig         # Pure math module (no external deps)
  chain_client.zig      # ChainClient seam (EthChainClient prod impl)
  context.zig           # SDK context (holds a ChainClient) + read helpers
  approve.zig           # USDC approval helpers
  perp_contract.zig     # Contract write wrappers (open/adjust/move/liquidate/...)
  perp_factory.zig      # Market creation (createPerp)
  withdrawal_controller.zig # Escrowed payout claims (getClaim / release)
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
  contract_tests.zig    # Contract-layer test runner (in-memory mock chain)
  contract/             # Contract-layer tests, incl. abi_golden_test.zig
  contracts/            # Solidity mocks for the integration tests
  integration_tests.zig # Integration test runner
  integration/          # Integration test files
```

## Tracking a contracts release

The SDK targets one `perpcity-contracts` release at a time (see the README).
When moving to a new one:

1. Update the signature strings in `src/abi/` and the mirrored structs in
   `src/types.zig` / `src/events.zig` from the interfaces at that tag.
2. Regenerate the expected values in `tests/contract/abi_golden_test.zig` from
   the real artifacts (`forge inspect <Interface> methodIdentifiers` and
   `forge inspect <Interface> events` at the tag). This is what catches a
   mistyped signature string, which otherwise compiles cleanly.
3. Update the mocks in `tests/contracts/` to the new function and event shapes
   and run `zig build integration-test`.

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
