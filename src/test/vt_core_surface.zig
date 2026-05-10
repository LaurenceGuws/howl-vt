//! Responsibility: vt-core facade and lifecycle surface coverage.
//! Ownership: vt-core API stability tests.
//! Reason: keep the public VtCore surface explicit without embedding tests in the vt-core facade file.

const std = @import("std");
const vt = @import("vt_core");
const grid = @import("../grid.zig");
const selection = @import("../selection.zig");
const input_mod = @import("../input.zig");

const Grid = grid.Grid;
const Selection = selection;
const Input = input_mod;

test "VtCore facade methods remain available" {
    try std.testing.expect(@hasDecl(vt.VtCore, "init"));
    try std.testing.expect(@hasDecl(vt.VtCore, "initWithCells"));
    try std.testing.expect(@hasDecl(vt.VtCore, "deinit"));
    try std.testing.expect(@hasDecl(vt.VtCore, "feedByte"));
    try std.testing.expect(@hasDecl(vt.VtCore, "feedSlice"));
    try std.testing.expect(@hasDecl(vt.VtCore, "apply"));
    try std.testing.expect(@hasDecl(vt.VtCore, "clear"));
    try std.testing.expect(@hasDecl(vt.VtCore, "reset"));
    try std.testing.expect(@hasDecl(vt.VtCore, "resetScreen"));
    try std.testing.expect(@hasDecl(vt.VtCore, "resize"));
    try std.testing.expect(@hasDecl(vt.VtCore, "screen"));
    try std.testing.expect(@hasDecl(vt.VtCore, "queuedEventCount"));
}

test "VtCore method signatures remain host-facing" {
    const Allocator = std.mem.Allocator;
    const init_fn: fn (Allocator, u16, u16) anyerror!vt.VtCore = vt.VtCore.init;
    const init_cells_fn: fn (Allocator, u16, u16) anyerror!vt.VtCore = vt.VtCore.initWithCells;
    const deinit_fn: fn (*vt.VtCore) void = vt.VtCore.deinit;
    const feed_byte_fn: fn (*vt.VtCore, u8) void = vt.VtCore.feedByte;
    const feed_slice_fn: fn (*vt.VtCore, []const u8) void = vt.VtCore.feedSlice;
    const apply_fn: fn (*vt.VtCore) void = vt.VtCore.apply;
    const clear_fn: fn (*vt.VtCore) void = vt.VtCore.clear;
    const reset_fn: fn (*vt.VtCore) void = vt.VtCore.reset;
    const reset_screen_fn: fn (*vt.VtCore) void = vt.VtCore.resetScreen;
    const resize_fn: fn (*vt.VtCore, u16, u16) anyerror!void = vt.VtCore.resize;
    const screen_fn: fn (*const vt.VtCore) *const Grid = vt.VtCore.screen;
    const queue_fn: fn (*const vt.VtCore) usize = vt.VtCore.queuedEventCount;
    _ = .{ init_fn, init_cells_fn, deinit_fn, feed_byte_fn, feed_slice_fn, apply_fn, clear_fn, reset_fn, reset_screen_fn, resize_fn, screen_fn, queue_fn };
}

test "const-read history and selection accessors stay stable" {
    const history_row_fn: fn (*const vt.VtCore, usize, u16) u21 = vt.VtCore.historyRowAt;
    const history_count_fn: fn (*const vt.VtCore) usize = vt.VtCore.historyCount;
    const history_capacity_fn: fn (*const vt.VtCore) u16 = vt.VtCore.historyCapacity;
    const selection_state_fn: fn (*const vt.VtCore) ?Selection.TerminalSelection = vt.VtCore.selectionState;
    _ = .{ history_row_fn, history_count_fn, history_capacity_fn, selection_state_fn };
}

test "lifecycle extension methods stay stable" {
    const init_cells_history_fn: fn (std.mem.Allocator, u16, u16, u16) anyerror!vt.VtCore = vt.VtCore.initWithCellsAndHistory;
    const selection_start_fn: fn (*vt.VtCore, i32, u16) void = vt.VtCore.selectionStart;
    const selection_update_fn: fn (*vt.VtCore, i32, u16) void = vt.VtCore.selectionUpdate;
    const selection_finish_fn: fn (*vt.VtCore) void = vt.VtCore.selectionFinish;
    const selection_clear_fn: fn (*vt.VtCore) void = vt.VtCore.selectionClear;
    _ = .{ init_cells_history_fn, selection_start_fn, selection_update_fn, selection_finish_fn, selection_clear_fn };
}

