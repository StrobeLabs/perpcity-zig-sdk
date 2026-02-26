// Root test file: imports all integration test modules so
// `zig build integration-test` runs them all.
//
// All tests currently skip with error.SkipZigTest because the contract
// interaction layer (eth.zig RPC calls) requires a running Anvil instance.
// Run: anvil & zig build integration-test
comptime {
    _ = @import("integration/context_test.zig");
    _ = @import("integration/trading_test.zig");
    _ = @import("integration/approval_test.zig");
}
