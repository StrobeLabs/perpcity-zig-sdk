// Root test file for the contract-layer unit tests: imports every contract
// test module so `zig build contract-test` (and the default `zig build test`)
// runs them. These tests drive the SDK's read path through the ChainClient
// seam with an in-memory mock -- no network or Anvil required.
comptime {
    _ = @import("contract/context_read_test.zig");
}
