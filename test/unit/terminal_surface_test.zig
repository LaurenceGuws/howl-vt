const std = @import("std");
const parser_mod = @import("../../src/parser.zig");
const terminal_mod = @import("../../src/terminal.zig");
const ffi = @import("../../src/ffi/main.zig");
const screen = @import("../../src/screen.zig");
const screen_capture = @import("../support/screen_capture.zig");
const screen_set = @import("../../src/screen_set.zig");
const selection = @import("../../src/selection.zig");
const selection_projection = @import("../../src/selection_projection.zig");
const input_encode = @import("../../src/input/encode.zig");
const input_keyboard = @import("../../src/input/keyboard.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const Screen = screen.Screen;
const Selection = selection;
const StreamHarness = stream_harness.Harness;

var encode_scratch: input_encode.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: input_keyboard.Key, mod: input_keyboard.Modifier) []const u8 {
    return input_encode.encodeKey(terminal, &encode_scratch, key, mod);
}

fn activeScreen(terminal: *const Terminal) *const Screen {
    return terminal.screen_state.activeConst();
}

fn visibleView(terminal: *const Terminal, scrollback_offset: u32) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, scrollback_offset);
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

fn copySurfaceOk(handle: ffi.VtHandle, rows: u16, cols: u16, cells: []ffi.FfiSurfaceCell, dirty_rows: []u8, cols_start: []u16, cols_end: []u16) !ffi.FfiSurfaceResult {
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
    );
    try std.testing.expectEqual(@intFromEnum(ffi.HowlVtCallStatus.ok), result.status);
    try std.testing.expectEqual(rows, result.source.rows);
    try std.testing.expectEqual(cols, result.source.cols);
    try std.testing.expectEqual(rows, @as(u16, @intCast(result.source.dirty_rows.len)));
    try std.testing.expectEqual(rows, @as(u16, @intCast(result.source.dirty_cols_start.len)));
    try std.testing.expectEqual(rows, @as(u16, @intCast(result.source.dirty_cols_end.len)));
    return result;
}

fn terminalFromHandle(handle: ffi.VtHandle) *Terminal {
    return @ptrCast(@alignCast(handle.?));
}

fn hasDirtyRows(rows: []const u8) bool {
    for (rows) |dirty| {
        if (dirty != 0) return true;
    }
    return false;
}

test "Terminal public methods remain available" {
    try std.testing.expect(@hasDecl(Terminal, "init"));
    try std.testing.expect(@hasDecl(Terminal, "initWithCells"));
    try std.testing.expect(@hasDecl(Terminal, "deinit"));
    try std.testing.expect(@hasDecl(Terminal, "vtStream"));
}

test "Terminal method signatures remain host-facing" {
    const Allocator = std.mem.Allocator;
    const init_fn: fn (Allocator, u16, u16) anyerror!Terminal = Terminal.init;
    const init_cells_fn: fn (Allocator, u16, u16) anyerror!Terminal = Terminal.initWithCells;
    const init_cells_history_fn: fn (Allocator, u16, u16, u16) anyerror!Terminal = Terminal.initWithCellsAndHistory;
    const deinit_fn: fn (*Terminal) void = Terminal.deinit;
    const vt_stream_fn: fn (*Terminal) Terminal.Stream = Terminal.vtStream;
    _ = .{ init_fn, init_cells_fn, init_cells_history_fn, deinit_fn, vt_stream_fn };
}

test "const-read history and selection accessors stay stable" {
    const selection_state_fn: fn (*const Terminal) ?Selection.TerminalSelection = selectionState;
    _ = .{selection_state_fn};
}

