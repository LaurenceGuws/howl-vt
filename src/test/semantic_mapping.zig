//! Responsibility: mapping coverage from bridge events to semantic events.
//! Ownership: parser-to-semantic translation correctness tests.
//! Reason: make translation defaults, aliases, and private modes explicit.

const std = @import("std");
const interpret_owner = @import("../interpret.zig");

const Interpret = interpret_owner.Interpret;
const Event = Interpret.Event;
const SemanticEvent = Interpret.SemanticEvent;
const process = Interpret.process;
fn makeStyleChange(final: u8, p0: i32, p1: i32, count: u8) Event {
    var params = [_]i32{0} ** 16;
    params[0] = p0;
    params[1] = p1;
    return Event{ .style_change = .{
        .final = final,
        .params = params,
        .param_count = count,
        .leader = 0,
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
}

fn makeStyleChangeWithIntermediate(final: u8, intermediate: u8) Event {
    const params = [_]i32{0} ** 16;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = intermediate;
    return Event{ .style_change = .{
        .final = final,
        .params = params,
        .param_count = 0,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } };
}

fn makeStyleChangeWithParamAndIntermediate(final: u8, p0: i32, intermediate: u8) Event {
    var params = [_]i32{0} ** 16;
    params[0] = p0;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = intermediate;
    return Event{ .style_change = .{
        .final = final,
        .params = params,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } };
}

fn makePrivateStyleChange(final: u8, params_in: []const i32) Event {
    var params = [_]i32{0} ** 16;
    for (params_in, 0..) |value, idx| params[idx] = value;
    return Event{ .style_change = .{
        .final = final,
        .params = params,
        .param_count = @intCast(params_in.len),
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
}

fn makeEscFinal(final: u8) Event {
    return Event{ .esc_final = final };
}

test "semantic: CUU explicit count" {
    const sem = process(makeStyleChange('A', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.cursor_up);
}

test "semantic: CUU zero param defaults to 1" {
    const sem = process(makeStyleChange('A', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_up);
}

test "semantic: CUD" {
    const sem = process(makeStyleChange('B', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 5), sem.cursor_down);
}

test "semantic: CUD alias 'e'" {
    const sem = process(makeStyleChange('e', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 5), sem.cursor_down);
}

test "semantic: CUD alias 'e' zero param defaults to 1" {
    const sem = process(makeStyleChange('e', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_down);
}

test "semantic: CUF" {
    const sem = process(makeStyleChange('C', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_forward);
}

test "semantic: CUF alias 'a'" {
    const sem = process(makeStyleChange('a', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_forward);
}

test "semantic: CUF alias 'a' zero param defaults to 1" {
    const sem = process(makeStyleChange('a', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_forward);
}

test "semantic: CUB" {
    const sem = process(makeStyleChange('D', 4, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_back);
}

test "semantic: CNL explicit count" {
    const sem = process(makeStyleChange('E', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.cursor_next_line);
}

test "semantic: CNL zero param defaults to 1" {
    const sem = process(makeStyleChange('E', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_next_line);
}

test "semantic: CPL explicit count" {
    const sem = process(makeStyleChange('F', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_prev_line);
}

test "semantic: CPL zero param defaults to 1" {
    const sem = process(makeStyleChange('F', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.cursor_prev_line);
}

test "semantic: CHA explicit column" {
    const sem = process(makeStyleChange('G', 7, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 6), sem.cursor_horizontal_absolute);
}

test "semantic: CHA zero param defaults to column 0" {
    const sem = process(makeStyleChange('G', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_horizontal_absolute);
}

test "semantic: CHA alias backtick explicit column" {
    const sem = process(makeStyleChange('`', 7, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 6), sem.cursor_horizontal_absolute);
}

test "semantic: CHA alias backtick zero param defaults to column 0" {
    const sem = process(makeStyleChange('`', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_horizontal_absolute);
}

test "semantic: VPA explicit row" {
    const sem = process(makeStyleChange('d', 9, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 8), sem.cursor_vertical_absolute);
}

test "semantic: VPA zero param defaults to row 0" {
    const sem = process(makeStyleChange('d', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_vertical_absolute);
}

test "semantic: CHT explicit count" {
    const sem = process(makeStyleChange('I', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.horizontal_tab_forward);
}

test "semantic: CHT zero param defaults to 1" {
    const sem = process(makeStyleChange('I', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.horizontal_tab_forward);
}

test "semantic: CHT large param saturates to u16 max" {
    const sem = process(makeStyleChange('I', 999999, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(std.math.maxInt(u16), sem.horizontal_tab_forward);
}

test "semantic: CBT explicit count" {
    const sem = process(makeStyleChange('Z', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.horizontal_tab_back);
}

test "semantic: CBT zero param defaults to 1" {
    const sem = process(makeStyleChange('Z', 0, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.horizontal_tab_back);
}

test "semantic: CBT large param saturates to u16 max" {
    const sem = process(makeStyleChange('Z', 999999, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(std.math.maxInt(u16), sem.horizontal_tab_back);
}

test "semantic: IL explicit count" {
    const sem = process(makeStyleChange('L', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.insert_lines);
}

test "semantic: DL defaults to one line" {
    const sem = process(makeStyleChange('M', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.delete_lines);
}

test "semantic: DCH explicit count" {
    const sem = process(makeStyleChange('P', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.delete_chars);
}

test "semantic: DCH defaults to one char" {
    const sem = process(makeStyleChange('P', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.delete_chars);
}

test "semantic: ICH explicit count" {
    const sem = process(makeStyleChange('@', 4, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), sem.insert_chars);
}

test "semantic: ICH defaults to one char" {
    const sem = process(makeStyleChange('@', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.insert_chars);
}

test "semantic: REP explicit count" {
    const sem = process(makeStyleChange('b', 4, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), sem.repeat_preceding);
}

test "semantic: REP defaults to one char" {
    const sem = process(makeStyleChange('b', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.repeat_preceding);
}

test "semantic: SU explicit count" {
    const sem = process(makeStyleChange('S', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.scroll_up_lines);
}

test "semantic: SD defaults to one line" {
    const sem = process(makeStyleChange('T', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.scroll_down_lines);
}

test "semantic: DECSTBM captures top and bottom margins" {
    const sem = process(makeStyleChange('r', 2, 5, 2)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.set_scroll_region.top);
    try std.testing.expectEqual(@as(?u16, 4), sem.set_scroll_region.bottom);
}

test "semantic: DECSTBM with omitted bottom resets to viewport bottom" {
    const sem = process(makeStyleChange('r', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.set_scroll_region.top);
    try std.testing.expectEqual(@as(?u16, null), sem.set_scroll_region.bottom);
}

test "semantic: CUP explicit row and col" {
    const sem = process(makeStyleChange('H', 3, 5, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 4), sem.cursor_position.col);
}

test "semantic: CUP no params defaults to origin" {
    const sem = process(makeStyleChange('H', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.row);
    try std.testing.expectEqual(@as(u16, 0), sem.cursor_position.col);
}

test "semantic: unsupported CSI returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(makeStyleChange('Y', 1, 0, 1)));
}

test "semantic: DECSTR maps to reset_screen" {
    const sem = process(makeStyleChangeWithIntermediate('p', '!')) orelse return error.NoEvent;
    try std.testing.expect(sem == .reset_screen);
}

test "semantic: DEC private cursor show maps to cursor_visible true" {
    var params = [_]i32{0} ** 16;
    params[0] = 25;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.cursor_visible);
}

test "semantic: DEC private cursor hide maps to cursor_visible false" {
    var params = [_]i32{0} ** 16;
    params[0] = 25;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(!process(ev).?.cursor_visible);
}

test "semantic: DEC private wrap enable maps to auto_wrap true" {
    var params = [_]i32{0} ** 16;
    params[0] = 7;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.auto_wrap);
}

test "semantic: DEC private origin mode enable maps true" {
    var params = [_]i32{0} ** 16;
    params[0] = 6;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.origin_mode);
}

test "semantic: DEC private wrap disable maps to auto_wrap false" {
    var params = [_]i32{0} ** 16;
    params[0] = 7;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(!process(ev).?.auto_wrap);
}

test "semantic: text event maps to write_text" {
    const sem = process(Event{ .text = "hello" }) orelse return error.NoEvent;
    try std.testing.expectEqualSlices(u8, "hello", sem.write_text);
}

test "semantic: codepoint event maps to write_codepoint" {
    const sem = process(Event{ .codepoint = 0xE9 }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u21, 0xE9), sem.write_codepoint);
}

test "semantic: LF maps to line_feed" {
    const sem = process(Event{ .control = 0x0A }) orelse return error.NoEvent;
    try std.testing.expect(sem == .line_feed);
}

test "semantic: CR maps to carriage_return" {
    const sem = process(Event{ .control = 0x0D }) orelse return error.NoEvent;
    try std.testing.expect(sem == .carriage_return);
}

test "semantic: BS maps to backspace" {
    const sem = process(Event{ .control = 0x08 }) orelse return error.NoEvent;
    try std.testing.expect(sem == .backspace);
}

test "semantic: HT maps to horizontal_tab" {
    const sem = process(Event{ .control = 0x09 }) orelse return error.NoEvent;
    try std.testing.expect(sem == .horizontal_tab);
}

test "semantic: HTS and TBC map to tab stop controls" {
    try std.testing.expect(process(makeEscFinal('H')).? == .horizontal_tab_set);
    try std.testing.expect(process(makeStyleChange('g', 0, 0, 0)).? == .tab_clear_current);
    try std.testing.expect(process(makeStyleChange('g', 3, 0, 1)).? == .tab_clear_all);
}

test "semantic: DECSCA maps protection modes" {
    const protect = process(makeStyleChangeWithParamAndIntermediate('q', 1, '"')) orelse return error.NoEvent;
    try std.testing.expect(protect.character_protection);

    const unprotect = process(makeStyleChangeWithParamAndIntermediate('q', 2, '"')) orelse return error.NoEvent;
    try std.testing.expect(!unprotect.character_protection);
}

test "semantic: DECSED and DECSEL map from private CSI" {
    try std.testing.expectEqual(@as(u2, 2), process(makePrivateStyleChange('J', &.{2})).?.selective_erase_display);
    try std.testing.expectEqual(@as(u2, 1), process(makePrivateStyleChange('K', &.{1})).?.selective_erase_line);
}

test "semantic: rectangular erase fill copy and column ops map" {
    var params = [_]i32{0} ** 16;
    params[0] = 88;
    params[1] = 1;
    params[2] = 2;
    params[3] = 3;
    params[4] = 4;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const fill = process(Event{ .style_change = .{
        .final = 'x',
        .params = params,
        .param_count = 5,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u21, 88), fill.rect_fill.ch);
    try std.testing.expectEqual(@as(u16, 0), fill.rect_fill.area.top);
    try std.testing.expectEqual(@as(u16, 1), fill.rect_fill.area.left);

    params = [_]i32{0} ** 16;
    params[0] = 1;
    params[1] = 1;
    params[2] = 2;
    params[3] = 2;
    params[4] = 1;
    params[5] = 3;
    params[6] = 4;
    params[7] = 1;
    const copy = process(Event{ .style_change = .{
        .final = 'v',
        .params = params,
        .param_count = 8,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), copy.rect_copy.dest_top);
    try std.testing.expectEqual(@as(u16, 3), copy.rect_copy.dest_left);

    intermediates[0] = '\'';
    const insert = process(Event{ .style_change = .{
        .final = '}',
        .params = .{2} ++ [_]i32{0} ** 15,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), insert.insert_columns);

    const delete = process(Event{ .style_change = .{
        .final = '~',
        .params = .{3} ++ [_]i32{0} ** 15,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), delete.delete_columns);
}

test "semantic: rectangular attr ops and margin controls map" {
    var params = [_]i32{0} ** 16;
    params[0] = 1;
    params[1] = 1;
    params[2] = 2;
    params[3] = 2;
    params[4] = 1;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const change = process(Event{ .style_change = .{
        .final = 'r',
        .params = params,
        .param_count = 5,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expect(!change.rect_attrs_change.reverse);
    try std.testing.expectEqual(@as(u16, 1), change.rect_attrs_change.attrs.params[0]);

    const reverse = process(Event{ .style_change = .{
        .final = 't',
        .params = params,
        .param_count = 5,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expect(reverse.rect_attrs_change.reverse);

    intermediates[0] = '*';
    const extent = process(Event{ .style_change = .{
        .final = 'x',
        .params = .{2} ++ [_]i32{0} ** 15,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expect(extent.attr_change_extent_rect);

    const margins = process(makeStyleChange('s', 2, 4, 2)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), margins.set_left_right_margins.left);
    try std.testing.expectEqual(@as(?u16, 3), margins.set_left_right_margins.right);

    try std.testing.expect(process(makePrivateStyleChange('h', &.{69})).?.left_right_margin_mode);
    try std.testing.expect(!process(makePrivateStyleChange('l', &.{69})).?.left_right_margin_mode);
}

test "semantic: VT and FF map to line_feed" {
    try std.testing.expect(process(Event{ .control = 0x0B }).? == .line_feed);
    try std.testing.expect(process(Event{ .control = 0x0C }).? == .line_feed);
}

test "semantic: invalid_sequence returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event.invalid_sequence));
}

test "semantic: OSC title transport returns null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .osc = .{
        .kind = .title,
        .command = @as(?u16, 0),
        .payload = "My Title",
        .terminator = .bel,
    } }));
}

test "semantic: OSC 8 maps to hyperlink set and clear" {
    try std.testing.expectEqualStrings("https://example.com", process(Event{ .osc = .{
        .kind = .hyperlink,
        .command = @as(?u16, 8),
        .payload = ";https://example.com",
        .terminator = .bel,
    } }).?.hyperlink_set);
    try std.testing.expect(process(Event{ .osc = .{
        .kind = .hyperlink,
        .command = @as(?u16, 8),
        .payload = ";",
        .terminator = .bel,
    } }).? == .hyperlink_clear);
}

test "semantic: OSC 52 maps to clipboard set" {
    try std.testing.expectEqualStrings("c;Zm9v", process(Event{ .osc = .{
        .kind = .clipboard,
        .command = @as(?u16, 52),
        .payload = "c;Zm9v",
        .terminator = .bel,
    } }).?.clipboard_set);
}

test "semantic: APC PM and unsupported ESC transport return null" {
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .apc = "kitty" }));
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .pm = "ignored" }));
    try std.testing.expectEqual(@as(?SemanticEvent, null), process(Event{ .esc_final = 'z' }));
}

test "semantic: DCS DECRQSS maps request payload" {
    const sem = process(Event{ .dcs = "$q q" }) orelse return error.NoEvent;
    try std.testing.expectEqualStrings(" q", sem.dcs_request_status);
}

test "semantic: DEC save and restore cursor from ESC finals" {
    try std.testing.expect(process(makeEscFinal('7')).? == .save_cursor);
    try std.testing.expect(process(makeEscFinal('8')).? == .restore_cursor);
}

test "semantic: C1 7-bit ESC aliases map to motion controls" {
    try std.testing.expect(process(makeEscFinal('D')).? == .line_feed);
    try std.testing.expect(process(makeEscFinal('E')).? == .next_line);
    try std.testing.expect(process(makeEscFinal('M')).? == .reverse_index);
}

test "semantic: ESC DECID and RIS aliases" {
    try std.testing.expect(process(makeEscFinal('Z')).? == .primary_device_attributes);
    try std.testing.expect(process(makeEscFinal('c')).? == .reset_screen);
}

test "semantic: ANSI save and restore cursor CSI aliases" {
    try std.testing.expect(process(makeStyleChange('s', 0, 0, 0)).? == .save_cursor);
    try std.testing.expect(process(makeStyleChange('u', 0, 0, 0)).? == .restore_cursor);
}

test "semantic: DECSCUSR maps cursor styles" {
    var sem = process(makeStyleChangeWithParamAndIntermediate('q', 0, ' ')) orelse return error.NoEvent;
    try std.testing.expectEqual(SemanticEvent.CursorShape.block, sem.cursor_style.shape);
    try std.testing.expect(sem.cursor_style.blink);

    sem = process(makeStyleChangeWithParamAndIntermediate('q', 4, ' ')) orelse return error.NoEvent;
    try std.testing.expectEqual(SemanticEvent.CursorShape.underline, sem.cursor_style.shape);
    try std.testing.expect(!sem.cursor_style.blink);

    sem = process(makeStyleChangeWithParamAndIntermediate('q', 5, ' ')) orelse return error.NoEvent;
    try std.testing.expectEqual(SemanticEvent.CursorShape.bar, sem.cursor_style.shape);
    try std.testing.expect(sem.cursor_style.blink);
}

test "semantic: DEC private application cursor enable maps true" {
    var params = [_]i32{0} ** 16;
    params[0] = 1;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.application_cursor_keys);
}

test "semantic: DEC private focus reporting enable maps true" {
    var params = [_]i32{0} ** 16;
    params[0] = 1004;
    const ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.focus_reporting);
}

test "semantic: DEC private bracketed paste disable maps false" {
    var params = [_]i32{0} ** 16;
    params[0] = 2004;
    const ev = Event{ .style_change = .{
        .final = 'l',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(!process(ev).?.bracketed_paste);
}

test "semantic: DEC private mouse tracking mode mappings" {
    var params = [_]i32{0} ** 16;
    params[0] = 9;
    var ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).? == .mouse_tracking_x10);
    params[0] = 1000;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).? == .mouse_tracking_normal);
    params[0] = 1002;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).? == .mouse_tracking_button_event);
    params[0] = 1003;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).? == .mouse_tracking_any_event);
    params[0] = 1006;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).?.mouse_protocol_sgr);
    params[0] = 1005;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).?.mouse_protocol_utf8);
    params[0] = 1015;
    ev.style_change.params = params;
    try std.testing.expect(process(ev).?.mouse_protocol_urxvt);
}

test "semantic: application keypad and modifyOtherKeys mappings" {
    try std.testing.expect(process(makeEscFinal('=')).?.application_keypad);
    try std.testing.expect(!process(makeEscFinal('>')).?.application_keypad);

    var params = [_]i32{0} ** 16;
    params[0] = 66;
    var ev = Event{ .style_change = .{
        .final = 'h',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).?.application_keypad);

    params[0] = 4;
    params[1] = 2;
    ev = Event{ .style_change = .{
        .final = 'm',
        .params = params,
        .param_count = 2,
        .leader = '>',
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expectEqual(@as(i8, 2), process(ev).?.modify_other_keys_set);

    ev.style_change.final = 'n';
    try std.testing.expect(process(ev).? == .modify_other_keys_disable);

    ev.style_change.final = 'm';
    ev.style_change.leader = '?';
    ev.style_change.private = true;
    ev.style_change.param_count = 1;
    try std.testing.expect(process(ev).? == .modify_other_keys_query);
}

test "semantic: DSR 5 maps to device status report" {
    const sem = process(makeStyleChange('n', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .device_status_report);
}

test "semantic: DSR 6 maps to cursor position report" {
    const sem = process(makeStyleChange('n', 6, 0, 1)) orelse return error.NoEvent;
    try std.testing.expect(sem == .cursor_position_report);
}

test "semantic: DECXCPR maps to DEC cursor position report" {
    const sem = process(makePrivateStyleChange('n', &.{6})) orelse return error.NoEvent;
    try std.testing.expect(sem == .dec_cursor_position_report);
}

test "semantic: DEC DSR locator status and type map" {
    const status = process(makePrivateStyleChange('n', &.{55})) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 55), status.dec_device_status_report);

    const kind = process(makePrivateStyleChange('n', &.{56})) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 56), kind.dec_device_status_report);
}

test "semantic: DA maps to primary device attributes" {
    const sem = process(makeStyleChange('c', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expect(sem == .primary_device_attributes);
}

test "semantic: DA2 maps to secondary device attributes" {
    const params = [_]i32{0} ** 16;
    const ev = Event{ .style_change = .{
        .final = 'c',
        .params = params,
        .param_count = 0,
        .leader = '>',
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).? == .secondary_device_attributes);
}

test "semantic: XTVERSION maps to xtversion report" {
    var params = [_]i32{0} ** 16;
    params[0] = 0;
    const ev = Event{ .style_change = .{
        .final = 'q',
        .params = params,
        .param_count = 1,
        .leader = '>',
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).? == .xtversion);
}

test "semantic: XTTITLEPOS maps to title stack report" {
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '#';
    const ev = Event{ .style_change = .{
        .final = 'S',
        .params = [_]i32{0} ** 16,
        .param_count = 0,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } };
    try std.testing.expect(process(ev).? == .xttitlepos);
}

test "semantic: DA3 maps to tertiary device attributes" {
    const params = [_]i32{0} ** 16;
    const ev = Event{ .style_change = .{
        .final = 'c',
        .params = params,
        .param_count = 0,
        .leader = '=',
        .private = false,
        .intermediates = [_]u8{0} ** 4,
        .intermediates_len = 0,
    } };
    try std.testing.expect(process(ev).? == .tertiary_device_attributes);
}

test "semantic: ANSI mode set reset and query map" {
    const set = process(makeStyleChange('h', 4, 20, 2)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 2), set.ansi_mode_set.param_count);
    try std.testing.expectEqual(@as(u16, 4), set.ansi_mode_set.params[0]);
    try std.testing.expectEqual(@as(u16, 20), set.ansi_mode_set.params[1]);

    const reset = process(makeStyleChange('l', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 1), reset.ansi_mode_reset.param_count);
    try std.testing.expectEqual(@as(u16, 2), reset.ansi_mode_reset.params[0]);

    var params = [_]i32{0} ** 16;
    params[0] = 4;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const query = process(Event{ .style_change = .{
        .final = 'p',
        .params = params,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), query.ansi_mode_query);
}

test "semantic: report and checksum requests map" {
    var intermediates = [_]u8{0} ** 4;
    var params = [_]i32{0} ** 16;

    intermediates[0] = '"';
    try std.testing.expect(process(Event{ .style_change = .{
        .final = 'v',
        .params = params,
        .param_count = 0,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }).? == .displayed_extent_report);

    intermediates[0] = '$';
    params[0] = 2;
    const psr = process(Event{ .style_change = .{
        .final = 'w',
        .params = params,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), psr.presentation_state_report);

    intermediates[0] = '#';
    params[0] = 3;
    const xt = process(Event{ .style_change = .{
        .final = 'y',
        .params = params,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), xt.xtchecksum);

    intermediates[0] = '*';
    params = [_]i32{0} ** 16;
    params[0] = 7;
    params[1] = 1;
    params[2] = 2;
    params[3] = 3;
    params[4] = 4;
    params[5] = 5;
    const crc = process(Event{ .style_change = .{
        .final = 'y',
        .params = params,
        .param_count = 6,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 7), crc.rect_checksum_request.request_id);
    try std.testing.expectEqual(@as(u16, 1), crc.rect_checksum_request.page);

    const parm = process(makeStyleChange('x', 1, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), parm.terminal_parameters_report);

    intermediates[0] = '#';
    try std.testing.expect(process(Event{ .style_change = .{
        .final = 'R',
        .params = [_]i32{0} ** 16,
        .param_count = 0,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }).? == .xtreportcolors);
}

test "semantic: XTREPORTSGR maps to selected graphic rendition report" {
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '#';
    var params = [_]i32{0} ** 16;
    params[0] = 1;
    params[1] = 2;
    params[2] = 3;
    params[3] = 4;
    const sgr = process(Event{ .style_change = .{
        .final = '|',
        .params = params,
        .param_count = 4,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 0), sgr.selected_graphic_rendition_report.top);
    try std.testing.expectEqual(@as(u16, 1), sgr.selected_graphic_rendition_report.left);
    try std.testing.expectEqual(@as(?u16, 2), sgr.selected_graphic_rendition_report.bottom);
    try std.testing.expectEqual(@as(?u16, 3), sgr.selected_graphic_rendition_report.right);
}

test "semantic: locator controls map" {
    var params = [_]i32{0} ** 16;
    params[0] = 2;
    params[1] = 1;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '\'';
    const elr = process(Event{ .style_change = .{
        .final = 'z',
        .params = params,
        .param_count = 2,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 2), elr.locator_reporting.mode);
    try std.testing.expectEqual(@as(u16, 1), elr.locator_reporting.unit);

    params = [_]i32{0} ** 16;
    params[0] = 3;
    const req = process(Event{ .style_change = .{
        .final = '|',
        .params = params,
        .param_count = 1,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), req.locator_request);

    params = [_]i32{0} ** 16;
    params[0] = 2;
    params[1] = 3;
    params[2] = 4;
    params[3] = 5;
    const filter = process(Event{ .style_change = .{
        .final = 'w',
        .params = params,
        .param_count = 4,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(?u16, 1), filter.locator_filter.top);
    try std.testing.expectEqual(@as(?u16, 4), filter.locator_filter.right);

    intermediates[1] = '*';
    params = [_]i32{0} ** 16;
    params[0] = 1;
    params[1] = 3;
    const sle = process(Event{ .style_change = .{
        .final = '{',
        .params = params,
        .param_count = 2,
        .leader = 0,
        .private = false,
        .intermediates = intermediates,
        .intermediates_len = 2,
    } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 2), sle.locator_events.param_count);
}

test "semantic: DECRQM maps to dec mode query" {
    var params = [_]i32{0} ** 16;
    params[0] = 1004;
    var intermediates = [_]u8{0} ** 4;
    intermediates[0] = '$';
    const ev = Event{ .style_change = .{
        .final = 'p',
        .params = params,
        .param_count = 1,
        .leader = '?',
        .private = true,
        .intermediates = intermediates,
        .intermediates_len = 1,
    } };
    try std.testing.expectEqual(@as(u16, 1004), process(ev).?.dec_mode_query);
}

test "semantic: XTSAVE and XTRESTORE collect DEC private modes" {
    const save = process(makePrivateStyleChange('s', &.{ 1, 7, 1004 })) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 3), save.dec_mode_save.param_count);
    try std.testing.expectEqual(@as(u16, 1), save.dec_mode_save.params[0]);
    try std.testing.expectEqual(@as(u16, 7), save.dec_mode_save.params[1]);
    try std.testing.expectEqual(@as(u16, 1004), save.dec_mode_save.params[2]);

    const restore = process(makePrivateStyleChange('r', &.{ 1, 7, 1004 })) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 3), restore.dec_mode_restore.param_count);
    try std.testing.expectEqual(@as(u16, 1004), restore.dec_mode_restore.params[2]);
}

test "semantic: ED no param defaults to mode 0" {
    const sem = process(makeStyleChange('J', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 0), sem.erase_display);
}

test "semantic: ED mode 1 above" {
    const sem = process(makeStyleChange('J', 1, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 1), sem.erase_display);
}

test "semantic: ED mode 2 full" {
    const sem = process(makeStyleChange('J', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 2), sem.erase_display);
}

test "semantic: ED mode 3 scrollback" {
    const sem = process(makeStyleChange('J', 3, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 3), sem.erase_display);
}

test "semantic: EL mode 0 right" {
    const sem = process(makeStyleChange('K', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 0), sem.erase_line);
}

test "semantic: EL mode 1 left" {
    const sem = process(makeStyleChange('K', 1, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 1), sem.erase_line);
}

test "semantic: EL mode 2 full line" {
    const sem = process(makeStyleChange('K', 2, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 2), sem.erase_line);
}

test "semantic: EL invalid mode maps to 0" {
    const sem = process(makeStyleChange('K', 5, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u2, 0), sem.erase_line);
}

test "semantic: ECH explicit count" {
    const sem = process(makeStyleChange('X', 6, 0, 1)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 6), sem.erase_chars);
}

test "semantic: ECH defaults to one char" {
    const sem = process(makeStyleChange('X', 0, 0, 0)) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.erase_chars);
}

test "semantic: SL explicit count" {
    const sem = process(makeStyleChangeWithParamAndIntermediate('@', 3, ' ')) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 3), sem.shift_left_columns);
}

test "semantic: SR defaults to one column" {
    const sem = process(makeStyleChangeWithIntermediate('A', ' ')) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 1), sem.shift_right_columns);
}

test "semantic: DECST8C resets default tab stops" {
    try std.testing.expect(process(makePrivateStyleChange('W', &.{5})).? == .reset_default_tab_stops);
}

test "semantic: kitty graphics APC parses control keys and payload" {
    const sem = process(Event{ .apc = "Gi=31,I=4,s=10,v=2,a=q,t=d,f=24,x=3,y=5,z=-1;AAAA" }) orelse return error.NoEvent;
    const cmd = sem.kitty_graphics;
    try std.testing.expectEqual(@as(u8, 'q'), cmd.action);
    try std.testing.expectEqual(@as(u32, 31), cmd.image_id);
    try std.testing.expectEqual(@as(u32, 4), cmd.image_number);
    try std.testing.expectEqual(@as(u32, 10), cmd.width);
    try std.testing.expectEqual(@as(u32, 2), cmd.height);
    try std.testing.expectEqual(@as(u32, 3), cmd.x);
    try std.testing.expectEqual(@as(u32, 5), cmd.y);
    try std.testing.expectEqual(@as(i32, -1), cmd.z);
    try std.testing.expectEqual(@as(u16, 24), cmd.format);
    try std.testing.expectEqual(@as(u8, 'd'), cmd.medium);
    try std.testing.expectEqualStrings("AAAA", cmd.payload);
}

test "semantic: kitty shell integration OSC 133 parses mark and status" {
    const sem = process(Event{ .osc = .{ .kind = .generic, .command = 133, .payload = "D;7", .terminator = .bel } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, 'D'), sem.kitty_shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), sem.kitty_shell_mark.status);
}

test "semantic: kitty notification OSC 99 splits metadata and payload" {
    const sem = process(Event{ .osc = .{ .kind = .generic, .command = 99, .payload = "i=1:p=body;Hello", .terminator = .st } }) orelse return error.NoEvent;
    try std.testing.expectEqualStrings("i=1:p=body", sem.kitty_notification.metadata);
    try std.testing.expectEqualStrings("Hello", sem.kitty_notification.payload);
}

test "semantic: kitty pointer shape OSC 22 parses action and names" {
    const sem = process(Event{ .osc = .{ .kind = .generic, .command = 22, .payload = ">wait,pointer", .terminator = .st } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u8, '>'), sem.kitty_pointer_shape.action);
    try std.testing.expectEqualStrings("wait,pointer", sem.kitty_pointer_shape.names);
}

test "semantic: kitty color stack OSC codes map to commands" {
    const push = process(Event{ .osc = .{ .kind = .generic, .command = 30001, .payload = "", .terminator = .st } }) orelse return error.NoEvent;
    const pop = process(Event{ .osc = .{ .kind = .generic, .command = 30101, .payload = "", .terminator = .st } }) orelse return error.NoEvent;
    try std.testing.expect(push.kitty_color_stack == .push);
    try std.testing.expect(pop.kitty_color_stack == .pop);
}

test "semantic: terminal color OSC commands preserve command and payload" {
    const kitty = process(Event{ .osc = .{ .kind = .generic, .command = 21, .payload = "foreground=?", .terminator = .st } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 21), kitty.terminal_color_control.command);
    try std.testing.expectEqualStrings("foreground=?", kitty.terminal_color_control.payload);

    const xterm = process(Event{ .osc = .{ .kind = .generic, .command = 4, .payload = "1;#ff0000", .terminator = .st } }) orelse return error.NoEvent;
    try std.testing.expectEqual(@as(u16, 4), xterm.terminal_color_control.command);
    try std.testing.expectEqualStrings("1;#ff0000", xterm.terminal_color_control.payload);
}
