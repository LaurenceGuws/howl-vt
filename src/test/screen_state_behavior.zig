//! Responsibility: behavioral conformance coverage for screen-state mutations.
//! Ownership: terminal screen-state correctness tests.
//! Reason: keep cursor, wrap, erase, and cell semantics explicit and build-gated.

const std = @import("std");
const grid = @import("../grid/grid.zig");
const interpret = @import("../interpret/interpret.zig");

const GridModel = grid.GridModel;
const SemanticEvent = interpret.SemanticEvent;
test "screen: initial cursor at origin" {
    const s = GridModel.init(24, 80);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: reset clears cursor wrap and cells" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcdef" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    s.reset();
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
    try std.testing.expect(s.cursor_visible);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
}

test "screen: cursor_visible mode toggles without moving cursor" {
    var s = GridModel.init(2, 5);
    s.cursor_row = 1;
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .cursor_visible = false });
    try std.testing.expect(!s.cursor_visible);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
    s.apply(SemanticEvent{ .cursor_visible = true });
    try std.testing.expect(s.cursor_visible);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
}

test "screen: auto_wrap mode toggles and does not move cursor" {
    var s = GridModel.init(2, 5);
    s.cursor_row = 1;
    s.cursor_col = 4;
    s.apply(SemanticEvent{ .auto_wrap = false });
    try std.testing.expect(!s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    s.apply(SemanticEvent{ .auto_wrap = true });
    try std.testing.expect(s.auto_wrap);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen: origin mode makes cursor positioning relative to scroll region" {
    var s = GridModel.init(6, 10);
    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 2, .bottom = 4 } });
    s.apply(SemanticEvent{ .origin_mode = true });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 1 } });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    try std.testing.expectEqual(@as(u16, 4), s.cursor_row);
}

test "screen: save and restore cursor restores position and wrap" {
    var s = GridModel.init(4, 8);
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

test "screen: cursor_up moves row" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 5;
    s.apply(SemanticEvent{ .cursor_up = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
}

test "screen: cursor_up clamped at 0" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 1;
    s.apply(SemanticEvent{ .cursor_up = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
}

test "screen: cursor_down clamped at last row" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 20;
    s.apply(SemanticEvent{ .cursor_down = 10 });
    try std.testing.expectEqual(@as(u16, 23), s.cursor_row);
}

test "screen: cursor_forward clamped at last col" {
    var s = GridModel.init(24, 80);
    s.cursor_col = 75;
    s.apply(SemanticEvent{ .cursor_forward = 10 });
    try std.testing.expectEqual(@as(u16, 79), s.cursor_col);
}

test "screen: cursor_position absolute move" {
    var s = GridModel.init(24, 80);
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 10, .col = 40 } });
    try std.testing.expectEqual(@as(u16, 10), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 40), s.cursor_col);
}

test "screen: cursor_next_line moves row and resets column" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 5;
    s.cursor_col = 40;
    s.apply(SemanticEvent{ .cursor_next_line = 3 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: cursor_prev_line moves row and resets column" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 5;
    s.cursor_col = 40;
    s.apply(SemanticEvent{ .cursor_prev_line = 3 });
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: cursor_horizontal_absolute updates column only" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 12;
    s.cursor_col = 20;
    s.apply(SemanticEvent{ .cursor_horizontal_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 12), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), s.cursor_col);
}

test "screen: cursor_vertical_absolute updates row only" {
    var s = GridModel.init(24, 80);
    s.cursor_row = 12;
    s.cursor_col = 20;
    s.apply(SemanticEvent{ .cursor_vertical_absolute = 7 });
    try std.testing.expectEqual(@as(u16, 7), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 20), s.cursor_col);
}

