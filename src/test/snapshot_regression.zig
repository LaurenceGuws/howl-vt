//! Snapshot capture regression tests.

const std = @import("std");
const terminal_mod = @import("../terminal.zig");

const Terminal = terminal_mod.Terminal;
test "snapshot: capture from simple text" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("HELLO");
    terminal.apply();

    var snap = try terminal.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 5), snap.rows);
    try std.testing.expectEqual(@as(u16, 10), snap.cols);
    try std.testing.expectEqual(@as(u16, 0), snap.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), snap.cursor_col);
    try std.testing.expectEqual(true, snap.cursor_visible);
    try std.testing.expectEqual(true, snap.auto_wrap);
    try std.testing.expectEqual(@as(u21, 'H'), snap.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), snap.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'L'), snap.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'L'), snap.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'O'), snap.cellAt(0, 4));
}

test "snapshot: determinism across identical state" {
    const gpa = std.testing.allocator;

    var vt_core1 = try Terminal.initWithCells(gpa, 5, 10);
    defer vt_core1.deinit();
    vt_core1.feedSlice("TEST");
    vt_core1.apply();
    var snap1 = try vt_core1.snapshot();
    defer snap1.deinit();

    var vt_core2 = try Terminal.initWithCells(gpa, 5, 10);
    defer vt_core2.deinit();
    vt_core2.feedSlice("TEST");
    vt_core2.apply();
    var snap2 = try vt_core2.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
    try std.testing.expectEqual(snap1.cursor_visible, snap2.cursor_visible);
    try std.testing.expectEqual(snap1.auto_wrap, snap2.auto_wrap);

    if (snap1.cells != null and snap2.cells != null) {
        const size = @as(usize, snap1.rows) * @as(usize, snap1.cols);
        try std.testing.expectEqualSlices(u21, snap1.cells.?[0..size], snap2.cells.?[0..size]);
    }
}

test "snapshot: split-feed equivalence" {
    const gpa = std.testing.allocator;

    var vt_core_atomic = try Terminal.initWithCells(gpa, 5, 10);
    defer vt_core_atomic.deinit();
    vt_core_atomic.feedSlice("ABCDEFGHIJ");
    vt_core_atomic.apply();
    var snap_atomic = try vt_core_atomic.snapshot();
    defer snap_atomic.deinit();

    var vt_core_chunked = try Terminal.initWithCells(gpa, 5, 10);
    defer vt_core_chunked.deinit();
    vt_core_chunked.feedByte('A');
    vt_core_chunked.feedByte('B');
    vt_core_chunked.feedSlice("CD");
    vt_core_chunked.feedSlice("EFGHIJ");
    vt_core_chunked.apply();
    var snap_chunked = try vt_core_chunked.snapshot();
    defer snap_chunked.deinit();

    try std.testing.expectEqual(snap_atomic.cursor_col, snap_chunked.cursor_col);
    try std.testing.expectEqual(snap_atomic.cursor_row, snap_chunked.cursor_row);

    if (snap_atomic.cells != null and snap_chunked.cells != null) {
        const size = @as(usize, snap_atomic.rows) * @as(usize, snap_atomic.cols);
        try std.testing.expectEqualSlices(u21, snap_atomic.cells.?[0..size], snap_chunked.cells.?[0..size]);
    }
}

test "snapshot: history capture when history is enabled" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(gpa, 3, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("AAA\nBBB\nCCC\nDDD");
    terminal.apply();

    var snap = try terminal.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 3), snap.rows);
    try std.testing.expectEqual(@as(u16, 5), snap.cols);
    try std.testing.expectEqual(@as(u16, 10), snap.history_capacity);
    try std.testing.expectEqual(snap.history_count, terminal.visibleView(.{}).history_count);

    if (snap.history != null) {
        try std.testing.expect(snap.history.?.len > 0);
    }
}

test "snapshot: historyRowAt matches terminal after wraparound" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(gpa, 2, 3, 2);
    defer terminal.deinit();

    // Force history ring-buffer wraparound (capacity 2, scroll more than 2 rows).
    terminal.feedSlice("111\n222\n333\n444\n555");
    terminal.apply();

    var snap = try terminal.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(terminal.visibleView(.{}).history_count, snap.history_count);
    try std.testing.expectEqual(terminal.historyCapacity(), snap.history_capacity);

    var idx: usize = 0;
    while (idx < terminal.visibleView(.{}).history_count) : (idx += 1) {
        var col: u16 = 0;
        while (col < terminal.screen().cols) : (col += 1) {
            try std.testing.expectEqual(terminal.historyRowAt(idx, col), snap.historyRowAt(idx, col));
        }
    }
}

test "snapshot: selection state is included" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("HELLO");
    terminal.apply();

    terminal.selectionStart(0, 0);
    terminal.selectionUpdate(0, 4);
    terminal.selectionFinish();

    var snap = try terminal.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(true, snap.selection != null);
    if (snap.selection) |sel| {
        try std.testing.expectEqual(@as(i32, 0), sel.start.row);
        try std.testing.expectEqual(@as(u16, 0), sel.start.col);
        try std.testing.expectEqual(@as(i32, 0), sel.end.row);
        try std.testing.expectEqual(@as(u16, 4), sel.end.col);
        try std.testing.expectEqual(true, sel.active);
    }
}

test "snapshot: parity with direct screen state" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("TEST");
    terminal.apply();

    var snap = try terminal.snapshot();
    defer snap.deinit();

    const screen = terminal.screen();
    try std.testing.expectEqual(screen.rows, snap.rows);
    try std.testing.expectEqual(screen.cols, snap.cols);
    try std.testing.expectEqual(screen.cursor_row, snap.cursor_row);
    try std.testing.expectEqual(screen.cursor_col, snap.cursor_col);
    try std.testing.expectEqual(screen.cursor_visible, snap.cursor_visible);
    try std.testing.expectEqual(screen.auto_wrap, snap.auto_wrap);
}