test "lifecycle extension methods stay stable" {
    const selection_start_fn: fn (*Terminal, i32, u16) void = selectionStart;
    const selection_update_fn: fn (*Terminal, i32, u16) void = selectionUpdate;
    const selection_finish_fn: fn (*Terminal) void = selectionFinish;
    const selection_clear_fn: fn (*Terminal) void = selectionClear;
    _ = .{ selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "snapshot capture remains deterministic" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("TEST");

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
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("111\n222\n333");
    const before = visibleView(&terminal, 0).history_count;
    try resizeTerminal(&terminal, 3, 3);

    try std.testing.expectEqual(@as(u16, 8), historyCapacity(&terminal));
    try std.testing.expect(visibleView(&terminal, 0).history_count <= before);
}

test "alternate screen exit preserves primary scrollback" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 2, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("AAAA\nBBBB\nCCCC\nDDDD");
    var before = try captureSnapshot(&terminal);
    defer before.deinit();
    const history_before = visibleView(&terminal, 0).history_count;
    try std.testing.expect(history_before > 0);

    try stream.nextSlice("\x1b[?1049hALT!");
    try std.testing.expect(visibleView(&terminal, 0).is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 0), visibleView(&terminal, 0).history_count);
    try std.testing.expectEqual(@as(u21, 'A'), activeScreen(&terminal).cellAt(0, 0));

    try stream.nextSlice("\x1b[?1049l");
    var after = try captureSnapshot(&terminal);
    defer after.deinit();
    try std.testing.expect(!visibleView(&terminal, 0).is_alternate_screen);
    try std.testing.expectEqual(history_before, visibleView(&terminal, 0).history_count);
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
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[3;4H");
    const before_enter = activeScreen(&terminal).cursor.position_changed_by_client_at;
    try stream.nextSlice("\x1b[3;4H\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    try std.testing.expectEqual(@as(u16, 2), activeScreen(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 3), activeScreen(&terminal).cursor.col);
    try std.testing.expectEqual(before_enter, activeScreen(&terminal).cursor.position_changed_by_client_at);
}

test "alternate screen switches mark active viewport fully dirty" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    clearDirtyRows(&terminal);
    try stream.nextSlice("\x1b[?1049h");
    const enter_dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), enter_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), enter_dirty.dirty_cols_end[2]);

    clearDirtyRows(&terminal);
    try stream.nextSlice("\x1b[?1049l");
    const exit_dirty = activeScreen(&terminal).peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), exit_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), exit_dirty.dirty_cols_end[2]);
}

test "alternate screen switching clears selection on the screen-set owner path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    selectionStart(&terminal, 0, 0);
    try std.testing.expect(selectionState(&terminal) != null);

    try stream.nextSlice("\x1b[?1049h");
    try std.testing.expectEqual(@as(?Selection.TerminalSelection, null), selectionState(&terminal));

    selectionStart(&terminal, 0, 0);
    try std.testing.expect(selectionState(&terminal) != null);

    try stream.nextSlice("\x1b[?1049l");
    try std.testing.expectEqual(@as(?Selection.TerminalSelection, null), selectionState(&terminal));
}

test "full-screen scroll dirties only exposed bottom row" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("AAAA\nBBBB\nCCCC");
    clearDirtyRows(&terminal);

    try stream.nextSlice("\nDDDD");

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
    try std.testing.expect(before.snapshot_seq != 0);
    try std.testing.expect(before.dirty_generation != 0);
    try std.testing.expect(hasDirtyRows(&dirty_rows));

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalAckSurface(handle, before.snapshot_seq),
    );

    const after = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(before.snapshot_seq, after.snapshot_seq);
    try std.testing.expectEqual(before.dirty_generation, after.dirty_generation);
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
    const first = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(first.snapshot_seq != 0);
    try std.testing.expect(first.dirty_generation != 0);

    const fed = ffi.terminalFeed(handle, "A".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), fed.status);
    try std.testing.expectEqual(@as(u8, 1), fed.state_changed);

    const second = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(second.snapshot_seq != first.snapshot_seq);
    try std.testing.expect(second.dirty_generation != first.dirty_generation);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalAckSurface(handle, first.snapshot_seq),
    );

    const after_stale_ack = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(second.snapshot_seq, after_stale_ack.snapshot_seq);
    try std.testing.expectEqual(second.dirty_generation, after_stale_ack.dirty_generation);
    try std.testing.expect(hasDirtyRows(&dirty_rows));
}

