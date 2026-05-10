//! Responsibility: reusable scrollback fuzz scenarios and replay helpers.
//! Ownership: vt-core deterministic fuzz infrastructure.
//! Reason: keep unit regressions and fuzz executables on one shared scrollback model.

const std = @import("std");
const vt_mod = @import("vt_core");

pub const RowsMin: u16 = 1;
pub const ColsMin: u16 = 1;
pub const RowsMax: u16 = 80;
pub const ColsMax: u16 = 220;

const OpKind = enum {
    write_burst,
    resize,
    zoom_jitter,
};

pub const RunSummary = struct {
    structural_hash: u64,
    logical_hash: u64,
    history_count: usize,
    rows: u16,
    cols: u16,
};

pub const ChurnStep = union(enum) {
    resize: struct { rows: u16, cols: u16 },
    zoom_jitter: struct {
        start_rows: u16,
        start_cols: u16,
        end_rows: u16,
        end_cols: u16,
        steps: u8,
    },
};

pub const CoreStateSummary = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    wrap_pending: bool,
    history_count: usize,
    history_capacity: u16,
};

pub const PreservationOptions = struct {
    initial_rows: u16 = 24,
    initial_cols: u16 = 80,
    history_capacity: u16 = 4096,
    warmup_bursts: usize = 320,
    churn_ops: usize = 400,
};

pub const InvariantError = error{
    RowBelowMinimum,
    ColBelowMinimum,
    CursorRowOutOfBounds,
    CursorColOutOfBounds,
};

pub fn runScenario(allocator: std.mem.Allocator, seed: u64, op_count: usize) !RunSummary {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var vt = try vt_mod.VtCore.initWithCellsAndHistory(allocator, 24, 80, 4096);
    defer vt.deinit();

    var i: usize = 0;
    while (i < op_count) : (i += 1) {
        const op = pickOp(rand);
        switch (op) {
            .write_burst => try applyWriteBurst(&vt, rand),
            .resize => try applyResize(&vt, rand),
            .zoom_jitter => try applyZoomJitter(&vt, rand),
        }
        try ensureCoreInvariants(&vt);
    }

    return .{
        .structural_hash = hashStructural(&vt),
        .logical_hash = hashLogicalContent(&vt),
        .history_count = vt.historyCount(),
        .rows = vt.screen().rows,
        .cols = vt.screen().cols,
    };
}

pub fn runCanonicalPreservation(
    allocator: std.mem.Allocator,
    seed: u64,
    options: PreservationOptions,
) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var vt = try vt_mod.VtCore.initWithCellsAndHistory(
        allocator,
        options.initial_rows,
        options.initial_cols,
        options.history_capacity,
    );
    defer vt.deinit();

    var line_idx: usize = 0;
    while (line_idx < options.warmup_bursts) : (line_idx += 1) {
        try applyWriteBurst(&vt, rand);
    }

    const before = try canonicalLogicalHash(allocator, &vt);

    var churn_idx: usize = 0;
    while (churn_idx < options.churn_ops) : (churn_idx += 1) {
        const pre_state = summarizeCoreState(&vt);
        const step = if (rand.boolean())
            try applyResizeStep(&vt, rand)
        else
            try applyZoomJitterStep(&vt, rand);
        const actual = try canonicalLogicalHash(allocator, &vt);
        if (actual != before) {
            logBreakpoint(churn_idx, pre_state, step, before, actual, summarizeCoreState(&vt));
            return error.CanonicalContentMismatch;
        }

        try ensureCoreInvariants(&vt);
    }

    const restore_pre_state = summarizeCoreState(&vt);
    try vt.resize(options.initial_rows, options.initial_cols);
    const restore_step: ChurnStep = .{ .resize = .{
        .rows = options.initial_rows,
        .cols = options.initial_cols,
    } };
    try ensureCoreInvariants(&vt);

    const after = try canonicalLogicalHash(allocator, &vt);
    if (after != before) {
        logBreakpoint(options.churn_ops, restore_pre_state, restore_step, before, after, summarizeCoreState(&vt));
        return error.CanonicalContentMismatch;
    }
}