test "screen: zero rows/cols do not panic" {
    var s = GridModel.init(0, 0);
    s.apply(SemanticEvent{ .cursor_down = 5 });
    s.apply(SemanticEvent{ .cursor_forward = 5 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
}

test "screen: write_text stores bytes in cells" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abc" });
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
}

test "screen: sgr applies ansi and 256-color attrs to written cells" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .sgr = .{ .params = .{ 38, 5, 196 } ++ [_]i32{0} ** 13, .separators = [_]u8{0} ** 16, .param_count = 3 } });
    s.apply(SemanticEvent{ .sgr = .{ .params = .{ 48, 5, 23 } ++ [_]i32{0} ** 13, .separators = [_]u8{0} ** 16, .param_count = 3 } });
    s.apply(SemanticEvent{ .write_text = "X" });

    const cell = s.cellInfoAt(0, 0);
    try std.testing.expectEqual(@as(u21, 'X'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u8, 255), cell.attrs.fg.r);
    try std.testing.expectEqual(@as(u8, 0), cell.attrs.fg.g);
    try std.testing.expectEqual(@as(u8, 0), cell.attrs.fg.b);
    try std.testing.expectEqual(@as(u8, 0), cell.attrs.bg.r);
    try std.testing.expectEqual(@as(u8, 51), cell.attrs.bg.g);
    try std.testing.expectEqual(@as(u8, 51), cell.attrs.bg.b);
}

test "screen: sgr reset restores default attrs for later writes" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .sgr = .{ .params = .{31} ++ [_]i32{0} ** 15, .separators = [_]u8{0} ** 16, .param_count = 1 } });
    s.apply(SemanticEvent{ .write_text = "A" });
    s.apply(SemanticEvent{ .sgr = .{ .params = .{0} ++ [_]i32{0} ** 15, .separators = [_]u8{0} ** 16, .param_count = 1 } });
    s.apply(SemanticEvent{ .write_text = "B" });

    const a = s.cellInfoAt(0, 0);
    const b = s.cellInfoAt(0, 1);
    try std.testing.expectEqual(@as(u8, 170), a.attrs.fg.r);
    try std.testing.expectEqual(grid.default_fg.r, b.attrs.fg.r);
    try std.testing.expectEqual(grid.default_fg.g, b.attrs.fg.g);
    try std.testing.expectEqual(grid.default_fg.b, b.attrs.fg.b);
}

test "screen: kitty colon SGR sets underline styles without stealing semicolon params" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 4);
    defer s.deinit(gpa);

    var colon = [_]u8{0} ** 16;
    colon[1] = ':';
    s.apply(SemanticEvent{ .sgr = .{ .params = .{ 4, 3 } ++ [_]i32{0} ** 14, .separators = colon, .param_count = 2 } });
    s.apply(SemanticEvent{ .write_text = "C" });

    var semicolon = [_]u8{0} ** 16;
    semicolon[1] = ';';
    s.apply(SemanticEvent{ .sgr = .{ .params = .{ 4, 5 } ++ [_]i32{0} ** 14, .separators = semicolon, .param_count = 2 } });
    s.apply(SemanticEvent{ .write_text = "S" });

    const curly = s.cellInfoAt(0, 0);
    const straight = s.cellInfoAt(0, 1);
    try std.testing.expect(curly.attrs.underline);
    try std.testing.expectEqual(grid.UnderlineStyle.curly, curly.attrs.underline_style);
    try std.testing.expect(straight.attrs.underline);
    try std.testing.expectEqual(grid.UnderlineStyle.straight, straight.attrs.underline_style);
    try std.testing.expect(straight.attrs.blink);
}

test "screen: kitty underline color SGR sets and resets color" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .sgr = .{ .params = .{ 4, 58, 2, 1, 2, 3 } ++ [_]i32{0} ** 10, .separators = [_]u8{0} ** 16, .param_count = 6 } });
    s.apply(SemanticEvent{ .write_text = "C" });
    s.apply(SemanticEvent{ .sgr = .{ .params = .{59} ++ [_]i32{0} ** 15, .separators = [_]u8{0} ** 16, .param_count = 1 } });
    s.apply(SemanticEvent{ .write_text = "R" });

    const colored = s.cellInfoAt(0, 0);
    const reset = s.cellInfoAt(0, 1);
    try std.testing.expect(colored.attrs.underline);
    try std.testing.expectEqual(@as(u8, 1), colored.attrs.underline_color.r);
    try std.testing.expectEqual(@as(u8, 2), colored.attrs.underline_color.g);
    try std.testing.expectEqual(@as(u8, 3), colored.attrs.underline_color.b);
    try std.testing.expect(reset.attrs.underline);
    try std.testing.expectEqual(grid.Color{ .r = 0, .g = 0, .b = 0, .a = 0 }, reset.attrs.underline_color);
}

