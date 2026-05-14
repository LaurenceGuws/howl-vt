//! End-to-end terminal flow tests.

const std = @import("std");
const terminal_mod = @import("../terminal.zig");

const Terminal = terminal_mod.Terminal;

test "terminal: parser apply flow applies bytes to grid state deterministically" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    terminal.feedSlice("ab");
    terminal.feedByte('c');
    terminal.feedSlice("\r\nxy");
    terminal.apply();

    const s = terminal.screen();
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}
