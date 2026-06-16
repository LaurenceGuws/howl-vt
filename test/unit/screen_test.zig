const std = @import("std");
const screen_mod = @import("../../src/screen.zig");
const screen_apply = @import("../../src/screen/apply.zig");
const erase = @import("../../src/screen/erase.zig");
const parser_mod = @import("../../src/parser.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const EraseMode = erase.EraseMode;
const SemanticEvent = screen_apply.ScreenAction;
const csi_max_params = parser_mod.max_params;

fn apply(screen: *Screen, event: SemanticEvent) void {
    screen.applyScreen(event);
}

fn emptySeparators() parser_mod.CsiSeparatorList {
    return parser_mod.CsiSeparatorList.initEmpty();
}

fn colonSeparator(after_param_idx: u8) parser_mod.CsiSeparatorList {
    var separators = parser_mod.CsiSeparatorList.initEmpty();
    separators.set(@intCast(after_param_idx));
    return separators;
}

test "screen: erase_line mode 0 clears from cursor to end of line" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "helloworld" });
    s.cursor.setColByClient(5);
    apply(&s, SemanticEvent{ .erase_line = .cursor_to_end });
    try std.testing.expectEqual(@as(u21, 'h'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 9));
    try std.testing.expectEqual(@as(u16, 5), s.cursor.col);
}

test "screen: erase_line mode 1 clears from start to cursor" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "helloworld" });
    s.cursor.setColByClient(4);
    apply(&s, SemanticEvent{ .erase_line = .start_to_cursor });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'w'), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u16, 4), s.cursor.col);
}

test "screen: erase_line mode 2 clears full line" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 10);
    defer s.deinit(gpa);
    apply(&s, SemanticEvent{ .write_text = "helloworld" });
    s.cursor.setColByClient(3);
    apply(&s, SemanticEvent{ .erase_line = .all });
    for (0..10) |i| {
        try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, @intCast(i)));
    }
    try std.testing.expectEqual(@as(u16, 3), s.cursor.col);
}

test "screen: erase_display mode 0 clears from cursor to end of screen" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor.setPositionByClient(0, 0);
    apply(&s, SemanticEvent{ .write_text = "AAAAA" });
    s.cursor.setPositionByClient(1, 0);
    apply(&s, SemanticEvent{ .write_text = "BBBBB" });
    s.cursor.setPositionByClient(2, 0);
    apply(&s, SemanticEvent{ .write_text = "CCCCC" });
    s.cursor.setPositionByClient(1, 2);
    apply(&s, SemanticEvent{ .erase_display = .cursor_to_end });
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor.col);
}

test "screen: erase_display mode 1 clears from start to cursor" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor.setPositionByClient(0, 0);
    apply(&s, SemanticEvent{ .write_text = "AAAAA" });
    s.cursor.setPositionByClient(1, 0);
    apply(&s, SemanticEvent{ .write_text = "BBBBB" });
    s.cursor.setPositionByClient(2, 0);
    apply(&s, SemanticEvent{ .write_text = "CCCCC" });
    s.cursor.setPositionByClient(1, 2);
    apply(&s, SemanticEvent{ .erase_display = .start_to_cursor });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor.col);
}

test "screen: erase_display mode 2 clears entire screen" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);
    s.cursor.setPositionByClient(1, 2);
    apply(&s, SemanticEvent{ .write_text = "AB" });
    s.cursor.setPositionByClient(1, 2);
    apply(&s, SemanticEvent{ .erase_display = .all });
    for (0..3) |r| {
        for (0..5) |c_| {
            try std.testing.expectEqual(@as(u21, 0), s.cellAt(@intCast(r), @intCast(c_)));
        }
    }
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor.col);
}

test "screen: erase ops no-op without cell buffer" {
    var s = Grid.init(4, 10);
    s.cursor.setColByClient(3);
    apply(&s, SemanticEvent{ .erase_line = EraseMode.all });
    apply(&s, SemanticEvent{ .erase_display = EraseMode.all });
    try std.testing.expectEqual(@as(u16, 3), s.cursor.col);
}

test "screen: DECSTBM and IL shift rows down inside region" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "AAAA" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "BBBB" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "CCCC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "DDDD" });

    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 3 } });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .insert_lines = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(3, 0));
}

test "screen: DECSTBM and DL shift rows up inside region" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "AAAA" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "BBBB" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "CCCC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "DDDD" });

    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 3 } });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .delete_lines = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(3, 0));
}