test "screen: write_text wraps to next row after filled column" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcdefgh" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'h'), s.cellAt(1, 2));
}

test "screen: exact line fill leaves cursor at last column until next write" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcde" });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 4));
    s.apply(SemanticEvent{ .write_text = "f" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(1, 0));
}

test "screen: wrap at bottom scrolls cell buffer up" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abcde" });
    s.apply(SemanticEvent{ .write_text = "fghij" });
    s.apply(SemanticEvent{ .write_text = "k" });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'j'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'k'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
}

test "screen: disabled auto_wrap keeps writing at last column" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 5);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .auto_wrap = false });
    s.apply(SemanticEvent{ .write_text = "abcdefg" });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'd'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'g'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
}

test "screen: line_feed advances row" {
    var s = GridModel.init(4, 10);
    s.cursor_row = 1;
    s.apply(SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_row);
}

test "screen: carriage_return resets col" {
    var s = GridModel.init(4, 10);
    s.cursor_col = 7;
    s.apply(SemanticEvent.carriage_return);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: backspace moves col left" {
    var s = GridModel.init(4, 10);
    s.cursor_col = 5;
    s.apply(SemanticEvent.backspace);
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen: horizontal_tab advances to next default tab stop" {
    var s = GridModel.init(4, 20);
    s.cursor_col = 3;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor_col);
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 16), s.cursor_col);
}

test "screen: horizontal_tab clamps at last column" {
    var s = GridModel.init(4, 20);
    s.cursor_col = 17;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 19), s.cursor_col);
}

test "screen: horizontal_tab_forward advances by requested stop count" {
    var s = GridModel.init(4, 20);
    s.cursor_col = 1;
    s.apply(SemanticEvent{ .horizontal_tab_forward = 2 });
    try std.testing.expectEqual(@as(u16, 16), s.cursor_col);
}

test "screen: horizontal_tab_forward clamps at last column" {
    var s = GridModel.init(4, 20);
    s.cursor_col = 17;
    s.apply(SemanticEvent{ .horizontal_tab_forward = 2 });
    try std.testing.expectEqual(@as(u16, 19), s.cursor_col);
}

test "screen: horizontal_tab_back moves to previous default tab stop" {
    var s = GridModel.init(4, 20);
    s.cursor_col = 17;
    s.apply(SemanticEvent{ .horizontal_tab_back = 2 });
    try std.testing.expectEqual(@as(u16, 8), s.cursor_col);
}

test "screen: horizontal_tab_back clamps at column zero" {
    var s = GridModel.init(4, 20);
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .horizontal_tab_back = 2 });
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: HTS sets custom tab stop and TBC clears it" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 20);
    defer s.deinit(gpa);

    s.cursor_col = 5;
    s.apply(SemanticEvent.horizontal_tab_set);
    s.cursor_col = 3;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 5), s.cursor_col);

    s.apply(SemanticEvent.tab_clear_current);
    s.cursor_col = 3;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor_col);
}

test "screen: TBC all clears defaults until reset restores them" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 20);
    defer s.deinit(gpa);

    s.apply(SemanticEvent.tab_clear_all);
    s.cursor_col = 3;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 19), s.cursor_col);

    s.reset();
    s.cursor_col = 3;
    s.apply(SemanticEvent.horizontal_tab);
    try std.testing.expectEqual(@as(u16, 8), s.cursor_col);
}

test "screen: cellAt out of bounds returns 0" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(10, 0));
}

test "screen: erase_line mode 0 clears from cursor to end of line" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "helloworld" });
    s.cursor_col = 5;
    s.apply(SemanticEvent{ .erase_line = 0 });
    try std.testing.expectEqual(@as(u21, 'h'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 9));
    try std.testing.expectEqual(@as(u16, 5), s.cursor_col);
}

test "screen: erase_line mode 1 clears from start to cursor" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "helloworld" });
    s.cursor_col = 4;
    s.apply(SemanticEvent{ .erase_line = 1 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'w'), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen: erase_line mode 2 clears full line" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "helloworld" });
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .erase_line = 2 });
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, @intCast(i)));
    }
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
}

