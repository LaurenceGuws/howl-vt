const std = @import("std");
const screen_mod = @import("../screen.zig");
const action_vocabulary = @import("../action/vocabulary.zig");

const Grid = screen_mod.Screen;
const SemanticEvent = action_vocabulary.SemanticEvent;

test "screen resize: row-only resize preserves live bottom and restores from history" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 4, 4, 8);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "AAAA" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "BBBB" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "CCCC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "PROM" });
    s.cursor_row = 3;
    s.cursor_col = 3;

    try s.resize(gpa, 2, 4);

    try std.testing.expectEqual(@as(u32, 2), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'B'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'P'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);

    try s.resize(gpa, 4, 4);

    try std.testing.expectEqual(@as(u32, 0), s.historyCount());
    try std.testing.expectEqual(@as(u16, 8), s.historyCapacity());
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'P'), s.cellAt(3, 0));
    try std.testing.expectEqual(@as(u16, 3), s.cursor_row);
}

test "screen resize: column resize reflows wrapped content into history and viewport" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 2, 4, 8);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "ABCDEFGHIJ" });

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(0, 3));

    try s.resize(gpa, 1, 5);

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u16, 8), s.historyCapacity());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), s.historyRowAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'F'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(0, 4));

    try s.resize(gpa, 2, 4);

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'H'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'I'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(1, 1));
}

test "screen resize: column resize preserves exact-fill cursor wrap state" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCellsAndHistory(gpa, 1, 4, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "ABCD" });

    try std.testing.expect(s.wrap_pending);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);

    try s.resize(gpa, 1, 2);

    try std.testing.expectEqual(@as(u32, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expect(s.wrap_pending);
}