test "screen: DCH deletes chars and clears tail" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 8);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "reset" });
    apply(&s, SemanticEvent.backspace);
    apply(&s, SemanticEvent.backspace);
    apply(&s, SemanticEvent.backspace);
    apply(&s, SemanticEvent.backspace);
    apply(&s, SemanticEvent.backspace);
    apply(&s, SemanticEvent{ .delete_chars = 3 });
    apply(&s, SemanticEvent{ .write_text = "ll" });

    try std.testing.expectEqual(@as(u21, 'l'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 4));
}

test "screen: ICH inserts blanks and shifts suffix right" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 8);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "abcdef" });
    s.cursor.setColByClient(2);
    s.current_attrs.bg = Grid.Color.rgbComponents(40, 44, 52);
    apply(&s, SemanticEvent{ .insert_chars = 2 });

    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'd'), s.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 'e'), s.cellAt(0, 6));
    try std.testing.expectEqual(@as(u21, 'f'), s.cellAt(0, 7));
    const blank = s.cellInfoAt(0, 2);
    try std.testing.expectEqual(Grid.Color.rgbComponents(40, 44, 52), blank.attrs.bg);
    try std.testing.expectEqual(@as(u16, 2), s.cursor.col);
}

test "screen: REP repeats last written codepoint" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 6);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "A" });
    apply(&s, SemanticEvent{ .repeat_preceding = 3 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u16, 4), s.cursor.col);
}

test "screen: REP is no-op without preceding codepoint" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .repeat_preceding = 3 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), s.cursor.col);
}

test "screen: RI scrolls region down at top margin" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "AAAA" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "BBBB" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "CCCC" });

    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent.reverse_index);

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(2, 0));
}

test "screen: erase_line uses current background for empty cells" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 5);
    defer s.deinit(gpa);

    s.current_attrs.bg = Grid.Color.rgbComponents(40, 44, 52);
    apply(&s, SemanticEvent{ .write_text = "~" });
    apply(&s, SemanticEvent{ .erase_line = .cursor_to_end });

    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 1));
    const cell = s.cellInfoAt(0, 1);
    try std.testing.expectEqual(Grid.Color.rgbComponents(40, 44, 52), cell.attrs.bg);
}

test "screen: ECH uses current background without moving cursor" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 1, 8);
    defer s.deinit(gpa);

    s.current_attrs.bg = Grid.Color.rgbComponents(40, 44, 52);
    s.cursor.setColByClient(2);
    apply(&s, SemanticEvent{ .erase_chars = 3 });

    try std.testing.expectEqual(@as(u16, 2), s.cursor.col);
    var col: u16 = 2;
    while (col < 5) : (col += 1) {
        const cell = s.cellInfoAt(0, col);
        try std.testing.expectEqual(@as(u21, 0), @as(u21, @intCast(cell.codepoint)));
        try std.testing.expectEqual(Grid.Color.rgbComponents(40, 44, 52), cell.attrs.bg);
    }
}

test "screen: SL shifts scroll-region rows left" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "ABCDE" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "FGHIJ" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "KLMNO" });

    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    apply(&s, SemanticEvent{ .shift_left_columns = 2 });

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
    var s = try Grid.initWithCells(gpa, 1, 5);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "ABCDE" });
    apply(&s, SemanticEvent{ .left_right_margin_mode = true });
    apply(&s, SemanticEvent{ .set_left_right_margins = .{ .left = 1, .right = 3 } });
    apply(&s, SemanticEvent{ .shift_right_columns = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(0, 4));
}

test "screen: DECSCA protects cells from selective erase" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 2, 3);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "A" });
    apply(&s, SemanticEvent{ .character_protection = true });
    apply(&s, SemanticEvent{ .write_text = "B" });
    apply(&s, SemanticEvent{ .character_protection = false });
    apply(&s, SemanticEvent{ .write_text = "CDEF" });

    s.cursor.setPositionByClient(1, 2);
    apply(&s, SemanticEvent{ .selective_erase_display = .all });

    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
}

test "screen: DECERA clips rectangle to viewport" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "ABC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "DEF" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "GHI" });

    apply(&s, SemanticEvent{ .rect_erase = .{ .top = 0, .left = 0, .bottom = 1, .right = 1 } });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'F'), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'I'), s.cellAt(2, 2));
}

test "screen: DECSERA preserves protected cells" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "ABC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "D" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 1 } });
    apply(&s, SemanticEvent{ .character_protection = true });
    apply(&s, SemanticEvent{ .write_text = "E" });
    apply(&s, SemanticEvent{ .character_protection = false });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 2 } });
    apply(&s, SemanticEvent{ .write_text = "FGHI" });

    apply(&s, SemanticEvent{ .rect_selective_erase = .{ .top = 0, .left = 0, .bottom = 2, .right = 2 } });
    try std.testing.expectEqual(@as(u21, 'E'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 2));
}