test "screen: erase_display mode 0 clears from cursor to end of screen" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor_row = 0;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "AAAAA" });
    s.cursor_row = 1;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "BBBBB" });
    s.cursor_row = 2;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "CCCCC" });
    s.cursor_row = 1;
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_display = 0 });
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: erase_display mode 1 clears from start to cursor" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor_row = 0;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "AAAAA" });
    s.cursor_row = 1;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "BBBBB" });
    s.cursor_row = 2;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "CCCCC" });
    s.cursor_row = 1;
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_display = 1 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: erase_display mode 2 clears entire screen" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor_row = 1;
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .write_text = "AB" });
    s.cursor_row = 1;
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_display = 2 });
    for (0..3) |r| {
        for (0..5) |c_| {
            try std.testing.expectEqual(@as(u21, 0), s.cellAt(@intCast(r), @intCast(c_)));
        }
    }
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: erase ops no-op without cell buffer" {
    var s = GridModel.init(4, 10);
    s.cursor_col = 3;
    s.apply(SemanticEvent{ .erase_line = 2 });
    s.apply(SemanticEvent{ .erase_display = 2 });
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);
}

test "screen: initWithCells has no history by default" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 0), s.history_capacity);
    try std.testing.expect(s.history == null);
}

test "screen: initWithCellsAndHistory allocates bounded history" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 4, 10, 100);
    defer s.deinit(gpa);
    try std.testing.expectEqual(@as(u16, 100), s.history_capacity);
    try std.testing.expect(s.history != null);
    try std.testing.expectEqual(@as(usize, 0), s.history_count);
}

test "screen: scrollUp captures row to history" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 2, 10, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "abc" });
    s.cursor_row = 1;
    s.cursor_col = 0;
    s.apply(SemanticEvent{ .write_text = "xyz" });
    s.cursor_col = 0;
    s.apply(SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(usize, 1), s.history_count);
    const h = s.history.?;
    try std.testing.expectEqual(@as(u21, 'a'), @as(u21, @intCast(h[0].codepoint)));
    try std.testing.expectEqual(@as(u21, 'b'), @as(u21, @intCast(h[1].codepoint)));
    try std.testing.expectEqual(@as(u21, 'c'), @as(u21, @intCast(h[2].codepoint)));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'z'), s.cellAt(0, 2));
}

test "screen: DECSTBM and IL shift rows down inside region" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "AAAA" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "BBBB" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "CCCC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "DDDD" });

    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 3 } });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .insert_lines = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(3, 0));
}

test "screen: DECSTBM and DL shift rows up inside region" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "AAAA" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "BBBB" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "CCCC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "DDDD" });

    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 3 } });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .delete_lines = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(3, 0));
}

test "screen: DCH deletes chars and clears tail" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 8);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "reset" });
    s.apply(SemanticEvent.backspace);
    s.apply(SemanticEvent.backspace);
    s.apply(SemanticEvent.backspace);
    s.apply(SemanticEvent.backspace);
    s.apply(SemanticEvent.backspace);
    s.apply(SemanticEvent{ .delete_chars = 3 });
    s.apply(SemanticEvent{ .write_text = "ll" });

    try std.testing.expectEqual(@as(u21, 'l'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 4));
}

test "screen: ICH inserts blanks and shifts suffix right" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 8);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "abcdef" });
    s.cursor_col = 2;
    s.current_attrs.bg = .{ .r = 40, .g = 44, .b = 52 };
    s.apply(SemanticEvent{ .insert_chars = 2 });

    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'd'), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 6));
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(0, 7));
    const blank = s.cellInfoAt(0, 2);
    try std.testing.expectEqual(@as(u8, 40), blank.attrs.bg.r);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}

test "screen: REP repeats last written codepoint" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 6);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "A" });
    s.apply(SemanticEvent{ .repeat_preceding = 3 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u16, 4), s.cursor_col);
}

test "screen: REP is no-op without preceding codepoint" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .repeat_preceding = 3 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), s.cursor_col);
}

test "screen: RI scrolls region down at top margin" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "AAAA" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "BBBB" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "CCCC" });

    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent.reverse_index);

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(2, 0));
}