test "older ack cannot retire newer published generation" {
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    var cells: [8]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    _ = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    const first_feed = ffi.terminalFeed(handle, "A".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), first_feed.status);
    const second = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);

    const second_feed = ffi.terminalFeed(handle, "B".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), second_feed.status);
    const third = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(third.dirty_generation != second.dirty_generation);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)),
        ffi.terminalAckSurface(handle, second.snapshot_seq),
    );

    const after_old_ack = try copySurfaceOk(handle, 2, 4, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expectEqual(third.dirty_generation, after_old_ack.dirty_generation);
    try std.testing.expect(hasDirtyRows(&dirty_rows));
}

test "scrollback projection change gets a new surface snapshot sequence" {
    const handle = ffi.terminalInit(2, 2, 4);
    defer ffi.terminalDeinit(handle);

    const fed = ffi.terminalFeed(handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), fed.status);

    var cells: [4]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;

    const live = try copySurfaceOk(handle, 2, 2, &cells, &dirty_rows, &cols_start, &cols_end);
    const scrolled = ffi.terminalCopySurface(handle, 1, &cells, cells.len, &dirty_rows, dirty_rows.len, &cols_start, cols_start.len, &cols_end, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), scrolled.status);
    try std.testing.expect(scrolled.snapshot_seq != live.snapshot_seq);
    try std.testing.expectEqual(live.dirty_generation, scrolled.dirty_generation);
}

test "surface copy remains bounded after projected history wraps" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 2, 3, 2);
    defer terminal.deinit();
    var harness = try StreamHarness.init(&terminal);
    defer harness.deinit();

    try harness.nextSlice("aaa\nbbb\nccc\nddd\neee");

    const handle: ffi.VtHandle = @ptrCast(&terminal);
    var cells: [6]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;

    const result = try copySurfaceOk(handle, 2, 3, &cells, &dirty_rows, &cols_start, &cols_end);
    try std.testing.expect(result.history_count <= historyCapacity(&terminal));
}

test "copy surface exports bounded combining truth" {
    const handle = ffi.terminalInit(1, 2, 4);
    defer ffi.terminalDeinit(handle);

    const payload = [_]u8{ 0x6F, 0xCC, 0x80 };
    const fed = ffi.terminalFeed(handle, payload[0..].ptr, payload.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), fed.status);

    var cells: [2]ffi.FfiSurfaceCell = undefined;
    var dirty_rows: [1]u8 = undefined;
    var cols_start: [1]u16 = undefined;
    var cols_end: [1]u16 = undefined;
    _ = try copySurfaceOk(handle, 1, 2, &cells, &dirty_rows, &cols_start, &cols_end);

    try std.testing.expectEqual(@as(u32, 'o'), cells[0].codepoint);
    try std.testing.expectEqual(@as(u8, 1), cells[0].combining_len);
    try std.testing.expectEqual(@as(u32, 0x0300), cells[0].combining[0]);
}

test "copy surface keeps metadata on invalid output pointers" {
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    const result = ffi.terminalCopySurface(handle, 0, null, 8, null, 2, null, 2, null, 2);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.invalid_argument)), result.status);
    try std.testing.expectEqual(@as(u16, 2), result.source.rows);
    try std.testing.expectEqual(@as(u16, 4), result.source.cols);
    try std.testing.expectEqual(@as(u64, 8), result.source.surface_cells.len);
    try std.testing.expectEqual(@as(u64, 2), result.source.dirty_rows.len);
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

    const failed = ffi.terminalFeed(handle, bytes.items.ptr, bytes.items.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.limit_reached)), failed.status);

    const recovered = ffi.terminalFeed(handle, "A".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), recovered.status);
    try std.testing.expectEqual(@as(u8, 1), recovered.state_changed);
}

