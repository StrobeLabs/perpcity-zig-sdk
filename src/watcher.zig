//! Real-time event watching for a Perp market. `PerpEventWatcher` subscribes to
//! new block headers over a WebSocket and, reorg-safely, fetches + decodes the
//! market's logs block-by-block - the push-based counterpart to the pull-based
//! `context.pollEvents`. This is what lets a bot react to a threshold crossing
//! (funding accrual, an index move, a margin change) the instant the block
//! lands, instead of on a poll interval.
//!
//! Establishing the watcher opens a live WebSocket + HTTP connection, so it is
//! exercised by integration tests, not CI. The reorg-safe range planner
//! (`planRange`) is re-exported for callers building custom pull loops over the
//! `ChainClient` seam.

const std = @import("std");
const eth = @import("eth");
const types = @import("types.zig");
const event_decode = @import("event_decode.zig");

/// Options controlling the watcher's start lag and reorg handling.
pub const WatchOpts = eth.log_watcher.WatchOpts;
/// A processed-block cursor (number + hash) for reorg detection.
pub const Cursor = eth.log_watcher.Cursor;
/// The planned block range for a new head.
pub const RangePlan = eth.log_watcher.RangePlan;

/// Plan the reorg-safe block range to fetch for a new head given the last
/// processed cursor. Pure and re-exported from eth.zig so a caller can build a
/// reorg-safe pull loop over the `ChainClient` seam's `getLogs` without a
/// WebSocket. Returns null when there is nothing to fetch (duplicate head, or
/// reorg handling disabled).
pub const planRange = eth.log_watcher.planRange;

/// A live watcher for a single Perp market. Owns its transport, provider,
/// WebSocket client, and the underlying reorg-safe log watcher.
pub const PerpEventWatcher = struct {
    allocator: std.mem.Allocator,
    transport: *eth.http_transport.HttpTransport,
    provider: *eth.provider.Provider,
    ws: *eth.ws_client.WsClient,
    watcher: *eth.log_watcher.LogWatcher,
    /// Owns the filter's address hex string; the watcher's filter borrows it, so
    /// it must live in this heap-stable struct.
    address_hex: [42]u8,

    /// Connect to `ws_url` (for `newHeads`) and `rpc_url` (for `getLogs`) and
    /// begin watching `perp`'s events. Opens live connections. Free with
    /// `deinit`.
    pub fn connect(
        allocator: std.mem.Allocator,
        ws_url: []const u8,
        rpc_url: []const u8,
        perp: types.Address,
        opts: WatchOpts,
    ) !*PerpEventWatcher {
        const self = try allocator.create(PerpEventWatcher);
        errdefer allocator.destroy(self);
        self.allocator = allocator;
        self.address_hex = eth.primitives.addressToHex(&perp);

        const transport = try allocator.create(eth.http_transport.HttpTransport);
        errdefer allocator.destroy(transport);
        transport.* = eth.http_transport.HttpTransport.init(allocator, rpc_url, eth.runtime.blockingIo());
        errdefer transport.deinit();

        const provider = try allocator.create(eth.provider.Provider);
        errdefer allocator.destroy(provider);
        provider.* = eth.provider.Provider.init(allocator, transport);

        const ws = try eth.ws_client.WsClient.connect(allocator, ws_url, eth.runtime.blockingIo(), .{});
        errdefer ws.deinit();

        const watcher = try allocator.create(eth.log_watcher.LogWatcher);
        errdefer allocator.destroy(watcher);
        const filter = eth.json_rpc.LogFilter{ .address = &self.address_hex };
        watcher.* = try eth.log_watcher.LogWatcher.init(allocator, provider, ws, filter, opts);
        errdefer watcher.deinit();

        self.transport = transport;
        self.provider = provider;
        self.ws = ws;
        self.watcher = watcher;
        return self;
    }

    pub fn deinit(self: *PerpEventWatcher) void {
        self.watcher.deinit();
        self.allocator.destroy(self.watcher);
        self.ws.deinit();
        self.transport.deinit();
        self.allocator.destroy(self.provider);
        self.allocator.destroy(self.transport);
        self.allocator.destroy(self);
    }

    /// Block until the next block header, then fetch + decode this market's logs
    /// for the reorg-safe range. May return an empty slice. Logs can be
    /// re-delivered across reorgs, so dedupe on `(block_hash, log_index)`.
    /// Caller frees the returned slice with `allocator.free`.
    pub fn pollNext(self: *PerpEventWatcher, allocator: std.mem.Allocator) ![]event_decode.DecodedEvent {
        const logs = try self.watcher.pollOnce();
        defer eth.log_watcher.freeLogs(self.allocator, logs);
        return event_decode.decodeLogs(allocator, logs);
    }
};