test "screen: cursor_style updates cursor presentation" {
    var s = GridModel.init(4, 4);

    s.apply(SemanticEvent{ .cursor_style = .{ .shape = .bar, .blink = false } });
    try std.testing.expectEqual(.bar, s.cursor_style.shape);
    try std.testing.expect(!s.cursor_style.blink);

    s.apply(SemanticEvent{ .cursor_style = .{ .shape = .underline, .blink = true } });
    try std.testing.expectEqual(.underline, s.cursor_style.shape);
    try std.testing.expect(s.cursor_style.blink);
}

test "screen: erase_line uses current background for empty cells" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 5);
    defer s.deinit(gpa);

    s.current_attrs.bg = .{ .r = 40, .g = 44, .b = 52 };
    s.apply(SemanticEvent{ .write_text = "~" });
    s.apply(SemanticEvent{ .erase_line = 0 });

    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 1));
    const cell = s.cellInfoAt(0, 1);
    try std.testing.expectEqual(@as(u8, 40), cell.attrs.bg.r);
    try std.testing.expectEqual(@as(u8, 44), cell.attrs.bg.g);
    try std.testing.expectEqual(@as(u8, 52), cell.attrs.bg.b);
}

test "screen: ECH uses current background without moving cursor" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 8);
    defer s.deinit(gpa);

    s.current_attrs.bg = .{ .r = 40, .g = 44, .b = 52 };
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .erase_chars = 3 });

    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
    var col: u16 = 2;
    while (col < 5) : (col += 1) {
        const cell = s.cellInfoAt(0, col);
        try std.testing.expectEqual(@as(u21, 0), @as(u21, @intCast(cell.codepoint)));
        try std.testing.expectEqual(@as(u8, 40), cell.attrs.bg.r);
        try std.testing.expectEqual(@as(u8, 44), cell.attrs.bg.g);
        try std.testing.expectEqual(@as(u8, 52), cell.attrs.bg.b);
    }
}

test "screen: SL shifts scroll-region rows left" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "ABCDE" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "FGHIJ" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "KLMNO" });

    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    s.apply(SemanticEvent{ .shift_left_columns = 2 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'H'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'I'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 4));
    try std.testing.expectEqual(@as(u21, 'M'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'N'), s.cellAt(2, 1));
    try std.testing.expectEqual(@as(u21, 'O'), s.cellAt(2, 2));
}

test "screen: SR respects horizontal margins" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 5);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "ABCDE" });
    s.apply(SemanticEvent{ .left_right_margin_mode = true });
    s.apply(SemanticEvent{ .set_left_right_margins = .{ .left = 1, .right = 3 } });
    s.apply(SemanticEvent{ .shift_right_columns = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(0, 4));
}

test "screen: DECST8C restores default tab stops" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 1, 20);
    defer s.deinit(gpa);
    s.cursor_col = 8;
    s.apply(.tab_clear_current);
    s.apply(.tab_clear_all);
    try std.testing.expect(!s.tabStopAt(8));
    try std.testing.expect(!s.tabStopAt(16));
    s.apply(.reset_default_tab_stops);
    try std.testing.expect(s.tabStopAt(8));
    try std.testing.expect(s.tabStopAt(16));
    try std.testing.expect(!s.tabStopAt(4));
}

test "screen: DECSCA protects cells from selective erase" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "A" });
    s.apply(SemanticEvent{ .character_protection = true });
    s.apply(SemanticEvent{ .write_text = "B" });
    s.apply(SemanticEvent{ .character_protection = false });
    s.apply(SemanticEvent{ .write_text = "CDEF" });

    s.cursor_row = 1;
    s.cursor_col = 2;
    s.apply(SemanticEvent{ .selective_erase_display = 2 });

    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
}

test "screen: DECERA clips rectangle to viewport" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "ABC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "DEF" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "GHI" });

    s.apply(SemanticEvent{ .rect_erase = .{ .top = 0, .left = 0, .bottom = 1, .right = 1 } });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'F'), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'I'), s.cellAt(2, 2));
}

test "screen: DECSERA preserves protected cells" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "ABC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "D" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 1 } });
    s.apply(SemanticEvent{ .character_protection = true });
    s.apply(SemanticEvent{ .write_text = "E" });
    s.apply(SemanticEvent{ .character_protection = false });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 2 } });
    s.apply(SemanticEvent{ .write_text = "FGHI" });

    s.apply(SemanticEvent{ .rect_selective_erase = .{ .top = 0, .left = 0, .bottom = 2, .right = 2 } });
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 2));
}

