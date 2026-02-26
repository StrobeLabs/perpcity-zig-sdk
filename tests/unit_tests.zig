// Root test file: imports all unit test modules so `zig build test` runs them all.
comptime {
    _ = @import("unit/conversions_test.zig");
    _ = @import("unit/liquidity_test.zig");
    _ = @import("unit/position_calculations_test.zig");
    _ = @import("unit/perp_functions_test.zig");
    _ = @import("unit/user_functions_test.zig");
    _ = @import("unit/errors_test.zig");
    _ = @import("unit/multi_rpc_test.zig");
    _ = @import("unit/connection_test.zig");
    _ = @import("unit/latency_test.zig");
    _ = @import("unit/gas_test.zig");
    _ = @import("unit/state_cache_test.zig");
    _ = @import("unit/events_test.zig");
    _ = @import("unit/tx_pipeline_test.zig");
    _ = @import("unit/position_manager_test.zig");
}