pub fn parseSeed(bytes: []const u8) !u64 {
    if (bytes.len == 40) {
        const commit_hash = std.fmt.parseUnsigned(u160, bytes, 16) catch |err| switch (err) {
            error.Overflow => unreachable,
            error.InvalidCharacter => return error.InvalidSeed,
        };
        return @truncate(commit_hash);
    }

    return std.fmt.parseUnsigned(u64, bytes, 10) catch return error.InvalidSeed;
}

pub fn defaultPreservationOptions(events_max: ?usize) PreservationOptions {
    var options: PreservationOptions = .{};
    options.churn_ops = events_max orelse options.churn_ops;
    return options;
}

fn pickOp(rand: std.Random) OpKind {
    const roll = rand.uintLessThan(u8, 100);
    if (roll < 45) return .write_burst;
    if (roll < 80) return .resize;
    return .zoom_jitter;
}

fn applyWriteBurst(vt: *vt_mod.VtCore, rand: std.Random) !void {
    const lines = rand.uintLessThan(u8, 8) + 1;
    var line_idx: u8 = 0;
    while (line_idx < lines) : (line_idx += 1) {
        var buf: [96]u8 = undefined;
        const len = rand.uintLessThan(u8, 90) + 1;
        var i: usize = 0;
        while (i < len) : (i += 1) {
            const cp = "0123456789abcdefXYZ+-_=./[]{}()";
            buf[i] = cp[rand.uintLessThan(usize, cp.len)];
        }
        vt.feedSlice(buf[0..len]);
        vt.feedByte('\n');
    }
    vt.apply();
}

fn applyResize(vt: *vt_mod.VtCore, rand: std.Random) !void {
    const rows = RowsMin + rand.uintLessThan(u16, RowsMax - RowsMin + 1);
    const cols = ColsMin + rand.uintLessThan(u16, ColsMax - ColsMin + 1);
    try vt.resize(rows, cols);
}

fn applyResizeStep(vt: *vt_mod.VtCore, rand: std.Random) !ChurnStep {
    const rows = RowsMin + rand.uintLessThan(u16, RowsMax - RowsMin + 1);
    const cols = ColsMin + rand.uintLessThan(u16, ColsMax - ColsMin + 1);
    try vt.resize(rows, cols);
    return .{ .resize = .{ .rows = rows, .cols = cols } };
}

fn applyZoomJitter(vt: *vt_mod.VtCore, rand: std.Random) !void {
    const cur_rows = vt.screen().rows;
    const cur_cols = vt.screen().cols;
    const steps = rand.uintLessThan(u8, 5) + 2;
    var i: u8 = 0;
    while (i < steps) : (i += 1) {
        const delta_rows: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 7))) - 3;
        const delta_cols: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 19))) - 9;
        const next_rows = clampDimI16(cur_rows, delta_rows, RowsMin, RowsMax);
        const next_cols = clampDimI16(cur_cols, delta_cols, ColsMin, ColsMax);
        try vt.resize(next_rows, next_cols);
    }
    try vt.resize(cur_rows, cur_cols);
}

fn applyZoomJitterStep(vt: *vt_mod.VtCore, rand: std.Random) !ChurnStep {
    const cur_rows = vt.screen().rows;
    const cur_cols = vt.screen().cols;
    const steps = rand.uintLessThan(u8, 5) + 2;
    var end_rows = cur_rows;
    var end_cols = cur_cols;
    var i: u8 = 0;
    while (i < steps) : (i += 1) {
        const delta_rows: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 7))) - 3;
        const delta_cols: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 19))) - 9;
        end_rows = clampDimI16(cur_rows, delta_rows, RowsMin, RowsMax);
        end_cols = clampDimI16(cur_cols, delta_cols, ColsMin, ColsMax);
        try vt.resize(end_rows, end_cols);
    }
    try vt.resize(cur_rows, cur_cols);
    return .{ .zoom_jitter = .{
        .start_rows = cur_rows,
        .start_cols = cur_cols,
        .end_rows = end_rows,
        .end_cols = end_cols,
        .steps = steps,
    } };
}

