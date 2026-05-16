//! Public Terminal API and lifecycle tests.

const std = @import("std");
const action_mod = @import("../action.zig");
const parser_mod = @import("../parser.zig");
const terminal_mod = @import("../terminal.zig");
const grid = @import("../grid.zig");
const screen_snapshot = @import("../screen/snapshot.zig");
const screen_view = @import("../screen/view.zig");
const selection = @import("../selection.zig");
const input_mod = @import("../input.zig");

const Terminal = terminal_mod.Terminal;
const Action = action_mod;
const Grid = grid.Grid;
const Selection = selection;
const Input = input_mod;
const Parser = parser_mod;

var encode_scratch: Input.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: Input.Key, mod: Input.Modifier) []const u8 {
    return Input.encodeKey(terminal, &encode_scratch, key, mod);
}

fn activeScreen(terminal: *const Terminal) *const Grid {
    return terminal.screen_state.activeConst();
}

fn visibleView(terminal: *const Terminal, options: screen_view.Options) screen_view.View {
    return screen_view.visibleView(&terminal.screen_state, options);
}

fn historyCapacity(terminal: *const Terminal) u16 {
    return screen_view.historyCapacity(&terminal.screen_state);
}

fn clearDirtyRows(terminal: *Terminal) void {
    screen_view.clearDirtyRows(&terminal.screen_state);
}

fn captureSnapshot(terminal: *const Terminal) !screen_snapshot.VtCoreSnapshot {
    return screen_snapshot.VtCoreSnapshot.captureFromScreen(
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
    Parser.feedByte(terminal, byte);
}

fn feedSlice(terminal: *Terminal, bytes: []const u8) void {
    Parser.feedSlice(terminal, bytes);
}

fn apply(terminal: *Terminal) void {
    Action.apply(terminal);
}

fn clear(terminal: *Terminal) void {
    Parser.clear(terminal);
}

fn reset(terminal: *Terminal) void {
    Parser.reset(terminal);
}

fn applyLimit(terminal: *Terminal, max_events: usize) Action.ApplySummary {
    return Action.applyLimit(terminal, max_events);
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
    const apply_limit_fn: fn (*Terminal, usize) Action.ApplySummary = applyLimit;
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