test "screen: DECFRA fills clipped rectangle with current attrs" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    s.current_attrs.bg = Grid.Color.rgbComponents(40, 44, 52);
    apply(&s, SemanticEvent{ .rect_fill = .{ .area = .{ .top = 1, .left = 1, .bottom = 9, .right = 9 }, .ch = 'X' } });

    try std.testing.expectEqual(@as(u21, 'X'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'X'), s.cellAt(2, 2));
    const cell = s.cellInfoAt(1, 1);
    try std.testing.expectEqual(Grid.Color.rgbComponents(40, 44, 52), cell.attrs.bg);
}

test "screen: DECCRA copies overlapping rectangle through temporary buffer" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 7);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "ABC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "DEF" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "GHI" });
    apply(&s, SemanticEvent{ .rect_copy = .{
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
    var s = try Grid.initWithCells(gpa, 3, 5);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "ABCDE" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "FGHIJ" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "KLMNO" });

    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    s.cursor.setColByClient(1);
    s.current_attrs.bg = Grid.Color.rgbComponents(40, 44, 52);
    apply(&s, SemanticEvent{ .insert_columns = 2 });

    try std.testing.expectEqual(@as(u21, 'B'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'G'), s.cellAt(1, 3));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(2, 1));

    apply(&s, SemanticEvent{ .delete_columns = 1 });
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'G'), s.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 'L'), s.cellAt(2, 2));
}

test "screen: DECCARA stream mode spans full middle rows" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "ABCDEFGHI" });
    apply(&s, SemanticEvent{ .rect_attrs_change = .{
        .area = .{ .top = 0, .left = 1, .bottom = 2, .right = 1 },
        .attrs = .{ .params = .{1} ++ [_]u16{0} ** (csi_max_params - 1), .param_count = 1 },
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
    var s = try Grid.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .write_text = "ABCDEFGHI" });
    apply(&s, SemanticEvent{ .attr_change_extent_rect = true });
    apply(&s, SemanticEvent{ .rect_attrs_change = .{
        .area = .{ .top = 0, .left = 0, .bottom = 1, .right = 1 },
        .attrs = .{ .params = .{1} ++ [_]u16{0} ** (csi_max_params - 1), .param_count = 1 },
        .reverse = false,
    } });

    try std.testing.expect(s.cellInfoAt(0, 0).attrs.bold);
    try std.testing.expect(s.cellInfoAt(1, 1).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(0, 2).attrs.bold);
    try std.testing.expect(!s.cellInfoAt(1, 2).attrs.bold);
}

test "screen: DECRARA toggles supported attrs" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 2, 3);
    defer s.deinit(gpa);

    const underline_params = [_]i32{4};
    apply(&s, SemanticEvent{ .sgr = .{ .params = underline_params[0..], .separators = emptySeparators() } });
    apply(&s, SemanticEvent{ .write_text = "ABCDEF" });
    apply(&s, SemanticEvent{ .rect_attrs_change = .{
        .area = .{ .top = 0, .left = 0, .bottom = 1, .right = 1 },
        .attrs = .{ .params = .{ 1, 4 } ++ [_]u16{0} ** (csi_max_params - 2), .param_count = 2 },
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
    var s = try Grid.initWithCells(gpa, 3, 3);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .left_right_margin_mode = true });
    apply(&s, SemanticEvent{ .set_left_right_margins = .{ .left = 1, .right = null } });
    apply(&s, SemanticEvent{ .write_text = "ABCDEFG" });

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
    var s = Grid.init(4, 4);
    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 2 } });
    apply(&s, SemanticEvent{ .origin_mode = true });
    apply(&s, SemanticEvent{ .left_right_margin_mode = true });
    apply(&s, SemanticEvent{ .set_left_right_margins = .{ .left = 1, .right = 2 } });

    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.col);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    try std.testing.expectEqual(@as(u16, 1), s.cursor.row);
    try std.testing.expectEqual(@as(u16, 1), s.cursor.col);
}

test "screen: SU scrolls only within configured region" {
    const gpa = std.testing.allocator;
    var s = try Grid.initWithCells(gpa, 4, 4);
    defer s.deinit(gpa);

    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 0, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "AAAA" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 1, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "BBBB" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 2, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "CCCC" });
    apply(&s, SemanticEvent{ .cursor_position = .{ .row = 3, .col = 0 } });
    apply(&s, SemanticEvent{ .write_text = "DDDD" });

    apply(&s, SemanticEvent{ .set_scroll_region = .{ .top = 1, .bottom = 3 } });
    apply(&s, SemanticEvent{ .scroll_up_lines = 1 });

    try std.testing.expectEqual(@as(u21, 'A'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'C'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'D'), s.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), s.cellAt(3, 0));
}