fn clampDimI16(base: u16, delta: i16, min_v: u16, max_v: u16) u16 {
    const signed = @as(i32, @intCast(base)) + @as(i32, delta);
    const clamped = std.math.clamp(signed, @as(i32, @intCast(min_v)), @as(i32, @intCast(max_v)));
    return @intCast(clamped);
}

fn ensureCoreInvariants(vt: *const vt_mod.VtCore) InvariantError!void {
    const s = vt.screen();
    if (s.rows < RowsMin) return error.RowBelowMinimum;
    if (s.cols < ColsMin) return error.ColBelowMinimum;
    if (s.cursor_row >= s.rows) return error.CursorRowOutOfBounds;
    if (s.cursor_col >= s.cols) return error.CursorColOutOfBounds;
}

fn hashStructural(vt: *const vt_mod.VtCore) u64 {
    var h = std.hash.Wyhash.init(0);
    const s = vt.screen();
    h.update(std.mem.asBytes(&s.rows));
    h.update(std.mem.asBytes(&s.cols));
    h.update(std.mem.asBytes(&s.cursor_row));
    h.update(std.mem.asBytes(&s.cursor_col));
    h.update(std.mem.asBytes(&s.wrap_pending));
    const history_count = vt.historyCount();
    const history_capacity = vt.historyCapacity();
    h.update(std.mem.asBytes(&history_count));
    h.update(std.mem.asBytes(&history_capacity));
    return h.final();
}

fn hashLogicalContent(vt: *const vt_mod.VtCore) u64 {
    var h = std.hash.Wyhash.init(0x9e3779b97f4a7c15);
    const s = vt.screen();
    const history = vt.historyCount();

    var hr: usize = 0;
    while (hr < history) : (hr += 1) {
        var col: u16 = 0;
        while (col < s.cols) : (col += 1) {
            const cp = vt.historyRowAt(hr, col);
            h.update(std.mem.asBytes(&cp));
        }
    }

    var row: u16 = 0;
    while (row < s.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < s.cols) : (col += 1) {
            const cp = s.cellAt(row, col);
            h.update(std.mem.asBytes(&cp));
        }
    }

    return h.final();
}

fn canonicalLogicalHash(allocator: std.mem.Allocator, vt: *const vt_mod.VtCore) !u64 {
    const lines = try canonicalLogicalStream(allocator, vt);
    defer allocator.free(lines);

    var h = std.hash.Wyhash.init(0xd1b54a32d192ed03);
    h.update(std.mem.sliceAsBytes(lines));
    return h.final();
}

fn canonicalLogicalStream(allocator: std.mem.Allocator, vt: *const vt_mod.VtCore) ![]u21 {
    const s = vt.screen();
    var lines: std.ArrayList(u21) = .empty;
    defer lines.deinit(allocator);

    var row_buf: std.ArrayList(u21) = .empty;
    defer row_buf.deinit(allocator);

    var history_idx = vt.historyCount();
    while (history_idx > 0) {
        history_idx -= 1;
        try appendHistoryRowCanonical(allocator, &lines, &row_buf, vt, history_idx, s.cols);
    }

    var row: u16 = 0;
    while (row < s.rows) : (row += 1) {
        try appendVisibleRowCanonical(allocator, &lines, &row_buf, s, row, s.cols);
    }

    if (row_buf.items.len > 0 or lines.items.len == 0) {
        try flushLogicalRow(allocator, &lines, &row_buf);
    }

    return try lines.toOwnedSlice(allocator);
}

fn appendHistoryRowCanonical(
    allocator: std.mem.Allocator,
    all_lines: *std.ArrayList(u21),
    current_line: *std.ArrayList(u21),
    vt: *const vt_mod.VtCore,
    recency: usize,
    cols: u16,
) !void {
    const s = vt.screen();
    const len = historyContentLen(s, vt, recency, cols);
    var col: u16 = 0;
    while (col < len) : (col += 1) {
        try current_line.append(allocator, vt.historyRowAt(recency, col));
    }
    if (!historyRowWrapped(s, recency)) {
        try flushLogicalRow(allocator, all_lines, current_line);
    }
}

