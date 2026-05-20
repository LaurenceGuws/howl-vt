//! Deterministic M7 baseline smoke test.

const std = @import("std");
const action = @import("../action.zig");
const terminal_mod = @import("../terminal.zig");
const pty_feed_record = @import("pty_feed_record.zig");

const WorkloadResult = struct {
    name: []const u8,
    bytes_per_run: usize,
    runs: usize,
    median_ns: u64,
    p95_ns: u64,
    median_alloc_count: usize,
    median_alloc_bytes: usize,
    median_peak_live_bytes: usize,
    median_max_queue_depth: u32,

    fn throughputMibS(self: WorkloadResult) f64 {
        const median_seconds = @as(f64, @floatFromInt(self.median_ns)) / 1_000_000_000.0;
        if (median_seconds <= 0) return 0;
        return (@as(f64, @floatFromInt(self.bytes_per_run)) / median_seconds) / (1024.0 * 1024.0);
    }
};

const OutputFormat = enum { ndjson, text };

const Options = struct {
    runs: usize = 10,
    format: OutputFormat = .ndjson,
};

const RunObservation = struct {
    ns: u64,
    alloc_count: usize,
    alloc_bytes: usize,
    peak_live_bytes: usize,
    max_queue_depth: u32,
};

const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_count: usize = 0,
    alloc_bytes: usize = 0,
    live_bytes: usize = 0,
    peak_live_bytes: usize = 0,
    window_alloc_count: usize = 0,
    window_alloc_bytes: usize = 0,
    window_peak_live_bytes: usize = 0,
    window_live_baseline: usize = 0,

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn init(child: std.mem.Allocator) CountingAllocator {
        return .{ .child = child };
    }

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn resetWindow(self: *CountingAllocator) void {
        self.window_alloc_count = 0;
        self.window_alloc_bytes = 0;
        self.window_peak_live_bytes = 0;
        self.window_live_baseline = self.live_bytes;
    }

    fn updateWindowPeak(self: *CountingAllocator) void {
        if (self.live_bytes >= self.window_live_baseline) {
            const delta = self.live_bytes - self.window_live_baseline;
            if (delta > self.window_peak_live_bytes) self.window_peak_live_bytes = delta;
        }
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.alloc_count += 1;
        self.alloc_bytes += len;
        self.live_bytes += len;
        if (self.live_bytes > self.peak_live_bytes) self.peak_live_bytes = self.live_bytes;
        self.window_alloc_count += 1;
        self.window_alloc_bytes += len;
        self.updateWindowPeak();
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        if (new_len > memory.len) {
            const delta = new_len - memory.len;
            self.alloc_bytes += delta;
            self.window_alloc_bytes += delta;
            self.live_bytes += delta;
        } else {
            const delta = memory.len - new_len;
            self.live_bytes -|= delta;
        }
        self.updateWindowPeak();
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len > memory.len) {
            const delta = new_len - memory.len;
            self.alloc_bytes += delta;
            self.window_alloc_bytes += delta;
            self.live_bytes += delta;
        } else {
            const delta = memory.len - new_len;
            self.live_bytes -|= delta;
        }
        self.updateWindowPeak();
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
        self.live_bytes -|= memory.len;
        self.updateWindowPeak();
    }
};

fn lessThan(comptime T: type) fn (void, T, T) bool {
    return struct {
        fn compare(_: void, lhs: T, rhs: T) bool {
            return lhs < rhs;
        }
    }.compare;
}

fn median(comptime T: type, scratch: []T) T {
    std.sort.heap(T, scratch, {}, lessThan(T));
    return scratch[scratch.len / 2];
}

fn p95U64(scratch: []u64) u64 {
    std.sort.heap(u64, scratch, {}, lessThan(u64));
    const n = scratch.len;
    const idx = ((95 * n) + 99) / 100 - 1;
    return scratch[@min(idx, n - 1)];
}

fn nowNs(io: std.Io) u64 {
    return @intCast(std.Io.Clock.awake.now(io).toNanoseconds());
}