test "snapshot surface remains deterministic" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("TEST");
    vt_core.apply();

    var snap1 = try vt_core.snapshot();
    defer snap1.deinit();

    var snap2 = try vt_core.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.rows, snap2.rows);
    try std.testing.expectEqual(snap1.cols, snap2.cols);
    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
}

test "resize keeps history enabled state" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCellsAndHistory(allocator, 1, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("111\n222\n333");
    vt_core.apply();
    const before = vt_core.historyCount();
    try vt_core.resize(3, 3);

    try std.testing.expectEqual(@as(u16, 8), vt_core.historyCapacity());
    try std.testing.expect(vt_core.historyCount() <= before);
}

test "alternate screen exit preserves primary scrollback" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCellsAndHistory(allocator, 2, 4, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("AAAA\nBBBB\nCCCC\nDDDD");
    vt_core.apply();
    var before = try vt_core.snapshot();
    defer before.deinit();
    const history_before = vt_core.historyCount();
    try std.testing.expect(history_before > 0);

    vt_core.feedSlice("\x1b[?1049hALT!");
    vt_core.apply();
    try std.testing.expect(vt_core.isAlternateScreen());
    try std.testing.expectEqual(@as(usize, 0), vt_core.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), vt_core.screen().cellAt(0, 0));

    vt_core.feedSlice("\x1b[?1049l");
    vt_core.apply();
    var after = try vt_core.snapshot();
    defer after.deinit();
    try std.testing.expect(!vt_core.isAlternateScreen());
    try std.testing.expectEqual(history_before, vt_core.historyCount());
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
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[3;4H\x1b[?1049h\x1b[2;2H\x1b[?1049l");
    vt_core.apply();
    try std.testing.expectEqual(@as(u16, 2), vt_core.screen().cursor_row);
    try std.testing.expectEqual(@as(u16, 3), vt_core.screen().cursor_col);
}

test "alternate screen switches mark active viewport fully dirty" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 4);
    defer vt_core.deinit();

    vt_core.clearDirtyRows();
    vt_core.feedSlice("\x1b[?1049h");
    vt_core.apply();
    const enter_dirty = vt_core.screen().peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), enter_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), enter_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), enter_dirty.dirty_cols_end[2]);

    vt_core.clearDirtyRows();
    vt_core.feedSlice("\x1b[?1049l");
    vt_core.apply();
    const exit_dirty = vt_core.screen().peekDirtyRows().?;
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.start_row);
    try std.testing.expectEqual(@as(u16, 2), exit_dirty.end_row);
    try std.testing.expectEqual(@as(u16, 0), exit_dirty.dirty_cols_start[0]);
    try std.testing.expectEqual(@as(u16, 3), exit_dirty.dirty_cols_end[2]);
}

test "encodeKey and encodeMouse methods are callable" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    const encode_key_fn: fn (*vt.VtCore, Input.Key, Input.Modifier) []const u8 = vt.VtCore.encodeKey;
    const encode_mouse_fn: fn (*vt.VtCore, Input.MouseEvent) []const u8 = vt.VtCore.encodeMouse;
    _ = .{ encode_key_fn, encode_mouse_fn };

    vt_core.feedSlice("TEST");
    vt_core.apply();

    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    _ = vt_core.encodeKey('A', 0);
    _ = vt_core.encodeKey('B', 0);

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
}

test "VtCore exposes key and modifier constants" {
    _ = vt.VtCore.mod_none;
    _ = vt.VtCore.mod_shift;
    _ = vt.VtCore.mod_alt;
    _ = vt.VtCore.mod_ctrl;
    _ = vt.VtCore.key_enter;
    _ = vt.VtCore.key_tab;
    _ = vt.VtCore.key_backspace;
    _ = vt.VtCore.key_escape;
    _ = vt.VtCore.key_up;
    _ = vt.VtCore.key_down;
    _ = vt.VtCore.key_left;
    _ = vt.VtCore.key_right;
    _ = vt.VtCore.key_kp_0;
    _ = vt.VtCore.key_kp_enter;
}
