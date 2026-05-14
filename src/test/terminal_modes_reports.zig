//! Input encoding, mode tracking, and report behavior tests.

const std = @import("std");
const terminal_mod = @import("../terminal.zig");
const input_mod = @import("../input.zig");

const Terminal = terminal_mod.Terminal;
const Input = input_mod;

test "encodeMouse returns empty output and does not mutate state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("HELLO");
    terminal.apply();

    var snap_before = try terminal.snapshot();
    defer snap_before.deinit();

    const mouse_event = Input.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    const output = terminal.encodeMouse(mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);

    var snap_after = try terminal.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
}

test "mouse reporting is gated by DECSET mouse modes and SGR protocol" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    const mouse_event = Input.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    try std.testing.expectEqualStrings("", terminal.encodeMouse(mouse_event));
    terminal.feedSlice("\x1b[?1000h\x1b[?1006h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[<0;4;3M", terminal.encodeMouse(mouse_event));

    const move_event = Input.MouseEvent{
        .kind = .move,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("", terminal.encodeMouse(move_event));
    terminal.feedSlice("\x1b[?1002h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[<32;4;3M", terminal.encodeMouse(move_event));
    terminal.feedSlice("\x1b[?1003h");
    terminal.apply();
    const hover_event = Input.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 1,
        .col = 1,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 0,
    };
    try std.testing.expectEqualStrings("\x1b[<35;2;2M", terminal.encodeMouse(hover_event));
}

test "mouse reporting supports legacy x10 normal utf8 and urxvt encodings" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    const press = Input.MouseEvent{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = Input.mod_shift | Input.mod_alt, .buttons_down = 1 };
    const release = Input.MouseEvent{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = 0, .buttons_down = 0 };
    const wheel = Input.MouseEvent{ .kind = .wheel, .button = .wheel_down, .row = 2, .col = 3, .mod = 0, .buttons_down = 0 };

    terminal.feedSlice("\x1b[?9h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[M $#", terminal.encodeMouse(press));
    try std.testing.expectEqualStrings("", terminal.encodeMouse(release));

    terminal.feedSlice("\x1b[?1000h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[M,$#", terminal.encodeMouse(press));
    try std.testing.expectEqualStrings("\x1b[M#$#", terminal.encodeMouse(release));
    try std.testing.expectEqualStrings("\x1b[Ma$#", terminal.encodeMouse(wheel));

    terminal.feedSlice("\x1b[?1005h");
    terminal.apply();
    const far_press = Input.MouseEvent{ .kind = .press, .button = .left, .row = 240, .col = 240, .mod = 0, .buttons_down = 1 };
    try std.testing.expectEqualStrings("\x1b[M \xc4\x91\xc4\x91", terminal.encodeMouse(far_press));

    terminal.feedSlice("\x1b[?1015h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[32;241;241M", terminal.encodeMouse(far_press));
}