fn buildAsciiFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 700_000);
    defer out.deinit(allocator);
    const line = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, "\r\n");
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildCsiFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 120_000);
    defer out.deinit(allocator);
    const block = "\x1b[H\x1b[2J\x1b[31mHELLO\x1b[0m\x1b[5C\x1b[2K\x1b[1;1H";
    var i: usize = 0;
    while (i < 2_000) : (i += 1) {
        try out.appendSlice(allocator, block);
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildUnicodeFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 500_000);
    defer out.deinit(allocator);
    const line = "ASCII Привет 你好 Καλημέρα مرحبا 😀 λ─│┌┐└┘\r\n";
    var i: usize = 0;
    while (i < 10_000) : (i += 1) {
        try out.appendSlice(allocator, line);
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildScrollFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 80_000);
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < 20_000) : (i += 1) {
        try out.appendSlice(allocator, "X\r\n");
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn summarizeObservations(
    base_allocator: std.mem.Allocator,
    name: []const u8,
    bytes_per_run: usize,
    observations: []const RunObservation,
) !WorkloadResult {
    const runs = observations.len;
    const ns_values = try base_allocator.alloc(u64, runs);
    defer base_allocator.free(ns_values);
    const alloc_count_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_count_values);
    const alloc_bytes_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(alloc_bytes_values);
    const peak_live_values = try base_allocator.alloc(usize, runs);
    defer base_allocator.free(peak_live_values);
    const queue_depth_values = try base_allocator.alloc(u32, runs);
    defer base_allocator.free(queue_depth_values);

    for (observations, 0..) |obs, idx| {
        ns_values[idx] = obs.ns;
        alloc_count_values[idx] = obs.alloc_count;
        alloc_bytes_values[idx] = obs.alloc_bytes;
        peak_live_values[idx] = obs.peak_live_bytes;
        queue_depth_values[idx] = obs.max_queue_depth;
    }

    return .{
        .name = name,
        .bytes_per_run = bytes_per_run,
        .runs = runs,
        .median_ns = median(u64, ns_values),
        .p95_ns = p95U64(ns_values),
        .median_alloc_count = median(usize, alloc_count_values),
        .median_alloc_bytes = median(usize, alloc_bytes_values),
        .median_peak_live_bytes = median(usize, peak_live_values),
        .median_max_queue_depth = median(u32, queue_depth_values),
    };
}

fn runFeedApplyWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    name: []const u8,
    fixture: []const u8,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: usize,
) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);
    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithCellsAndHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer terminal.deinit();
        counting.resetWindow();
        const start = nowNs(io);
        try terminal.parser.feedSlice(fixture);
        const max_queue_depth = action.applyLimit(&terminal, 0).remaining_events;
        action.apply(&terminal);
        const end = nowNs(io);
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }
    return try summarizeObservations(base_allocator, name, fixture.len, observations);
}

fn runMixedInteractiveWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    runs: usize,
) !WorkloadResult {
    const bursts_per_run: usize = 5_000;
    const burst = "abc\x1b[D\x1b[C\r";
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);

    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithCellsAndHistory(
            counting.allocator(),
            40,
            120,
            1_000,
        );
        defer terminal.deinit();
        counting.resetWindow();
        const start = nowNs(io);
        var j: usize = 0;
        var max_queue_depth: u32 = 0;
        while (j < bursts_per_run) : (j += 1) {
            try terminal.parser.feedSlice(burst);
            max_queue_depth = @max(max_queue_depth, action.applyLimit(&terminal, 0).remaining_events);
            action.apply(&terminal);
        }
        const end = nowNs(io);
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }
    return try summarizeObservations(base_allocator, "mixed_interactive", bursts_per_run * burst.len, observations);
}

fn runSnapshotWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    fixture: []const u8,
    runs: usize,
) !WorkloadResult {
    const snapshot_calls_per_run: usize = 200;
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);

    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithCellsAndHistory(
            counting.allocator(),
            40,
            120,
            1_000,
        );
        defer terminal.deinit();
        try terminal.parser.feedSlice(fixture);
        action.apply(&terminal);
        counting.resetWindow();
        const start = nowNs(io);
        var j: usize = 0;
        while (j < snapshot_calls_per_run) : (j += 1) {
            var snap = try @import("screen_capture.zig").Capture.captureFromScreen(
                terminal.allocator,
                terminal.screen_state.activeConst(),
                terminal.screen_state.activeSelectionConst().state(),
            );
            snap.deinit();
        }
        const end = nowNs(io);
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = 0,
        };
    }
    return try summarizeObservations(base_allocator, "snapshot_opt_in", snapshot_calls_per_run, observations);
}

fn runQueueGrowthChunkedWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    name: []const u8,
    fixture: []const u8,
    chunk_size: usize,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: usize,
) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, runs);
    defer base_allocator.free(observations);

    var i: usize = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithCellsAndHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer terminal.deinit();

        counting.resetWindow();
        var offset: usize = 0;
        var max_queue_depth: u32 = 0;
        const start = nowNs(io);
        while (offset < fixture.len) {
            const next = @min(offset + chunk_size, fixture.len);
            try terminal.parser.feedSlice(fixture[offset..next]);
            max_queue_depth = @max(max_queue_depth, action.applyLimit(&terminal, 0).remaining_events);
            offset = next;
        }
        action.apply(&terminal);
        const end = nowNs(io);
        observations[i] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }
    return try summarizeObservations(base_allocator, name, fixture.len, observations);
}

fn runReplayRecordWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    name: []const u8,
    record: *const pty_feed_record.Record,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: u32,
) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, @intCast(runs));
    defer base_allocator.free(observations);

    for (observations) |*obs| {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithCellsAndHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer terminal.deinit();

        counting.resetWindow();
        var max_queue_depth: u32 = 0;
        const start = nowNs(io);
        for (record.chunks.items) |chunk| {
            try terminal.parser.feedSlice(chunk);
            max_queue_depth = @max(max_queue_depth, action.applyLimit(&terminal, 0).remaining_events);
        }
        action.apply(&terminal);
        const end = nowNs(io);
        obs.* = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
            .max_queue_depth = max_queue_depth,
        };
    }
    return try summarizeObservations(base_allocator, name, @intCast(pty_feed_record.byteLen(record)), observations);
}

fn loadReplayRecordIfPresent(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !?pty_feed_record.Record {
    return pty_feed_record.load(io, allocator, path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => |e| return e,
    };
}

fn printTextResult(result: WorkloadResult) void {
    const median_ms = @as(f64, @floatFromInt(result.median_ns)) / 1_000_000.0;
    const p95_ms = @as(f64, @floatFromInt(result.p95_ns)) / 1_000_000.0;

    std.debug.print("workload={s}\n", .{result.name});
    std.debug.print("runs={d}\n", .{result.runs});
    std.debug.print("bytes_per_run={d}\n", .{result.bytes_per_run});
    std.debug.print("median_ms={d:.3}\n", .{median_ms});
    std.debug.print("p95_ms={d:.3}\n", .{p95_ms});
    std.debug.print("throughput_mib_s={d:.2}\n", .{result.throughputMibS()});
    std.debug.print("median_alloc_count={d}\n", .{result.median_alloc_count});
    std.debug.print("median_alloc_bytes={d}\n", .{result.median_alloc_bytes});
    std.debug.print("median_peak_live_bytes={d}\n", .{result.median_peak_live_bytes});
    std.debug.print("median_max_queue_depth={d}\n", .{result.median_max_queue_depth});
    std.debug.print("---\n", .{});
}

fn printNdjsonResult(result: WorkloadResult) void {
    std.debug.print(
        "{{\"type\":\"vt_core_benchmark\",\"schema\":2,\"workload\":\"{s}\",\"runs\":{d},\"bytes_per_run\":{d},\"median_ns\":{d},\"p95_ns\":{d},\"throughput_mib_s\":{d:.3},\"median_alloc_count\":{d},\"median_alloc_bytes\":{d},\"median_peak_live_bytes\":{d},\"median_max_queue_depth\":{d}}}\n",
        .{
            result.name,
            result.runs,
            result.bytes_per_run,
            result.median_ns,
            result.p95_ns,
            result.throughputMibS(),
            result.median_alloc_count,
            result.median_alloc_bytes,
            result.median_peak_live_bytes,
            result.median_max_queue_depth,
        },
    );
}

fn printResult(result: WorkloadResult, format: OutputFormat) void {
    switch (format) {
        .ndjson => printNdjsonResult(result),
        .text => printTextResult(result),
    }
}

fn usage() void {
    std.debug.print(
        \\usage: vt_core_benchmark [--runs N] [--text]
        \\
        \\Default output is NDJSON, one event per workload.
        \\
    , .{});
}

fn parseOptions(args_vector: std.process.Args.Vector) !Options {
    var args = std.process.Args.Iterator.init(.{ .vector = args_vector });
    _ = args.next();
    var options = Options{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            usage();
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--text")) {
            options.format = .text;
        } else if (std.mem.eql(u8, arg, "--runs")) {
            const value = args.next() orelse return error.InvalidArgs;
            options.runs = @max(try std.fmt.parseInt(usize, value, 10), 1);
        } else {
            usage();
            return error.InvalidArgs;
        }
    }
    return options;
}

