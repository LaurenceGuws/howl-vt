const std = @import("std");
const screen_mod = @import("../../../src/screen.zig");
const action_vocabulary = @import("../../../src/vocabulary.zig");

const Grid = screen_mod.Screen;
const SemanticEvent = action_vocabulary.SemanticEvent;

test "screen tabs: default and counted tab moves clamp correctly" {
    var s = Grid.init(4, 20);
    s.cursor.setColByClient(3);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor.col);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 16), s.cursor.col);
    s.cursor.setColByClient(17);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 19), s.cursor.col);
    s.cursor.setColByClient(1);
    s.apply(SemanticEvent{ .horizontal_tab_forward = 2 });
    try std.testing.expectEqual(@as(u16, 16), s.cursor.col);
    s.cursor.setColByClient(17);
    s.apply(SemanticEvent{ .horizontal_tab_forward = 2 });
    try std.testing.expectEqual(@as(u16, 19), s.cursor.col);
    s.cursor.setColByClient(17);
    s.apply(SemanticEvent{ .horizontal_tab_back = 2 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor.col);
    s.cursor.setColByClient(3);
    s.apply(SemanticEvent{ .horizontal_tab_back = 2 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
}

test "screen tabs: HTS TBC and reset manage custom and default stops" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 20);
    defer s.deinit(gpa);

    s.cursor.setColByClient(5);
    s.apply(SemanticEvent.horizontal_tab_set);
    s.cursor.setColByClient(3);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 5), s.cursor.col);

    s.apply(SemanticEvent.tab_clear_current);
    s.cursor.setColByClient(3);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor.col);

    s.apply(SemanticEvent.tab_clear_all);
    s.cursor.setColByClient(3);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 19), s.cursor.col);

    s.reset();
    s.cursor.setColByClient(3);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor.col);

    s.cursor.setColByClient(8);
    s.apply(.tab_clear_current);
    s.apply(.tab_clear_all);
    try std.testing.expect(!s.tabStopAt(8));
    try std.testing.expect(!s.tabStopAt(16));
    s.apply(.reset_default_tab_stops);
    try std.testing.expect(s.tabStopAt(8));
    try std.testing.expect(s.tabStopAt(16));
    try std.testing.expect(!s.tabStopAt(4));
}

test "screen tabs: resize wider preserves custom and default stops" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 20);
    defer s.deinit(gpa);

    s.cursor.setColByClient(5);
    s.apply(.horizontal_tab_set);
    s.cursor.setColByClient(8);
    s.apply(.tab_clear_current);

    try s.resize(gpa, 4, 25);

    try std.testing.expect(s.tabStopAt(5));
    try std.testing.expect(!s.tabStopAt(8));
    try std.testing.expect(s.tabStopAt(16));
    try std.testing.expect(s.tabStopAt(24));
}
