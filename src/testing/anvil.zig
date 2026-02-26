const std = @import("std");

/// Anvil process manager for local EVM integration testing.
///
/// Spawns an Anvil instance as a child process on a configurable port,
/// waits for it to become ready, and provides a clean shutdown method.
/// Designed to be used in integration tests where a local EVM node is needed.
pub const AnvilProcess = struct {
    /// The spawned Anvil child process handle.
    child: std.process.Child,

    /// The HTTP JSON-RPC URL for connecting to this Anvil instance
    /// (e.g. "http://127.0.0.1:8546").
    rpc_url: []const u8,

    /// Allocator used for the rpc_url string and internal buffers.
    allocator: std.mem.Allocator,

    /// The Io interface used for process management.
    io: std.Io,

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
        /// Anvil did not print "Listening on" within the timeout period.
        StartupTimeout,
        /// Anvil process exited unexpectedly before becoming ready.
        ProcessExitedEarly,
        /// Failed to spawn the Anvil process.
        SpawnFailed,
        /// Failed to read from Anvil's stderr pipe.
        StderrReadFailed,
    };

    /// Spawn an Anvil process on the given port and wait for it to be ready.
    ///
    /// The process is started with:
    ///   anvil --port <port> --chain-id 31337 --block-time 1
    ///
    /// This function blocks until Anvil prints "Listening on" to stderr,
    /// or returns an error if a 10-second timeout is exceeded.
    pub fn start(allocator: std.mem.Allocator, port: u16, io: std.Io) !AnvilProcess {
        var port_buf: [5]u8 = undefined;
        const port_str = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch unreachable;

        var child = std.process.spawn(io, .{
            .argv = &.{ "anvil", "--port", port_str, "--chain-id", "31337", "--block-time", "1" },
            .stderr = .pipe,
            .stdout = .ignore,
            .stdin = .ignore,
        }) catch {
            return AnvilError.SpawnFailed;
        };
        errdefer child.kill(io);

        // Read stderr until we see "Listening on" or timeout.
        const ready = waitForReady(&child, io);
        if (!ready) {
            return AnvilError.StartupTimeout;
        }

        // Build the RPC URL string.
        const rpc_url = std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{port}) catch {
            return error.OutOfMemory;
        };

        return AnvilProcess{
            .child = child,
            .rpc_url = rpc_url,
            .allocator = allocator,
            .io = io,
        };
    }

    /// Spawn Anvil on the default port (8546).
    pub fn startDefault(allocator: std.mem.Allocator, io: std.Io) !AnvilProcess {
        return start(allocator, DEFAULT_PORT, io);
    }

    /// Kill the Anvil process and free associated resources.
    ///
    /// After calling stop(), this AnvilProcess should not be used again.
    pub fn stop(self: *AnvilProcess) void {
        self.child.kill(self.io);
        self.allocator.free(self.rpc_url);
        self.* = undefined;
    }

    /// Poll Anvil's stderr for the "Listening on" readiness message.
    ///
    /// Returns true if the message was found, false if we timed out or
    /// the pipe closed without the expected output.
    fn waitForReady(child: *std.process.Child, io: std.Io) bool {
        const stderr_file = child.stderr orelse return false;

        // Use a simple polling loop reading from stderr.
        // Anvil prints its startup messages to stderr, ending with
        // "Listening on 127.0.0.1:<port>" when ready.
        var accumulated: [STDERR_BUF_SIZE]u8 = undefined;
        var total_read: usize = 0;
        var read_buf: [256]u8 = undefined;

        const deadline = std.time.nanoTimestamp() + @as(i128, STARTUP_TIMEOUT_NS);

        while (std.time.nanoTimestamp() < deadline) {
            const bytes_read = stderr_file.readStreaming(io, &.{&read_buf}) catch {
                // End of stream or error -- check what we have so far.
                break;
            };

            if (bytes_read == 0) {
                // No data yet, brief sleep before retrying.
                std.time.sleep(10 * std.time.ns_per_ms);
                continue;
            }

            // Append to accumulated buffer (best-effort, truncate if too long).
            const copy_len = @min(bytes_read, STDERR_BUF_SIZE - total_read);
            if (copy_len > 0) {
                @memcpy(accumulated[total_read..][0..copy_len], read_buf[0..copy_len]);
                total_read += copy_len;
            }

            // Check if the accumulated output contains the readiness marker.
            if (containsListening(accumulated[0..total_read])) {
                return true;
            }
        }

        // Final check in case we broke out of the loop.
        return containsListening(accumulated[0..total_read]);
    }

    /// Check whether a byte slice contains the substring "Listening on".
    fn containsListening(data: []const u8) bool {
        const needle = "Listening on";
        if (data.len < needle.len) return false;
        var i: usize = 0;
        while (i + needle.len <= data.len) : (i += 1) {
            if (std.mem.eql(u8, data[i..][0..needle.len], needle)) {
                return true;
            }
        }
        return false;
    }

    /// Parse a 40-character hex string into a 20-byte address at comptime.
    fn parseHexAddress(comptime hex: *const [40]u8) [20]u8 {
        return std.fmt.hexToBytes(20, hex) catch unreachable;
    }

    /// Parse a 64-character hex string into a 32-byte key at comptime.
    fn parseHexKey(comptime hex: *const [64]u8) [32]u8 {
        return std.fmt.hexToBytes(32, hex) catch unreachable;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "AnvilProcess constants are correct" {
    // Verify the well-known Anvil default account address.
    const expected_addr = [_]u8{
        0xf3, 0x9F, 0xd6, 0xe5, 0x1a, 0xad, 0x88, 0xF6, 0xF4, 0xce,
        0x6a, 0xB8, 0x82, 0x72, 0x79, 0xcf, 0xfF, 0xb9, 0x22, 0x66,
    };
    try std.testing.expectEqualSlices(u8, &expected_addr, &AnvilProcess.DEFAULT_ACCOUNT);

    // Verify chain ID.
    try std.testing.expectEqual(@as(u64, 31337), AnvilProcess.CHAIN_ID);

    // Verify default port.
    try std.testing.expectEqual(@as(u16, 8546), AnvilProcess.DEFAULT_PORT);
}

test "containsListening detects readiness marker" {
    try std.testing.expect(AnvilProcess.containsListening("Listening on 127.0.0.1:8546"));
    try std.testing.expect(AnvilProcess.containsListening("some prefix\nListening on 127.0.0.1:8546\n"));
    try std.testing.expect(!AnvilProcess.containsListening("Starting Anvil..."));
    try std.testing.expect(!AnvilProcess.containsListening("Listening o"));
    try std.testing.expect(!AnvilProcess.containsListening(""));
}