test "screen: DECFRA fills clipped rectangle with current attrs" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.current_attrs.bg = .{ .r = 40, .g = 44, .b = 52 };
    s.apply(SemanticEvent{ .rect_fill = .{ .area = .{ .top = 1, .left = 1, .bottom = 9, .right = 9 }, .ch = 'X' } });

    try std.testing.expectEqual(@as(u21, 'X'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'X'), s.cellAt(2, 2));
    const cell = s.cellInfoAt(1, 1);
    try std.testing.expectEqual(@as(u8, 40), cell.attrs.bg.r);
}

test "screen: DECCRA copies overlapping rectangle through temporary buffer" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 7);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "ABC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "DEF" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "GHI" });
    s.apply(SemanticEvent{ .rect_copy = .{
        .area = .{ .top = 0, .left = 0, .bottom = 2, .right = 2 },
        .source_page = 1,
        .dest_top = 0,
        .dest_left = 3,
        .dest_page = 1,
    } });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 'G'), s.cellAt(2, 3));
}

test "screen: DECIC and DECDC shift columns inside scroll region" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "ABCDE" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "FGHIJ" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "KLMNO" });

    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    s.cursor_col = 1;
    s.current_attrs.bg = .{ .r = 40, .g = 44, .b = 52 };
    s.apply(SemanticEvent{ .insert_columns = 2 });

    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'G'), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 1));

    s.apply(SemanticEvent{ .delete_columns = 1 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'G'), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'L'), s.cellAt(2, 2));
}

test "screen: DECCARA stream mode spans full middle rows" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "ABCDEFGHI" });
    s.apply(SemanticEvent{ .rect_attrs_change = .{
        .area = .{ .top = 0, .left = 1, .bottom = 2, .right = 1 },
        .attrs = .{ .params = .{1} ++ [_]u16{0} ** 15, .param_count = 1 },
        .reverse = false,
    } });

    try std.testing.expect(!s.cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(s.cellInfoAt(0, 1).attrs.bold);
    try std.testing.expect(s.cellInfoAt(0, 2).attrs.bold);
    try std.testing.expect(s.cellInfoAt(1, 0).attrs.bold);
    try std.testing.expect(s.cellInfoAt(1, 2).attrs.bold);
    try std.testing.expect(s.cellInfoAt(2, 0).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(2, 2).attrs.bold);
}

test "screen: DECSACE rectangle mode constrains DECCARA to exact bounds" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "ABCDEFGHI" });
    s.apply(SemanticEvent{ .attr_change_extent_rect = true });
    s.apply(SemanticEvent{ .rect_attrs_change = .{
        .area = .{ .top = 0, .left = 0, .bottom = 1, .right = 1 },
        .attrs = .{ .params = .{1} ++ [_]u16{0} ** 15, .param_count = 1 },
        .reverse = false,
    } });

    try std.testing.expect(s.cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(s.cellInfoAt(1, 1).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(0, 2).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(1, 2).attrs.bold);
}

test "screen: DECRARA toggles supported attrs" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 2, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .sgr = .{ .params = .{4} ++ [_]i32{0} ** 15, .separators = [_]u8{0} ** 16, .param_count = 1 } });
    s.apply(SemanticEvent{ .write_text = "ABCDEF" });
    s.apply(SemanticEvent{ .rect_attrs_change = .{
        .area = .{ .top = 0, .left = 0, .bottom = 1, .right = 1 },
        .attrs = .{ .params = .{ 1, 4 } ++ [_]u16{0} ** 14, .param_count = 2 },
        .reverse = true,
    } });

    try std.testing.expect(s.cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(0, 0).attrs.underline);
    try std.testing.expect(s.cellInfoAt(1, 1).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(1, 1).attrs.underline);
    try std.testing.expect(s.cellInfoAt(1, 2).attrs.underline);
}