fn appendVisibleRowCanonical(
    allocator: std.mem.Allocator,
    all_lines: *std.ArrayList(u21),
    current_line: *std.ArrayList(u21),
    s: anytype,
    row: u16,
    cols: u16,
) !void {
    const len = visibleContentLen(s, row, cols);
    var col: u16 = 0;
    while (col < len) : (col += 1) {
        try current_line.append(allocator, s.cellAt(row, col));
    }
    if (!visibleRowWrapped(s, row)) {
        try flushLogicalRow(allocator, all_lines, current_line);
    }
}

fn flushLogicalRow(allocator: std.mem.Allocator, all_lines: *std.ArrayList(u21), current_line: *std.ArrayList(u21)) !void {
    try all_lines.append(allocator, 0);
    try all_lines.appendSlice(allocator, current_line.items);
    current_line.clearRetainingCapacity();
}

fn historyContentLen(s: anytype, vt: *const vt_mod.VtCore, recency: usize, cols: u16) u16 {
    var col = cols;
    while (col > 0) {
        const idx = col - 1;
        if (vt.historyRowAt(recency, idx) != 0) return col;
        col -= 1;
    }
    if (historyRowWrapped(s, recency) and cols > 0) return cols;
    return 0;
}

fn visibleContentLen(s: anytype, row: u16, cols: u16) u16 {
    var col = cols;
    while (col > 0) {
        const idx = col - 1;
        if (s.cellAt(row, idx) != 0) return col;
        col -= 1;
    }
    if (visibleRowWrapped(s, row) and cols > 0) return cols;
    return 0;
}

fn visibleRowWrapped(s: anytype, row: u16) bool {
    const wraps = s.row_wraps orelse return false;
    if (s.rows == 0 or row >= s.rows) return false;
    const idx = (@as(usize, s.row_origin) + @as(usize, row)) % @as(usize, s.rows);
    return wraps[idx];
}

fn historyRowWrapped(s: anytype, recency: usize) bool {
    const wraps = s.history_wraps orelse return false;
    if (recency >= s.history_count) return false;
    const slot = s.history_count - 1 - recency;
    return wraps[slot];
}

fn summarizeCoreState(vt: *const vt_mod.VtCore) CoreStateSummary {
    const s = vt.screen();
    return .{
        .rows = s.rows,
        .cols = s.cols,
        .cursor_row = s.cursor_row,
        .cursor_col = s.cursor_col,
        .wrap_pending = s.wrap_pending,
        .history_count = vt.historyCount(),
        .history_capacity = vt.historyCapacity(),
    };
}

fn logBreakpoint(index: usize, before: CoreStateSummary, step: ChurnStep, expected: u64, actual: u64, after: CoreStateSummary) void {
    std.debug.print(
        "scrollback fuzz breakpoint at step {d}\nstate before: rows={d} cols={d} cursor=({d},{d}) wrap_pending={} history={d}/{d}\n",
        .{
            index,
            before.rows,
            before.cols,
            before.cursor_row,
            before.cursor_col,
            before.wrap_pending,
            before.history_count,
            before.history_capacity,
        },
    );
    switch (step) {
        .resize => |v| std.debug.print("step: resize rows={d} cols={d}\n", .{ v.rows, v.cols }),
        .zoom_jitter => |v| std.debug.print(
            "step: zoom_jitter start={d}x{d} last_jitter={d}x{d} steps={d} restored_to_start\n",
            .{ v.start_rows, v.start_cols, v.end_rows, v.end_cols, v.steps },
        ),
    }
    std.debug.print("expected output hash: {d}\nactual output hash: {d}\n", .{ expected, actual });
    std.debug.print(
        "state after: rows={d} cols={d} cursor=({d},{d}) wrap_pending={} history={d}/{d}\n",
        .{
            after.rows,
            after.cols,
            after.cursor_row,
            after.cursor_col,
            after.wrap_pending,
            after.history_count,
            after.history_capacity,
        },
    );
}