/// Benchmark entrypoint.
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    const options = parseOptions(init.minimal.args.vector) catch |err| switch (err) {
        error.HelpRequested => return,
        else => return err,
    };
    const runs = options.runs;

    const ascii_fixture = try buildAsciiFixture(allocator);
    defer allocator.free(ascii_fixture);
    const unicode_fixture = try buildUnicodeFixture(allocator);
    defer allocator.free(unicode_fixture);
    const csi_fixture = try buildCsiFixture(allocator);
    defer allocator.free(csi_fixture);
    const scroll_fixture = try buildScrollFixture(allocator);
    defer allocator.free(scroll_fixture);

    const ascii_result = try runFeedApplyWorkload(
        init.io,
        allocator,
        "ascii_heavy",
        ascii_fixture,
        40,
        120,
        0,
        runs,
    );
    const csi_result = try runFeedApplyWorkload(
        init.io,
        allocator,
        "csi_heavy",
        csi_fixture,
        40,
        120,
        0,
        runs,
    );
    const unicode_result = try runFeedApplyWorkload(
        init.io,
        allocator,
        "unicode_heavy",
        unicode_fixture,
        40,
        120,
        0,
        runs,
    );
    const scroll_no_history = try runFeedApplyWorkload(
        init.io,
        allocator,
        "scroll_heavy_history0",
        scroll_fixture,
        40,
        120,
        0,
        runs,
    );
    const scroll_with_history = try runFeedApplyWorkload(
        init.io,
        allocator,
        "scroll_heavy_history1000",
        scroll_fixture,
        40,
        120,
        1_000,
        runs,
    );
    const scroll_with_default_history = try runFeedApplyWorkload(
        init.io,
        allocator,
        "scroll_heavy_history4096",
        scroll_fixture,
        40,
        120,
        4_096,
        runs,
    );
    const mixed_result = try runMixedInteractiveWorkload(init.io, allocator, runs);
    const snapshot_result = try runSnapshotWorkload(init.io, allocator, scroll_fixture, runs);
    const queue_growth_ascii = try runQueueGrowthChunkedWorkload(
        init.io,
        allocator,
        "queue_growth_ascii_chunked_64",
        ascii_fixture,
        64,
        40,
        120,
        0,
        runs,
    );
    const queue_growth_scroll = try runQueueGrowthChunkedWorkload(
        init.io,
        allocator,
        "queue_growth_scroll_chunked_16",
        scroll_fixture,
        16,
        40,
        120,
        1_000,
        runs,
    );

    var replay_lsd_never = try loadReplayRecordIfPresent(init.io, allocator, "../howl-linux-host/artifacts/replay/lsd-never.hex");
    defer if (replay_lsd_never) |*record| record.deinit();
    const replay_lsd_never_result = if (replay_lsd_never) |*record|
        try runReplayRecordWorkload(init.io, allocator, "replay_lsd_never", record, 40, 120, 1_000, @intCast(runs))
    else
        null;

    var replay_lsd_always = try loadReplayRecordIfPresent(init.io, allocator, "../howl-linux-host/artifacts/replay/lsd-always.hex");
    defer if (replay_lsd_always) |*record| record.deinit();
    const replay_lsd_always_result = if (replay_lsd_always) |*record|
        try runReplayRecordWorkload(init.io, allocator, "replay_lsd_always", record, 40, 120, 1_000, @intCast(runs))
    else
        null;

    if (options.format == .text) {
        std.debug.print("vt_core_benchmark_v2\n", .{});
        std.debug.print("rows=40 cols=120 runs={d}\n", .{runs});
        std.debug.print("---\n", .{});
    }
    printResult(ascii_result, options.format);
    printResult(unicode_result, options.format);
    printResult(csi_result, options.format);
    printResult(scroll_no_history, options.format);
    printResult(scroll_with_history, options.format);
    printResult(scroll_with_default_history, options.format);
    printResult(mixed_result, options.format);
    printResult(snapshot_result, options.format);
    printResult(queue_growth_ascii, options.format);
    printResult(queue_growth_scroll, options.format);
    if (replay_lsd_never_result) |result| printResult(result, options.format);
    if (replay_lsd_always_result) |result| printResult(result, options.format);
}
