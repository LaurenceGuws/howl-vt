//! Public Terminal API and lifecycle tests.

const std = @import("std");
const action_mod = @import("../action.zig");
const terminal_mod = @import("../terminal.zig");
const ffi = @import("../ffi.zig");
const parsed_events_mod = @import("../parser/events.zig");
const screen = @import("../screen.zig");
const screen_capture = @import("screen_capture.zig");
const screen_set = @import("../screen_set.zig");
const selection = @import("../selection.zig");
const input_mod = @import("../input.zig");

const Terminal = terminal_mod.Terminal;
const Action = action_mod;
const ParsedEvents = parsed_events_mod.ParsedEvents;
const Screen = screen.Screen;
const Selection = selection;
const Input = input_mod;

var encode_scratch: Input.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: Input.Key, mod: Input.Modifier) []const u8 {
    return Input.encodeKey(terminal, &encode_scratch, key, mod);
}

fn activeScreen(terminal: *const Terminal) *const Screen {
    return terminal.screen_state.activeConst();
}

fn visibleView(terminal: *const Terminal, options: screen_set.Options) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, options);
}

fn historyCapacity(terminal: *const Terminal) u16 {
    return screen_set.historyCapacity(&terminal.screen_state);
}

fn clearDirtyRows(terminal: *Terminal) void {
    screen_set.clearDirtyRows(&terminal.screen_state);
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

fn resizeTerminal(terminal: *Terminal, rows: u16, cols: u16) !void {
    try terminal.screen_state.resize(terminal.allocator, rows, cols);
    terminal.screen_state.activeSelection().clearIfInvalidatedByGrid(terminal.screen_state.activeConst());
}

fn selectionState(terminal: *const Terminal) ?Selection.TerminalSelection {
    return Selection.terminalState(terminal);
}

fn selectionStart(terminal: *Terminal, row: i32, col: u16) void {
    Selection.terminalStart(terminal, row, col);
}

fn selectionUpdate(terminal: *Terminal, row: i32, col: u16) void {
    Selection.terminalUpdate(terminal, row, col);
}

fn selectionFinish(terminal: *Terminal) void {
    Selection.terminalFinish(terminal);
}

fn selectionClear(terminal: *Terminal) void {
    Selection.terminalClear(terminal);
}

fn feedByte(terminal: *Terminal, byte: u8) void {
    terminal.parser_queue.feedByteChecked(byte) catch unreachable;
}

fn feedSlice(terminal: *Terminal, bytes: []const u8) void {
    terminal.parser_queue.feedSliceChecked(bytes) catch unreachable;
}

fn apply(terminal: *Terminal) void {
    Action.apply(terminal);
}

fn clear(terminal: *Terminal) void {
    terminal.parser_queue.clear();
}

fn reset(terminal: *Terminal) void {
    terminal.parser_queue.reset();
}

fn applyLimit(terminal: *Terminal, max_events: u32) Action.ApplySummary {
    return Action.applyLimit(terminal, max_events);
}

fn copySurfaceOk(
    handle: ffi.VtHandle,
    rows: u16,
    cols: u16,
    cells: []ffi.FfiSurfaceCell,
    dirty_rows: []u8,
    cols_start: []u16,
    cols_end: []u16,
) !ffi.FfiSurfaceResult {
    const result = ffi.terminalCopySurface(
        handle,
        0,
        cells.ptr,
        cells.len,
        dirty_rows.ptr,
        dirty_rows.len,
        cols_start.ptr,
        cols_start.len,
        cols_end.ptr,
        cols_end.len,
        0,
        0,
    );
    try std.testing.expectEqual(@intFromEnum(ffi.HowlVtCallStatus.ok), result.status);
    try std.testing.expectEqual(rows, result.source.rows);
    try std.testing.expectEqual(cols, result.source.cols);
    return result;
}

test "Terminal public methods remain available" {
    try std.testing.expect(@hasDecl(Terminal, "init"));
    try std.testing.expect(@hasDecl(Terminal, "initWithCells"));
    try std.testing.expect(@hasDecl(Terminal, "deinit"));
    _ = .{ feedByte, feedSlice, apply, clear, reset, applyLimit };
}

test "Terminal method signatures remain host-facing" {
    const Allocator = std.mem.Allocator;
    const init_fn: fn (Allocator, u16, u16) anyerror!Terminal = Terminal.init;
    const init_cells_fn: fn (Allocator, u16, u16) anyerror!Terminal = Terminal.initWithCells;
    const deinit_fn: fn (*Terminal) void = Terminal.deinit;
    const feed_byte_fn: fn (*Terminal, u8) void = feedByte;
    const feed_slice_fn: fn (*Terminal, []const u8) void = feedSlice;
    const apply_fn: fn (*Terminal) void = apply;
    const clear_fn: fn (*Terminal) void = clear;
    const reset_fn: fn (*Terminal) void = reset;
    const apply_limit_fn: fn (*Terminal, u32) Action.ApplySummary = applyLimit;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, apply_limit_fn };
}

