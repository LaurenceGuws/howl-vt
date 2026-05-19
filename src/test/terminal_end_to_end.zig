//! End-to-end terminal flow tests.

const std = @import("std");
const action = @import("../action.zig");
const terminal_mod = @import("../terminal.zig");

const Action = action;
const Terminal = terminal_mod.Terminal;

test "terminal: parser queue applies bytes to grid state deterministically" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    try terminal.parser_queue.feedSliceChecked("ab");
    try terminal.parser_queue.feedByteChecked('c');
    try terminal.parser_queue.feedSliceChecked("\r\nxy");
    Action.apply(&terminal);

    const s = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}
