//! End-to-end terminal flow tests.

const std = @import("std");
const terminal_mod = @import("../terminal.zig");
const stream_harness = @import("stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const StreamHarness = stream_harness.Harness;

test "terminal: stream applies bytes to grid state deterministically" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("ab");
    try stream.next('c');
    try stream.nextSlice("\r\nxy");

    const s = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}
