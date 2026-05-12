const std = @import("std");

/// Anvil process manager for local EVM integration testing.
///
/// Spawns an Anvil instance as a child process on a configurable port, waits
/// for it to print "Listening on" on stderr, and shuts the process down on
/// `stop()`. Designed for short-lived integration tests against a local node.
pub const AnvilProcess = struct {
    child: std.process.Child,
    rpc_url: []const u8,
    allocator: std.mem.Allocator,

    /// Default port for Anvil when none is specified.
    pub const DEFAULT_PORT: u16 = 8546;

    /// How long to wait for Anvil to print "Listening on" before giving up.
    const STARTUP_TIMEOUT_NS: u64 = 10 * std.time.ns_per_s;

    /// Size of the buffer used to read Anvil's stderr output during startup.
    const STDERR_BUF_SIZE: usize = 4096;

    /// Well-known Anvil default account address (account 0).
    pub const DEFAULT_ACCOUNT: [20]u8 = parseHexAddress("f39Fd6e51aad88F6F4ce6aB8827279cffFb92266");

    /// Well-known Anvil default private key (account 0).
    pub const DEFAULT_PRIVATE_KEY: [32]u8 = parseHexKey("ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");

    /// Chain ID used by Anvil in tests.
    pub const CHAIN_ID: u64 = 31337;

    pub const AnvilError = error{
        StartupTimeout,
        ProcessExitedEarly,
        SpawnFailed,
        StderrReadFailed,
    };

    /// Spawn an Anvil process on the given port and wait for it to be ready.
    pub fn start(allocator: std.mem.Allocator, port: u16) !AnvilProcess {
        var port_buf: [5]u8 = undefined;
        const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch unreachable;

        var child = std.process.Child.init(
            &.{ "anvil", "--port", port_str, "--chain-id", "31337", "--block-time", "1" },
            allocator,
        );
        child.stdin_behavior = .Ignore;
        // Anvil (foundry 1.x) prints its banner + "Listening on" to stdout, so
        // pipe stdout and ignore stderr. We close stdout once we've seen the
        // readiness marker so anvil doesn't deadlock on a full pipe.
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Ignore;

        child.spawn() catch return AnvilError.SpawnFailed;
        errdefer _ = child.kill() catch {};

        if (!waitForReady(&child)) {
            return AnvilError.StartupTimeout;
        }

        if (child.stdout) |out| {
            out.close();
            child.stdout = null;
        }

        const rpc_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port});

        return AnvilProcess{
            .child = child,
            .rpc_url = rpc_url,
            .allocator = allocator,
        };
    }

    /// Spawn Anvil on the default port (8546).
    pub fn startDefault(allocator: std.mem.Allocator) !AnvilProcess {
        return start(allocator, DEFAULT_PORT);
    }

    /// Kill the Anvil process and free associated resources.
    pub fn stop(self: *AnvilProcess) void {
        _ = self.child.kill() catch {};
        self.allocator.free(self.rpc_url);
        self.* = undefined;
    }

    /// Poll Anvil's stdout for the "Listening on" readiness message.
    fn waitForReady(child: *std.process.Child) bool {
        const stdout_file = child.stdout orelse return false;

        var accumulated: [STDERR_BUF_SIZE]u8 = undefined;
        var total_read: usize = 0;
        var read_buf: [256]u8 = undefined;

        const deadline = std.time.nanoTimestamp() + @as(i128, STARTUP_TIMEOUT_NS);

        while (std.time.nanoTimestamp() < deadline) {
            const bytes_read = stdout_file.read(&read_buf) catch break;

            if (bytes_read == 0) {
                std.Thread.sleep(10 * std.time.ns_per_ms);
                continue;
            }

            const copy_len = @min(bytes_read, STDERR_BUF_SIZE - total_read);
            if (copy_len > 0) {
                @memcpy(accumulated[total_read..][0..copy_len], read_buf[0..copy_len]);
                total_read += copy_len;
            }

            if (containsListening(accumulated[0..total_read])) return true;
        }

        return containsListening(accumulated[0..total_read]);
    }

    fn containsListening(data: []const u8) bool {
        return std.mem.indexOf(u8, data, "Listening on") != null;
    }

    fn parseHexAddress(comptime hex: *const [40]u8) [20]u8 {
        var out: [20]u8 = undefined;
        _ = std.fmt.hexToBytes(&out, hex) catch unreachable;
        return out;
    }

    fn parseHexKey(comptime hex: *const [64]u8) [32]u8 {
        var out: [32]u8 = undefined;
        _ = std.fmt.hexToBytes(&out, hex) catch unreachable;
        return out;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AnvilProcess constants are correct" {
    const expected_addr = [_]u8{
        0xf3, 0x9F, 0xd6, 0xe5, 0x1a, 0xad, 0x88, 0xF6, 0xF4, 0xce,
        0x6a, 0xB8, 0x82, 0x72, 0x79, 0xcf, 0xfF, 0xb9, 0x22, 0x66,
    };
    try std.testing.expectEqualSlices(u8, &expected_addr, &AnvilProcess.DEFAULT_ACCOUNT);
    try std.testing.expectEqual(@as(u64, 31337), AnvilProcess.CHAIN_ID);
    try std.testing.expectEqual(@as(u16, 8546), AnvilProcess.DEFAULT_PORT);
}

test "containsListening detects readiness marker" {
    try std.testing.expect(AnvilProcess.containsListening("Listening on 127.0.0.1:8546"));
    try std.testing.expect(AnvilProcess.containsListening("some prefix\nListening on 127.0.0.1:8546\n"));
    try std.testing.expect(!AnvilProcess.containsListening("Starting Anvil..."));
    try std.testing.expect(!AnvilProcess.containsListening("Listening o"));
    try std.testing.expect(!AnvilProcess.containsListening(""));
}