test "const-read history and selection accessors stay stable" {
    const selection_state_fn: fn (*const Terminal) ?Selection.TerminalSelection = selectionState;
    _ = .{selection_state_fn};
}

test "lifecycle extension methods stay stable" {
    const init_cells_history_fn: fn (std.mem.Allocator, u16, u16, u16) anyerror!Terminal = Terminal.initWithCellsAndHistory;
    const selection_start_fn: fn (*Terminal, i32, u16) void = selectionStart;
    const selection_update_fn: fn (*Terminal, i32, u16) void = selectionUpdate;
    const selection_finish_fn: fn (*Terminal) void = selectionFinish;
    const selection_clear_fn: fn (*Terminal) void = selectionClear;
    _ = .{ init_cells_history_fn, selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "snapshot capture remains deterministic" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "TEST");
    apply(&terminal);

    var snap1 = try captureSnapshot(&terminal);
    defer snap1.deinit();

    var snap2 = try captureSnapshot(&terminal);
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.rows, snap2.rows);
    try std.testing.expectEqual(snap1.cols, snap2.cols);
    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
}

test "resize keeps history enabled state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 1, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "111\n222\n333");
    apply(&terminal);
    const before = visibleView(&terminal, .{}).history_count;
    try resizeTerminal(&terminal, 3, 3);

    try std.testing.expectEqual(@as(u16, 8), historyCapacity(&terminal));
    try std.testing.expect(visibleView(&terminal, .{}).history_count <= before);
}

test "alternate screen exit preserves primary scrollback" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 2, 4, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "AAAA\nBBBB\nCCCC\nDDDD");
    apply(&terminal);
    var before = try captureSnapshot(&terminal);
    defer before.deinit();
    const history_before = visibleView(&terminal, .{}).history_count;
    try std.testing.expect(history_before > 0);

    feedSlice(&terminal, "\x1b[?1049hALT!");
    apply(&terminal);
    try std.testing.expect(visibleView(&terminal, .{}).is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 0), visibleView(&terminal, .{}).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), activeScreen(&terminal).cellAt(0, 0));

    feedSlice(&terminal, "\x1b[?1049l");
    apply(&terminal);
    var after = try captureSnapshot(&terminal);
    defer after.deinit();
    try std.testing.expect(!visibleView(&terminal, .{}).is_alternate_screen);
    try std.testing.expectEqual(history_before, visibleView(&terminal, .{}).history_count);
    try std.testing.expectEqual(before.cursor_row, after.cursor_row);
    try std.testing.expectEqual(before.cursor_col, after.cursor_col);
    var row: u16 = 0;
    while (row < before.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < before.cols) : (col += 1) {
            try std.testing.expectEqual(before.cellAt(row, col), after.cellAt(row, col));
        }
    }
}

test "alternate screen 1049 restores primary cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b[3;4H\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    apply(&terminal);
    try std.testing.expectEqual(@as(u16, 2), activeScreen(&terminal).cursor_row);
    try std.testing.expectEqual(@as(u16, 3), activeScreen(&terminal).cursor_col);
}

test "alternate screen switches mark active viewport fully dirty" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 4);
    defer terminal.deinit();

    clearDirtyRows(&terminal);
    feedSlice(&terminal, "\x1b[?1049h");
    apply(&terminal);
    const enter_dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), enter_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), enter_dirty.dirty_cols_end[2]);

    clearDirtyRows(&terminal);
    feedSlice(&terminal, "\x1b[?1049l");
    apply(&terminal);
    const exit_dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), exit_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), exit_dirty.dirty_cols_end[2]);
}

