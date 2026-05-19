//! Snapshot capture regression tests.

const std = @import("std");
const action_mod = @import("../action.zig");
const screen_capture = @import("screen_capture.zig");
const screen_set = @import("../screen_set.zig");
const selection = @import("../selection.zig");
const terminal_mod = @import("../terminal.zig");

const Terminal = terminal_mod.Terminal;
const Action = action_mod;
fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

fn visibleView(terminal: *const Terminal) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, .{});
}

fn feedByte(terminal: *Terminal, byte: u8) void {
    terminal.parser.feedSlice(&.{byte}) catch unreachable;
}

fn feedSlice(terminal: *Terminal, bytes: []const u8) void {
    terminal.parser.feedSlice(bytes) catch unreachable;
}

fn apply(terminal: *Terminal) void {
    Action.apply(terminal);
}
test "snapshot: capture from simple text" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "HELLO");
    apply(&terminal);

    var snap = try captureSnapshot(&terminal);
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
    feedSlice(&vt_core1, "TEST");
    apply(&vt_core1);
    var snap1 = try captureSnapshot(&vt_core1);
    defer snap1.deinit();

    var vt_core2 = try Terminal.initWithCells(gpa, 5, 10);
    defer vt_core2.deinit();
    feedSlice(&vt_core2, "TEST");
    apply(&vt_core2);
    var snap2 = try captureSnapshot(&vt_core2);
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
    feedSlice(&vt_core_atomic, "ABCDEFGHIJ");
    apply(&vt_core_atomic);
    var snap_atomic = try captureSnapshot(&vt_core_atomic);
    defer snap_atomic.deinit();

    var vt_core_chunked = try Terminal.initWithCells(gpa, 5, 10);
    defer vt_core_chunked.deinit();
    feedByte(&vt_core_chunked, 'A');
    feedByte(&vt_core_chunked, 'B');
    feedSlice(&vt_core_chunked, "CD");
    feedSlice(&vt_core_chunked, "EFGHIJ");
    apply(&vt_core_chunked);
    var snap_chunked = try captureSnapshot(&vt_core_chunked);
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

    feedSlice(&terminal, "AAA\nBBB\nCCC\nDDD");
    apply(&terminal);

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 3), snap.rows);
    try std.testing.expectEqual(@as(u16, 5), snap.cols);
    try std.testing.expectEqual(@as(u16, 10), snap.history_capacity);
    try std.testing.expectEqual(snap.history_count, visibleView(&terminal).history_count);

    if (snap.history != null) {
        try std.testing.expect(snap.history.?.len > 0);
    }
}

test "snapshot: historyRowAt matches terminal after wraparound" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(gpa, 2, 3, 2);
    defer terminal.deinit();

    // Force history ring-buffer wraparound (capacity 2, scroll more than 2 rows).
    feedSlice(&terminal, "111\n222\n333\n444\n555");
    apply(&terminal);

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    try std.testing.expectEqual(visibleView(&terminal).history_count, snap.history_count);
    try std.testing.expectEqual(screen_set.historyCapacity(&terminal.screen_state), snap.history_capacity);

    var idx: u32 = 0;
    while (idx < visibleView(&terminal).history_count) : (idx += 1) {
        var col: u16 = 0;
        while (col < terminal.screen_state.activeConst().cols) : (col += 1) {
            try std.testing.expectEqual(screen_set.historyRowAt(&terminal.screen_state, idx, col), snap.historyRowAt(idx, col));
        }
    }
}

test "snapshot: selection state is included" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "HELLO");
    apply(&terminal);

    selection.terminalStart(&terminal, 0, 0);
    selection.terminalUpdate(&terminal, 0, 4);
    selection.terminalFinish(&terminal);

    var snap = try captureSnapshot(&terminal);
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

    feedSlice(&terminal, "TEST");
    apply(&terminal);

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    const screen = terminal.screen_state.activeConst();
    try std.testing.expectEqual(screen.rows, snap.rows);
    try std.testing.expectEqual(screen.cols, snap.cols);
    try std.testing.expectEqual(screen.cursor_row, snap.cursor_row);
    try std.testing.expectEqual(screen.cursor_col, snap.cursor_col);
    try std.testing.expectEqual(screen.cursor_visible, snap.cursor_visible);
    try std.testing.expectEqual(screen.auto_wrap, snap.auto_wrap);
}
