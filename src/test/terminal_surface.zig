//! Public Terminal API and lifecycle tests.

const std = @import("std");
const vt = @import("howl_vt");
const grid = @import("../grid.zig");
const selection = @import("../selection.zig");
const input_mod = @import("../input.zig");

const Grid = grid.Grid;
const Selection = selection;
const Input = input_mod;

test "Terminal public methods remain available" {
    try std.testing.expect(@hasDecl(vt.Terminal, "init"));
    try std.testing.expect(@hasDecl(vt.Terminal, "initWithCells"));
    try std.testing.expect(@hasDecl(vt.Terminal, "deinit"));
    try std.testing.expect(@hasDecl(vt.Terminal, "feedByte"));
    try std.testing.expect(@hasDecl(vt.Terminal, "feedSlice"));
    try std.testing.expect(@hasDecl(vt.Terminal, "apply"));
    try std.testing.expect(@hasDecl(vt.Terminal, "clear"));
    try std.testing.expect(@hasDecl(vt.Terminal, "reset"));
    try std.testing.expect(@hasDecl(vt.Terminal, "resetScreen"));
    try std.testing.expect(@hasDecl(vt.Terminal, "resize"));
    try std.testing.expect(@hasDecl(vt.Terminal, "screen"));
    try std.testing.expect(@hasDecl(vt.Terminal, "queuedEventCount"));
}

test "Terminal method signatures remain host-facing" {
    const Allocator = std.mem.Allocator;
    const init_fn: fn (Allocator, u16, u16) anyerror!vt.Terminal = vt.Terminal.init;
    const init_cells_fn: fn (Allocator, u16, u16) anyerror!vt.Terminal = vt.Terminal.initWithCells;
    const deinit_fn: fn (*vt.Terminal) void = vt.Terminal.deinit;
    const feed_byte_fn: fn (*vt.Terminal, u8) void = vt.Terminal.feedByte;
    const feed_slice_fn: fn (*vt.Terminal, []const u8) void = vt.Terminal.feedSlice;
    const apply_fn: fn (*vt.Terminal) void = vt.Terminal.apply;
    const clear_fn: fn (*vt.Terminal) void = vt.Terminal.clear;
    const reset_fn: fn (*vt.Terminal) void = vt.Terminal.reset;
    const reset_screen_fn: fn (*vt.Terminal) void = vt.Terminal.resetScreen;
    const resize_fn: fn (*vt.Terminal, u16, u16) anyerror!void = vt.Terminal.resize;
    const screen_fn: fn (*const vt.Terminal) *const Grid = vt.Terminal.screen;
    const queue_fn: fn (*const vt.Terminal) usize = vt.Terminal.queuedEventCount;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, reset_screen_fn, resize_fn, screen_fn, queue_fn };
}

test "const-read history and selection accessors stay stable" {
    const history_row_fn: fn (*const vt.Terminal, usize, u16) u21 = vt.Terminal.historyRowAt;
    const history_count_fn: fn (*const vt.Terminal) usize = vt.Terminal.historyCount;
    const history_capacity_fn: fn (*const vt.Terminal) u16 = vt.Terminal.historyCapacity;
    const selection_state_fn: fn (*const vt.Terminal) ?Selection.TerminalSelection = vt.Terminal.selectionState;
    _ = .{ history_row_fn, history_count_fn, history_capacity_fn, selection_state_fn };
}

test "lifecycle extension methods stay stable" {
    const init_cells_history_fn: fn (std.mem.Allocator, u16, u16, u16) anyerror!vt.Terminal = vt.Terminal.initWithCellsAndHistory;
    const selection_start_fn: fn (*vt.Terminal, i32, u16) void = vt.Terminal.selectionStart;
    const selection_update_fn: fn (*vt.Terminal, i32, u16) void = vt.Terminal.selectionUpdate;
    const selection_finish_fn: fn (*vt.Terminal) void = vt.Terminal.selectionFinish;
    const selection_clear_fn: fn (*vt.Terminal) void = vt.Terminal.selectionClear;
    _ = .{ init_cells_history_fn, selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "snapshot capture remains deterministic" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("TEST");
    terminal.apply();

    var snap1 = try terminal.snapshot();
    defer snap1.deinit();

    var snap2 = try terminal.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.rows, snap2.rows);
    try std.testing.expectEqual(snap1.cols, snap2.cols);
    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
}