test "full-screen scroll dirties only exposed bottom row" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 4, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "AAAA\nBBBB\nCCCC");
    apply(&terminal);
    clearDirtyRows(&terminal);

    feedSlice(&terminal, "\nDDDD");
    apply(&terminal);

    const dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 2), dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), dirty.dirty_cols_start[2]);
    try std.testing.expectEqual(@as(u16, 3), dirty.dirty_cols_end[2]);
}

test "surface source ack clears matching dirty generation" {
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    var cells: [8]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;

    const before = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(before.dirty_needed > 0);
    try std.testing.expect(before.dirty_generation != 0);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalAckSurface(handle, before.dirty_generation),
    );

    const after = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(@as(u64, 0), after.dirty_needed);
    try std.testing.expectEqual(@as(u8, 0), dirty_rows[0]);
    try std.testing.expectEqual(@as(u8, 0), dirty_rows[1]);
}

test "stale surface source ack does not clear newer dirtiness" {
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    var cells: [8]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    var title: [16]u8 = undefined;

    const first = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(first.dirty_generation != 0);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalFeed(handle, "A".ptr, 1),
    );
    const applied = ffi.terminalApply(handle, 64, title[0..].ptr, title.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), applied.status);
    try std.testing.expect(applied.applied > 0);

    const second = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(second.dirty_generation != first.dirty_generation);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalAckSurface(handle, first.dirty_generation),
    );

    const after_stale_ack = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(second.dirty_generation, after_stale_ack.dirty_generation);
    try std.testing.expect(after_stale_ack.dirty_needed > 0);
}

test "older ack cannot retire newer published generation" {
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    var cells: [8]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    var title: [16]u8 = undefined;

    _ = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalFeed(handle, "A".ptr, 1),
    );
    const first_apply = ffi.terminalApply(handle, 64, title[0..].ptr, title.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), first_apply.status);
    const second = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalFeed(handle, "B".ptr, 1),
    );
    const second_apply = ffi.terminalApply(handle, 64, title[0..].ptr, title.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), second_apply.status);
    const third = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(third.dirty_generation != second.dirty_generation);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalAckSurface(handle, second.dirty_generation),
    );

    const after_old_ack = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(third.dirty_generation, after_old_ack.dirty_generation);
    try std.testing.expect(after_old_ack.dirty_needed > 0);
}

test "terminal feed fails overlong OSC instead of truncating it" {
    const allocator = std.testing.allocator;
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    var bytes = try std.ArrayList(u8).initCapacity(allocator, 4_101);
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, "\x1b]0;");
    try bytes.appendNTimes(allocator, 'A', 4_097);
    try bytes.append(allocator, 0x07);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.limit_reached)),
        ffi.terminalFeed(handle, bytes.items.ptr, bytes.items.len),
    );

    const queued = ffi.terminalApply(handle, 0, null, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), queued.status);
    try std.testing.expectEqual(@as(u64, 0), queued.remaining_events);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalFeed(handle, "A".ptr, 1),
    );
    const applied = ffi.terminalApply(handle, 64, null, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), applied.status);
    try std.testing.expect(applied.applied > 0);
}

test "terminal feed fails queue-heavy burst at explicit event bound" {
    const allocator = std.testing.allocator;
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    var bytes = try std.ArrayList(u8).initCapacity(allocator, ParsedEvents.max_queued_events + 1);
    defer bytes.deinit(allocator);
    try bytes.appendNTimes(allocator, 0x07, ParsedEvents.max_queued_events + 1);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.limit_reached)),
        ffi.terminalFeed(handle, bytes.items.ptr, bytes.items.len),
    );

    const queued = ffi.terminalApply(handle, 0, null, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), queued.status);
    try std.testing.expectEqual(@as(u64, 0), queued.remaining_events);
}

test "input encoding APIs are callable without terminal facade methods" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "TEST");
    apply(&terminal);

    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    _ = encodeKey(&terminal, 'A', 0);
    _ = encodeKey(&terminal, 'B', 0);

    var snap_after = try captureSnapshot(&terminal);
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
}

test "Input exposes key and modifier constants" {
    _ = Input.mod_none;
    _ = Input.mod_shift;
    _ = Input.mod_alt;
    _ = Input.mod_ctrl;
    _ = Input.key_enter;
    _ = Input.key_tab;
    _ = Input.key_backspace;
    _ = Input.key_escape;
    _ = Input.key_up;
    _ = Input.key_down;
    _ = Input.key_left;
    _ = Input.key_right;
    _ = Input.key_kp_0;
    _ = Input.key_kp_enter;
}