test "terminal feed fails overlong APC instead of truncating it" {
    const allocator = std.testing.allocator;
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    const begin = ffi.terminalFeed(handle, "\x1b_".ptr, 2);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), begin.status);

    const chunk_len: usize = 4096;
    const chunk = try allocator.alloc(u8, chunk_len);
    defer allocator.free(chunk);
    @memset(chunk, 'A');

    var sent: usize = 0;
    while (sent + chunk_len <= parser_mod.max_apc_control_bytes) : (sent += chunk_len) {
        const result = ffi.terminalFeed(handle, chunk.ptr, chunk.len);
        try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), result.status);
    }

    const failed = ffi.terminalFeed(handle, chunk.ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.limit_reached)), failed.status);

    const recovered = ffi.terminalFeed(handle, "A".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), recovered.status);
    try std.testing.expectEqual(@as(u8, 1), recovered.state_changed);
}

test "terminal feed fails overlong PM instead of truncating it" {
    const allocator = std.testing.allocator;
    const handle = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(handle);

    const begin = ffi.terminalFeed(handle, "\x1b^".ptr, 2);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), begin.status);

    const chunk_len: usize = 4096;
    const chunk = try allocator.alloc(u8, chunk_len);
    defer allocator.free(chunk);
    @memset(chunk, 'A');

    var sent: usize = 0;
    while (sent + chunk_len <= parser_mod.max_metadata_control_bytes) : (sent += chunk_len) {
        const result = ffi.terminalFeed(handle, chunk.ptr, chunk.len);
        try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), result.status);
    }

    const failed = ffi.terminalFeed(handle, chunk.ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.limit_reached)), failed.status);

    const recovered = ffi.terminalFeed(handle, "A".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(ffi.HowlVtCallStatus.ok)), recovered.status);
    try std.testing.expectEqual(@as(u8, 1), recovered.state_changed);
}

test "input encoding APIs are callable without terminal facade methods" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("TEST");

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
    _ = input_keyboard.mod_none;
    _ = input_keyboard.mod_shift;
    _ = input_keyboard.mod_alt;
    _ = input_keyboard.mod_ctrl;
    _ = input_keyboard.key_enter;
    _ = input_keyboard.key_tab;
    _ = input_keyboard.key_backspace;
    _ = input_keyboard.key_escape;
    _ = input_keyboard.key_up;
    _ = input_keyboard.key_down;
    _ = input_keyboard.key_left;
    _ = input_keyboard.key_right;
    _ = input_keyboard.key_kp_0;
    _ = input_keyboard.key_kp_enter;
}

test "selection follows viewport movement through scrollback rows" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 2, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("aa\r\nbb\r\ncc");

    selectionStart(&terminal, 1, 0);
    selectionUpdate(&terminal, 2, 1);
    selectionFinish(&terminal);

    const live = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(?selection_projection.Range, .{ .start = 0, .end_exclusive = 2 }), selection_projection.visibleRange(live, selectionState(&terminal).?, 0));
    try std.testing.expectEqual(@as(?selection_projection.Range, .{ .start = 0, .end_exclusive = 2 }), selection_projection.visibleRange(live, selectionState(&terminal).?, 1));

    const scrolled = visibleView(&terminal, 1);
    try std.testing.expectEqual(@as(?selection_projection.Range, null), selection_projection.visibleRange(scrolled, selectionState(&terminal).?, 0));
    try std.testing.expectEqual(@as(?selection_projection.Range, .{ .start = 0, .end_exclusive = 2 }), selection_projection.visibleRange(scrolled, selectionState(&terminal).?, 1));
}

test "cursor hides when viewport is scrolled off live bottom" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 2, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("aa\r\nbb\r\ncc");

    try std.testing.expect(visibleView(&terminal, 0).cursor_visible);
    try std.testing.expect(!visibleView(&terminal, 1).cursor_visible);
}
