const std = @import("std");
const parser_mod = @import("../../src/parser.zig");
const terminal_mod = @import("../../src/terminal.zig");
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

test "terminal feed fails overlong OSC instead of truncating it" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();

    var bytes = try std.ArrayList(u8).initCapacity(allocator, 4_101);
    defer bytes.deinit(allocator);
    try bytes.appendSlice(allocator, "\x1b]0;");
    try bytes.appendNTimes(allocator, 'A', 4_097);
    try bytes.append(allocator, 0x07);

    try std.testing.expectError(error.StringControlLimit, terminal.feed(bytes.items));

    const recovered = try terminal.feed("A");
    try std.testing.expect(recovered.state_changed);
}

test "terminal feed fails overlong APC instead of truncating it" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();

    _ = try terminal.feed("\x1b_");

    const chunk_len: usize = 4096;
    const chunk = try allocator.alloc(u8, chunk_len);
    defer allocator.free(chunk);
    @memset(chunk, 'A');

    var sent: usize = 0;
    while (sent + chunk_len <= parser_mod.max_apc_control_bytes) : (sent += chunk_len) {
        _ = try terminal.feed(chunk);
    }

    try std.testing.expectError(error.StringControlLimit, terminal.feed(chunk[0..1]));

    const recovered = try terminal.feed("A");
    try std.testing.expect(recovered.state_changed);
}

test "terminal feed fails overlong PM instead of truncating it" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();

    _ = try terminal.feed("\x1b^");

    const chunk_len: usize = 4096;
    const chunk = try allocator.alloc(u8, chunk_len);
    defer allocator.free(chunk);
    @memset(chunk, 'A');

    var sent: usize = 0;
    while (sent + chunk_len <= parser_mod.max_metadata_control_bytes) : (sent += chunk_len) {
        _ = try terminal.feed(chunk);
    }

    try std.testing.expectError(error.StringControlLimit, terminal.feed(chunk[0..1]));

    const recovered = try terminal.feed("A");
    try std.testing.expect(recovered.state_changed);
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
