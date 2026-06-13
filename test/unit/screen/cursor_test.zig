const std = @import("std");
const screen_mod = @import("../../../src/screen.zig");
const action_vocabulary = @import("../../../src/vocabulary.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const SemanticEvent = action_vocabulary.SemanticEvent;

test "screen cursor: initial cursor at origin" {
    const s = Screen.init(24, 80);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen cursor: visibility and auto-wrap modes do not move cursor" {
    var s = Screen.init(2, 5);
    s.cursor_row = 1;
    s.cursor_col = 4;
    s.apply(SemanticEvent{ .cursor_visible = false });
    s.apply(SemanticEvent{ .auto_wrap = false });
    try std.testing.expect(!s.cursor_visible);
    try std.testing.expect(!s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen cursor: origin mode makes cursor positioning relative to scroll region" {
    var s = Screen.init(6, 10);
    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 2, .bottom = 4 } });
    s.apply(SemanticEvent{ .origin_mode = true });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 1 } });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    try std.testing.expectEqual(@as(u16, 4), s.cursor_row);
}

test "screen cursor: save and restore preserves position and wrap" {
    var s = Screen.init(4, 8);
    s.cursor_row = 1;
    s.cursor_col = 5;
    s.wrap_pending = true;
    s.apply(.save_cursor);
    s.cursor_row = 3;
    s.cursor_col = 0;
    s.wrap_pending = false;
    s.apply(.restore_cursor);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), s.cursor_col);
    try std.testing.expect(s.wrap_pending);
}

test "screen cursor: directional and absolute moves clamp correctly" {
    var s = Screen.init(24, 80);
    s.cursor_row = 5;
    s.apply(SemanticEvent{ .cursor_up = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
    s.cursor_row = 1;
    s.apply(SemanticEvent{ .cursor_up = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    s.cursor_row = 20;
    s.apply(SemanticEvent{ .cursor_down = 10 });
    try std.testing.expectEqual(@as(u16, 23), s.cursor_row);
    s.cursor_col = 75;
    s.apply(SemanticEvent{ .cursor_forward = 10 });
    try std.testing.expectEqual(@as(u16, 79), s.cursor_col);
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 10, .col = 40 } });
    try std.testing.expectEqual(@as(u16, 10), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 40), s.cursor_col);
}

test "screen cursor: line-relative and axis-specific moves update the right fields" {
    var s = Grid.init(24, 80);
    s.cursor_row = 5;
    s.cursor_col = 40;
    s.apply(SemanticEvent{ .cursor_next_line = 3 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
    s.cursor_row = 5;
    s.cursor_col = 40;
    s.apply(SemanticEvent{ .cursor_prev_line = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
    s.cursor_row = 12;
    s.cursor_col = 20;
    s.apply(SemanticEvent{ .cursor_horizontal_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 12), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor_col);
    s.apply(SemanticEvent{ .cursor_vertical_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 7), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor_col);
}

test "screen cursor: zero rows and primitive cursor controls do not panic" {
    var s = Screen.init(0, 0);
    s.apply(SemanticEvent{ .cursor_down = 5 });
    s.apply(SemanticEvent{ .cursor_forward = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);

    var t = Grid.init(4, 10);
    t.cursor_row = 1;
    t.cursor_col = 7;
    t.apply(SemanticEvent.line_feed);
    t.apply(SemanticEvent.carriage_return);
    try std.testing.expectEqual(@as(u16, 2), t.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), t.cursor_col);
    t.cursor_col = 5;
    t.apply(SemanticEvent.backspace);
    try std.testing.expectEqual(@as(u16, 4), t.cursor_col);
}

test "screen cursor: cursor style updates presentation" {
    var s = Grid.init(4, 4);
    s.apply(SemanticEvent{ .cursor_style = .{ .shape = .bar, .blink = false } });
    try std.testing.expectEqual(.bar, s.cursor_style.shape);
    try std.testing.expect(!s.cursor_style.blink);
    s.apply(SemanticEvent{ .cursor_style = .{ .shape = .underline, .blink = true } });
    try std.testing.expectEqual(.underline, s.cursor_style.shape);
    try std.testing.expect(s.cursor_style.blink);
}