test "screen: DECLRMM and DECSLRM wrap inside horizontal margins" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .left_right_margin_mode = true });
    s.apply(SemanticEvent{ .set_left_right_margins = .{ .left = 1, .right = null } });
    s.apply(SemanticEvent{ .write_text = "ABCDEFG" });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'F'), s.cellAt(2, 1));
    try std.testing.expectEqual(@as(u21, 'G'), s.cellAt(2, 2));
}

test "screen: DECOM with DECSLRM makes cursor addressing margin-relative" {
    var s = GridModel.init(4, 4);
    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    s.apply(SemanticEvent{ .origin_mode = true });
    s.apply(SemanticEvent{ .left_right_margin_mode = true });
    s.apply(SemanticEvent{ .set_left_right_margins = .{ .left = 1, .right = 2 } });

    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
}

test "screen: SU scrolls only within configured region" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCells(gpa, 4, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "AAAA" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "BBBB" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "CCCC" });
    s.apply(SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    s.apply(SemanticEvent{ .write_text = "DDDD" });

    s.apply(SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 3 } });
    s.apply(SemanticEvent{ .scroll_up_lines = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(3, 0));
}

test "screen: history capacity limits with wraparound" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 2, 2, 2);
    defer s.deinit(gpa);
    var row_num: u21 = '1';
    var i: u16 = 0;
    while (i < 5) : (i += 1) {
        s.cursor_col = 0;
        s.cursor_row = 0;
        for (0..2) |_| {
            s.apply(SemanticEvent{ .write_codepoint = row_num });
        }
        if (i < 4) {
            s.cursor_row = 1;
            s.apply(SemanticEvent.line_feed);
        }
        row_num += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), s.history_count);
    try std.testing.expectEqual(@as(u21, '4'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, '4'), s.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, '3'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, '3'), s.historyRowAt(1, 1));
}

test "screen: reset does not truncate history" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 2, 5, 10);
    defer s.deinit(gpa);
    s.apply(SemanticEvent{ .write_text = "test1" });
    s.cursor_row = 1;
    s.apply(SemanticEvent.line_feed);
    try std.testing.expectEqual(@as(usize, 1), s.history_count);
    s.reset();
    try std.testing.expectEqual(@as(usize, 1), s.history_count);
}

test "screen: ED 3 clears scrollback history" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 2, 4, 8);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "AAAA\nBBBB\nCCCC" });
    try std.testing.expect(s.historyCount() > 0);
    s.apply(SemanticEvent{ .erase_display = 3 });
    try std.testing.expectEqual(@as(usize, 0), s.historyCount());
}

test "screen: row-only resize preserves live bottom and restores from history" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 4, 4, 8);
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

    try std.testing.expectEqual(@as(usize, 2), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'B'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'P'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);

    try s.resize(gpa, 4, 4);

    try std.testing.expectEqual(@as(usize, 0), s.historyCount());
    try std.testing.expectEqual(@as(u16, 8), s.historyCapacity());
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'P'), s.cellAt(3, 0));
    try std.testing.expectEqual(@as(u16, 3), s.cursor_row);
}

test "screen: column resize reflows wrapped content into history and viewport" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 2, 4, 8);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "ABCDEFGHIJ" });

    try std.testing.expectEqual(@as(usize, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(0, 3));

    try s.resize(gpa, 1, 5);

    try std.testing.expectEqual(@as(usize, 1), s.historyCount());
    try std.testing.expectEqual(@as(u16, 8), s.historyCapacity());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'E'), s.historyRowAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'F'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(0, 4));

    try s.resize(gpa, 2, 4);

    try std.testing.expectEqual(@as(usize, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.historyRowAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'H'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'I'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'J'), s.cellAt(1, 1));
}

test "screen: column resize preserves exact-fill cursor wrap state" {
    const gpa = std.testing.allocator;
    var s = try GridModel.initWithCellsAndHistory(gpa, 1, 4, 4);
    defer s.deinit(gpa);

    s.apply(SemanticEvent{ .write_text = "ABCD" });

    try std.testing.expect(s.wrap_pending);
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), s.cursor_col);

    try s.resize(gpa, 1, 2);

    try std.testing.expectEqual(@as(usize, 1), s.historyCount());
    try std.testing.expectEqual(@as(u21, 'A'), s.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.historyRowAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u16, 0), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor_col);
    try std.testing.expect(s.wrap_pending);
}
