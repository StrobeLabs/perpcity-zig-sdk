// Root test file for the contract-layer unit tests: imports every contract
// test module so `zig build contract-test` (and the default `zig build test`)
// runs them. These tests drive the SDK's read path through the ChainClient
// seam with an in-memory mock -- no network or Anvil required.
comptime {
    _ = @import("contract/context_read_test.zig");
    _ = @import("contract/context_getters_test.zig");
    _ = @import("contract/context_batch_test.zig");
    _ = @import("contract/context_write_test.zig");
    _ = @import("contract/context_simulate_test.zig");
    _ = @import("contract/context_events_test.zig");
    _ = @import("contract/context_discover_test.zig");
    _ = @import("contract/revert_test.zig");
    _ = @import("contract/context_simulate_override_test.zig");
    _ = @import("contract/context_multicall_test.zig");
}