test "resize keeps history enabled state" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.initWithCellsAndHistory(allocator, 1, 3, 8);
    defer terminal.deinit();

    terminal.feedSlice("111\n222\n333");
    terminal.apply();
    const before = terminal.historyCount();
    try terminal.resize(3, 3);

    try std.testing.expectEqual(@as(u16, 8), terminal.historyCapacity());
    try std.testing.expect(terminal.historyCount() <= before);
}

test "alternate screen exit preserves primary scrollback" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.initWithCellsAndHistory(allocator, 2, 4, 16);
    defer terminal.deinit();

    terminal.feedSlice("AAAA\nBBBB\nCCCC\nDDDD");
    terminal.apply();
    var before = try terminal.snapshot();
    defer before.deinit();
    const history_before = terminal.historyCount();
    try std.testing.expect(history_before > 0);

    terminal.feedSlice("\x1b[?1049hALT!");
    terminal.apply();
    try std.testing.expect(terminal.isAlternateScreen());
    try std.testing.expectEqual(@as(usize, 0), terminal.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), terminal.screen().cellAt(0, 0));

    terminal.feedSlice("\x1b[?1049l");
    terminal.apply();
    var after = try terminal.snapshot();
    defer after.deinit();
    try std.testing.expect(!terminal.isAlternateScreen());
    try std.testing.expectEqual(history_before, terminal.historyCount());
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
    var terminal = try vt.Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[3;4H\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    terminal.apply();
    try std.testing.expectEqual(@as(u16, 2), terminal.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen().cursor_col);
}

test "alternate screen switches mark active viewport fully dirty" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.initWithCells(allocator, 3, 4);
    defer terminal.deinit();

    terminal.clearDirtyRows();
    terminal.feedSlice("\x1b[?1049h");
    terminal.apply();
    const enter_dirty = terminal.screen().peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), enter_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), enter_dirty.dirty_cols_end[2]);

    terminal.clearDirtyRows();
    terminal.feedSlice("\x1b[?1049l");
    terminal.apply();
    const exit_dirty = terminal.screen().peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), exit_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), exit_dirty.dirty_cols_end[2]);
}

test "encodeKey and encodeMouse methods are callable" {
    const allocator = std.testing.allocator;
    var terminal = try vt.Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    const encode_key_fn: fn (*vt.Terminal, Input.Key, Input.Modifier) []const u8 = vt.Terminal.encodeKey;
    const encode_mouse_fn: fn (*vt.Terminal, Input.MouseEvent) []const u8 = vt.Terminal.encodeMouse;
    _ = .{ encode_key_fn, encode_mouse_fn };

    terminal.feedSlice("TEST");
    terminal.apply();

    var snap_before = try terminal.snapshot();
    defer snap_before.deinit();

    _ = terminal.encodeKey('A', 0);
    _ = terminal.encodeKey('B', 0);

    var snap_after = try terminal.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
}

test "Input exposes key and modifier constants" {
    _ = vt.Input.mod_none;
    _ = vt.Input.mod_shift;
    _ = vt.Input.mod_alt;
    _ = vt.Input.mod_ctrl;
    _ = vt.Input.key_enter;
    _ = vt.Input.key_tab;
    _ = vt.Input.key_backspace;
    _ = vt.Input.key_escape;
    _ = vt.Input.key_up;
    _ = vt.Input.key_down;
    _ = vt.Input.key_left;
    _ = vt.Input.key_right;
    _ = vt.Input.key_kp_0;
    _ = vt.Input.key_kp_enter;
}