test "mouse mode queries and save restore include extended protocols" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[?1003h\x1b[?1005h\x1b[?1003;1005s");
    terminal.feedSlice("\x1b[?1000h\x1b[?1006h");
    terminal.feedSlice("\x1b[?1003;1005r");
    terminal.feedSlice("\x1b[?9$p\x1b[?1000$p\x1b[?1003$p\x1b[?1005$p\x1b[?1006$p\x1b[?1015$p");
    terminal.apply();

    try std.testing.expectEqualStrings("\x1b[?9;2$y\x1b[?1000;2$y\x1b[?1003;1$y\x1b[?1005;1$y\x1b[?1006;2$y\x1b[?1015;2$y", terminal.pendingOutput());
}

test "application cursor mode changes arrow key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expectEqualStrings("\x1b[A", terminal.encodeKey(Input.key_up, Input.mod_none));
    terminal.feedSlice("\x1b[?1h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bOA", terminal.encodeKey(Input.key_up, Input.mod_none));
    try std.testing.expectEqualStrings("\x1b[1;5A", terminal.encodeKey(Input.key_up, Input.mod_ctrl));
    terminal.feedSlice("\x1b[?1l");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[A", terminal.encodeKey(Input.key_up, Input.mod_none));
}

test "kitty keyboard set query push and pop flags" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[=5u\x1b[?u");
    terminal.apply();
    try std.testing.expectEqual(@as(u32, 5), terminal.kittyKeyboardFlags());
    try std.testing.expectEqualStrings("\x1b[?5u", terminal.pendingOutput());
    terminal.clearPendingOutput();

    terminal.feedSlice("\x1b[>1u\x1b[?u");
    terminal.apply();
    try std.testing.expectEqual(@as(u32, 1), terminal.kittyKeyboardFlags());
    try std.testing.expectEqualStrings("\x1b[?1u", terminal.pendingOutput());
    terminal.clearPendingOutput();

    terminal.feedSlice("\x1b[<u\x1b[?u");
    terminal.apply();
    try std.testing.expectEqual(@as(u32, 5), terminal.kittyKeyboardFlags());
    try std.testing.expectEqualStrings("\x1b[?5u", terminal.pendingOutput());
}

test "kitty keyboard flags stay separate across alternate screen" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[=1u\x1b[?1049h\x1b[=8u");
    terminal.apply();
    try std.testing.expect(terminal.isAlternateScreen());
    try std.testing.expectEqual(@as(u32, 8), terminal.kittyKeyboardFlags());
    terminal.feedSlice("\x1b[?1049l");
    terminal.apply();
    try std.testing.expectEqual(@as(u32, 1), terminal.kittyKeyboardFlags());
}

test "kitty keyboard mode switches existing keys to CSI-u family" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[=1u");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[27u", terminal.encodeKey(Input.key_escape, Input.mod_none));
    try std.testing.expectEqualStrings("\x1b[127;5u", terminal.encodeKey(Input.key_backspace, Input.mod_ctrl));
    try std.testing.expectEqualStrings("\x1b[1;5A", terminal.encodeKey(Input.key_up, Input.mod_ctrl));
    try std.testing.expectEqualStrings("\x1b[15~", terminal.encodeKey(Input.key_f5, Input.mod_none));
}

test "focus reports are gated by DECSET 1004" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expectEqualStrings("", terminal.encodeFocusIn());
    try std.testing.expectEqualStrings("", terminal.encodeFocusOut());
    terminal.feedSlice("\x1b[?1004h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[I", terminal.encodeFocusIn());
    try std.testing.expectEqualStrings("\x1b[O", terminal.encodeFocusOut());
    terminal.feedSlice("\x1b[?1004l");
    terminal.apply();
    try std.testing.expectEqualStrings("", terminal.encodeFocusIn());
}

test "bracketed paste wrappers are gated by DECSET 2004" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expectEqualStrings("", terminal.encodePasteStart());
    try std.testing.expectEqualStrings("", terminal.encodePasteEnd());
    terminal.feedSlice("\x1b[?2004h");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[200~", terminal.encodePasteStart());
    try std.testing.expectEqualStrings("\x1b[201~", terminal.encodePasteEnd());
    terminal.feedSlice("\x1b[?2004l");
    terminal.apply();
    try std.testing.expectEqualStrings("", terminal.encodePasteStart());
}

test "report queries append pending host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[2;3H\x1b[5n\x1b[6n\x1b[c\x1b[>c\x1b[>0q\x1b[#S");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[0n\x1b[2;3R\x1b[?62;22c\x1b[>1;10;0c\x1bP>|howl-vt dev\x1b\\\x1b[0;0#S", terminal.pendingOutput());

    terminal.clearPendingOutput();
    try std.testing.expectEqualStrings("", terminal.pendingOutput());
}

test "ENQ default answerback is empty and printable space remains text" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 8);
    defer terminal.deinit();

    terminal.feedSlice("A \x05B");
    terminal.apply();

    try std.testing.expectEqualStrings("", terminal.pendingOutput());
    const view = terminal.visibleView(.{});
    try std.testing.expectEqual(@as(u16, 0), view.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), view.cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 2));
}

test "extended report queries append host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 18);
    defer terminal.deinit();

    terminal.feedSlice("\x1bH\x1b[=c\x1b[\"v\x1b[0x\x1b[1x\x1b[2$w");
    terminal.apply();

    try std.testing.expectEqualStrings("\x1bP!|00000000\x1b\\\x1b[4;18;1;1;1\"w\x1b[2;1;1;128;128;1;0x\x1b[3;1;1;128;128;1;0x\x1bP2$u1/9/17\x1b\\", terminal.pendingOutput());
}

test "ANSI mode queries and XTREPORTCOLORS append host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[2h\x1b[4h\x1b[12h\x1b[20h\x1b]30001\x1b\\\x1b[2$p\x1b[4$p\x1b[12$p\x1b[20$p\x1b[#R");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[2;1$y\x1b[4;1$y\x1b[12;1$y\x1b[20;1$y\x1b[1;1#Q", terminal.pendingOutput());
}

test "XTREPORTSGR reports common rectangle attrs conservatively" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[31mAB\x1b[0mCD\x1b[1;1;1;2#|\x1b[1;1;1;4#|");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[0;31m\x1b[0m", terminal.pendingOutput());
}

test "ANSI modes affect key encoding and insert writes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();

    try std.testing.expectEqualStrings("\r", terminal.encodeKey(Input.key_enter, Input.mod_none));
    terminal.feedSlice("\x1b[20h\x1b[2h");
    terminal.apply();
    try std.testing.expectEqualStrings("", terminal.encodeKey('a', Input.mod_none));

    terminal.feedSlice("\x1b[2l");
    terminal.apply();
    try std.testing.expectEqualStrings("\r\n", terminal.encodeKey(Input.key_enter, Input.mod_none));

    terminal.feedSlice("ABCD\x1b[4h\x1b[1;2H!\x1b[4$p");
    terminal.apply();
    const view = terminal.visibleView(.{});
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), view.cellAt(0, 3));
    try std.testing.expectEqualStrings("\x1b[4;1$y", terminal.pendingOutput());
}

test "checksum extension affects rectangular checksum reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 2);
    defer terminal.deinit();

    terminal.feedSlice("ABCD\x1b[0#y\x1b[7;1;1;1;1;2;2*y");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP7!~FF7C\x1b\\", terminal.pendingOutput());

    terminal.clearPendingOutput();
    terminal.feedSlice("\x1b[1#y\x1b[8;1;1;1;1;2;2*y");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP8!~0083\x1b\\", terminal.pendingOutput());
}

test "locator requests reply unavailable, then current position, then disable one-shot" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[0'|");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[0&w", terminal.pendingOutput());

    terminal.clearPendingOutput();
    terminal.feedSlice("\x1b[1;0'z");
    terminal.apply();
    _ = terminal.encodeMouse(.{ .kind = .move, .button = .none, .row = 2, .col = 3, .mod = 0, .buttons_down = 1 });
    terminal.feedSlice("\x1b[0'|");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", terminal.pendingOutput());

    terminal.clearPendingOutput();
    terminal.feedSlice("\x1b[2;0'z\x1b[0'|");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", terminal.pendingOutput());
    terminal.clearPendingOutput();
    terminal.feedSlice("\x1b[0'|");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[0&w", terminal.pendingOutput());
}

test "locator button and filter events append DECLRP" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[1;0'z\x1b[1;3'*{");
    terminal.apply();

    _ = terminal.encodeMouse(.{ .kind = .press, .button = .left, .row = 1, .col = 2, .mod = 0, .buttons_down = 1 });
    try std.testing.expectEqualStrings("\x1b[2;4;2;3;0&w", terminal.pendingOutput());

    terminal.clearPendingOutput();
    _ = terminal.encodeMouse(.{ .kind = .release, .button = .left, .row = 1, .col = 2, .mod = 0, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[3;0;2;3;0&w", terminal.pendingOutput());

    terminal.clearPendingOutput();
    terminal.feedSlice("\x1b[2;2;2;2'w");
    terminal.apply();
    _ = terminal.encodeMouse(.{ .kind = .move, .button = .none, .row = 3, .col = 3, .mod = 0, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[10;0;4;4;0&w", terminal.pendingOutput());
}

test "DECCIR reports default cursor information" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 10);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[1$w");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;BBBB\x1b\\", terminal.pendingOutput());
}

test "DECCIR reports cursor position and rendition bits" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[3;7H\x1b[1m\x1b[4m\x1b[1$w");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP1$u3;7;1;C;@;@;0;2;@;BBBB\x1b\\", terminal.pendingOutput());
}

test "DECCIR reports protection origin and wrap flags" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 1, 5);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[1\"q\x1b[?6hABCDE\x1b[1$w");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;5;1;@;A;I;0;2;@;BBBB\x1b\\", terminal.pendingOutput());
}

test "DECCIR reports charset designation and GL shift" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 10);
    defer terminal.deinit();

    terminal.feedSlice("\x1b(0\x1b[1$w");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;0BBB\x1b\\", terminal.pendingOutput());

    terminal.clearPendingOutput();
    terminal.feedSlice("\x1b)0\x0E\x1b[1$w");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;1;2;@;00BB\x1b\\", terminal.pendingOutput());
}

test "DECXCPR appends DEC cursor position report" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[3;4H\x1b[?6n");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[?3;4R", terminal.pendingOutput());
}

test "DEC locator DSR replies status and type" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[?55n\x1b[?56n");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[?50n\x1b[?57;1n", terminal.pendingOutput());
}

test "DEC mode queries append DECRPM replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[?1004h\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004$p\x1b[?2004$p\x1b[?1002$p\x1b[?1006$p\x1b[?25$p\x1b[?9999$p");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[?1004;1$y\x1b[?2004;1$y\x1b[?1002;1$y\x1b[?1006;1$y\x1b[?25;1$y\x1b[?9999;0$y", terminal.pendingOutput());
}

test "DECRQSS replies for owned state and invalid requests" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[2;3r\x1b[?69h\x1b[2;7s\x1b[3 q\x1b[1\"q\x1b[2*x");
    terminal.feedSlice("\x1bP$qr\x1b\\\x1bP$qs\x1b\\\x1bP$q q\x1b\\\x1bP$q\"q\x1b\\\x1bP$q*x\x1b\\\x1bP$qm\x1b\\");
    terminal.apply();

    try std.testing.expectEqualStrings(
        "\x1bP1$r2;3r\x1b\\\x1bP1$r2;7s\x1b\\\x1bP1$r3 q\x1b\\\x1bP1$r1\"q\x1b\\\x1bP1$r2*x\x1b\\\x1bP0$r\x1b\\",
        terminal.pendingOutput(),
    );
}

test "DCS resource queries return conservative invalid replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1bP+q436F\x1b\\\x1bP+Q6E616D65\x1b\\");
    terminal.apply();

    try std.testing.expectEqualStrings("\x1bP0+r\x1b\\\x1bP0+R6E616D65\x1b\\", terminal.pendingOutput());
}

test "DCS legacy payload protocols retain latest host-neutral payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1bP+p436F=7661\x1b\\");
    terminal.apply();
    try std.testing.expect(terminal.dcsPayloadKind().? == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", terminal.dcsPayload().?);

    terminal.feedSlice("\x1bP0;0;0qdata\x1b\\");
    terminal.apply();
    try std.testing.expect(terminal.dcsPayloadKind().? == .sixel);
    try std.testing.expectEqualStrings("0;0;0qdata", terminal.dcsPayload().?);

    terminal.feedSlice("\x1bP1pdraw\x1b\\");
    terminal.apply();
    try std.testing.expect(terminal.dcsPayloadKind().? == .regis);
    try std.testing.expectEqualStrings("1pdraw", terminal.dcsPayload().?);
}

test "legacy Tektronix C0 and ESC controls retain latest host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1c\x1d\x1e\x1f");
    terminal.apply();
    try std.testing.expect(terminal.legacyControl().? == .tek_alpha);

    terminal.feedSlice("\x1b\x17\x1b\x1c\x1bl\x1bs");
    terminal.apply();
    try std.testing.expect(terminal.legacyControl().? == .tek_write_thru_short_dashed);
}

test "XTSAVE and XTRESTORE restore supported DEC private modes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[?1h\x1b[?7l\x1b[?25l\x1b[?1004h\x1b[?2004h");
    terminal.feedSlice("\x1b[?1;7;25;1004;2004s");
    terminal.feedSlice("\x1b[?1l\x1b[?7h\x1b[?25h\x1b[?1004l\x1b[?2004l");
    terminal.feedSlice("\x1b[?1;7;25;1004;2004r");
    terminal.feedSlice("\x1b[?1$p\x1b[?7$p\x1b[?25$p\x1b[?1004$p\x1b[?2004$p");
    terminal.apply();

    const view = terminal.visibleView(.{});
    try std.testing.expectEqualStrings("\x1bOA", terminal.encodeKey(Input.key_up, Input.mod_none));
    try std.testing.expect(!view.screen.auto_wrap);
    try std.testing.expect(!view.cursor_visible);
    try std.testing.expectEqualStrings("\x1b[I", terminal.encodeFocusIn());
    try std.testing.expectEqualStrings("\x1b[200~", terminal.encodePasteStart());
    try std.testing.expectEqualStrings("\x1b[?1;1$y\x1b[?7;2$y\x1b[?25;2$y\x1b[?1004;1$y\x1b[?2004;1$y", terminal.pendingOutput());
}

test "application keypad modes affect keypad encoding and DECRQM" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expectEqualStrings("1", terminal.encodeKey(Input.key_kp_1, Input.mod_none));
    try std.testing.expectEqualStrings("\r", terminal.encodeKey(Input.key_kp_enter, Input.mod_none));

    terminal.feedSlice("\x1b=\x1b[?66$p");
    terminal.apply();
    try std.testing.expect(terminal.isApplicationKeypad());
    try std.testing.expectEqualStrings("\x1b[?66;1$y", terminal.pendingOutput());
    try std.testing.expectEqualStrings("\x1bOq", terminal.encodeKey(Input.key_kp_1, Input.mod_none));
    try std.testing.expectEqualStrings("\x1bOM", terminal.encodeKey(Input.key_kp_enter, Input.mod_none));

    terminal.feedSlice("\x1b>");
    terminal.apply();
    try std.testing.expect(!terminal.isApplicationKeypad());
    try std.testing.expectEqualStrings("1", terminal.encodeKey(Input.key_kp_1, Input.mod_none));
}

test "modifyOtherKeys set query disable and encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    try std.testing.expectEqualStrings("a", terminal.encodeKey('a', Input.mod_alt));
    terminal.feedSlice("\x1b[>4;2m\x1b[?4m");
    terminal.apply();
    try std.testing.expectEqual(@as(i8, 2), terminal.modifyOtherKeys());
    try std.testing.expectEqualStrings("\x1b[>4;2m", terminal.pendingOutput());
    try std.testing.expectEqualStrings("\x1b[27;3;97~", terminal.encodeKey('a', Input.mod_alt));
    try std.testing.expectEqualStrings("a", terminal.encodeKey('a', Input.mod_none));

    terminal.feedSlice("\x1b[>4;3m");
    terminal.apply();
    try std.testing.expectEqualStrings("\x1b[27;1;97~", terminal.encodeKey('a', Input.mod_none));

    terminal.feedSlice("\x1b[>4n");
    terminal.apply();
    try std.testing.expectEqual(@as(i8, -1), terminal.modifyOtherKeys());
}

test "xterm key format query reset and other-key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[>4;1f\x1b[?4g\x1b[>4;1m");
    terminal.apply();
    try std.testing.expectEqual(@as(u16, 1), terminal.keyFormatOption(4));
    try std.testing.expectEqualStrings("\x1b[>4;1f", terminal.pendingOutput());
    try std.testing.expectEqualStrings("\x1b[97;3u", terminal.encodeKey('a', Input.mod_alt));

    terminal.feedSlice("\x1b[>4f\x1b[?4g");
    terminal.apply();
    try std.testing.expectEqual(@as(u16, 0), terminal.keyFormatOption(4));
    try std.testing.expectEqualStrings("\x1b[>4;1f\x1b[>4;0f", terminal.pendingOutput());
}

test "low priority private modes and media copy retain host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();

    terminal.feedSlice("\x1b[?80h\x1b[?45h\x1b[?1045h\x1b[?5i");
    terminal.apply();
    try std.testing.expect(terminal.sixelDisplayMode());
    try std.testing.expect(terminal.reverseWraparoundMode());
    try std.testing.expect(terminal.extendedReverseWraparoundMode());
    try std.testing.expectEqual(@as(?u16, 5), terminal.mediaCopyRequest());

    terminal.feedSlice("\x1b[?80l\x1b[?45l\x1b[?1045l");
    terminal.apply();
    try std.testing.expect(!terminal.sixelDisplayMode());
    try std.testing.expect(!terminal.reverseWraparoundMode());
    try std.testing.expect(!terminal.extendedReverseWraparoundMode());
}
