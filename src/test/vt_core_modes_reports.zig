//! Responsibility: input encoding, mode tracking, and report surface coverage.
//! Ownership: vt-core input, mode, and report behavior tests.
//! Reason: keep host-input and host-output protocol coverage out of the main vt-core facade.

const std = @import("std");
const vt = @import("vt_core");
const input_mod = @import("../input.zig");

const Input = input_mod.Input;

test "encodeMouse returns empty output and does not mutate state" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("HELLO");
    vt_core.apply();

    var snap_before = try vt_core.snapshot();
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

    const output = vt_core.encodeMouse(mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.selection, snap_after.selection);
    try std.testing.expectEqual(snap_before.history_count, snap_after.history_count);
}

test "mouse reporting is gated by DECSET mouse modes and SGR protocol" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

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

    try std.testing.expectEqualStrings("", vt_core.encodeMouse(mouse_event));
    vt_core.feedSlice("\x1b[?1000h\x1b[?1006h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[<0;4;3M", vt_core.encodeMouse(mouse_event));

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
    try std.testing.expectEqualStrings("", vt_core.encodeMouse(move_event));
    vt_core.feedSlice("\x1b[?1002h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[<32;4;3M", vt_core.encodeMouse(move_event));
    vt_core.feedSlice("\x1b[?1003h");
    vt_core.apply();
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
    try std.testing.expectEqualStrings("\x1b[<35;2;2M", vt_core.encodeMouse(hover_event));
}

test "mouse reporting supports legacy x10 normal utf8 and urxvt encodings" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    const press = Input.MouseEvent{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = vt.VtCore.mod_shift | vt.VtCore.mod_alt, .buttons_down = 1 };
    const release = Input.MouseEvent{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = 0, .buttons_down = 0 };
    const wheel = Input.MouseEvent{ .kind = .wheel, .button = .wheel_down, .row = 2, .col = 3, .mod = 0, .buttons_down = 0 };

    vt_core.feedSlice("\x1b[?9h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[M $#", vt_core.encodeMouse(press));
    try std.testing.expectEqualStrings("", vt_core.encodeMouse(release));

    vt_core.feedSlice("\x1b[?1000h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[M,$#", vt_core.encodeMouse(press));
    try std.testing.expectEqualStrings("\x1b[M#$#", vt_core.encodeMouse(release));
    try std.testing.expectEqualStrings("\x1b[Ma$#", vt_core.encodeMouse(wheel));

    vt_core.feedSlice("\x1b[?1005h");
    vt_core.apply();
    const far_press = Input.MouseEvent{ .kind = .press, .button = .left, .row = 240, .col = 240, .mod = 0, .buttons_down = 1 };
    try std.testing.expectEqualStrings("\x1b[M \xc4\x91\xc4\x91", vt_core.encodeMouse(far_press));

    vt_core.feedSlice("\x1b[?1015h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[32;241;241M", vt_core.encodeMouse(far_press));
}

test "mouse mode queries and save restore include extended protocols" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[?1003h\x1b[?1005h\x1b[?1003;1005s");
    vt_core.feedSlice("\x1b[?1000h\x1b[?1006h");
    vt_core.feedSlice("\x1b[?1003;1005r");
    vt_core.feedSlice("\x1b[?9$p\x1b[?1000$p\x1b[?1003$p\x1b[?1005$p\x1b[?1006$p\x1b[?1015$p");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1b[?9;2$y\x1b[?1000;2$y\x1b[?1003;1$y\x1b[?1005;1$y\x1b[?1006;2$y\x1b[?1015;2$y", vt_core.pendingOutput());
}

test "application cursor mode changes arrow key encoding" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    try std.testing.expectEqualStrings("\x1b[A", vt_core.encodeKey(vt.VtCore.key_up, vt.VtCore.mod_none));
    vt_core.feedSlice("\x1b[?1h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bOA", vt_core.encodeKey(vt.VtCore.key_up, vt.VtCore.mod_none));
    try std.testing.expectEqualStrings("\x1b[1;5A", vt_core.encodeKey(vt.VtCore.key_up, vt.VtCore.mod_ctrl));
    vt_core.feedSlice("\x1b[?1l");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[A", vt_core.encodeKey(vt.VtCore.key_up, vt.VtCore.mod_none));
}

test "kitty keyboard set query push and pop flags" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[=5u\x1b[?u");
    vt_core.apply();
    try std.testing.expectEqual(@as(u32, 5), vt_core.kittyKeyboardFlags());
    try std.testing.expectEqualStrings("\x1b[?5u", vt_core.pendingOutput());
    vt_core.clearPendingOutput();

    vt_core.feedSlice("\x1b[>1u\x1b[?u");
    vt_core.apply();
    try std.testing.expectEqual(@as(u32, 1), vt_core.kittyKeyboardFlags());
    try std.testing.expectEqualStrings("\x1b[?1u", vt_core.pendingOutput());
    vt_core.clearPendingOutput();

    vt_core.feedSlice("\x1b[<u\x1b[?u");
    vt_core.apply();
    try std.testing.expectEqual(@as(u32, 5), vt_core.kittyKeyboardFlags());
    try std.testing.expectEqualStrings("\x1b[?5u", vt_core.pendingOutput());
}

test "kitty keyboard flags stay separate across alternate screen" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[=1u\x1b[?1049h\x1b[=8u");
    vt_core.apply();
    try std.testing.expect(vt_core.isAlternateScreen());
    try std.testing.expectEqual(@as(u32, 8), vt_core.kittyKeyboardFlags());
    vt_core.feedSlice("\x1b[?1049l");
    vt_core.apply();
    try std.testing.expectEqual(@as(u32, 1), vt_core.kittyKeyboardFlags());
}

test "kitty keyboard mode switches existing keys to CSI-u family" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[=1u");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[27u", vt_core.encodeKey(vt.VtCore.key_escape, vt.VtCore.mod_none));
    try std.testing.expectEqualStrings("\x1b[127;5u", vt_core.encodeKey(vt.VtCore.key_backspace, vt.VtCore.mod_ctrl));
    try std.testing.expectEqualStrings("\x1b[1;5A", vt_core.encodeKey(vt.VtCore.key_up, vt.VtCore.mod_ctrl));
    try std.testing.expectEqualStrings("\x1b[15~", vt_core.encodeKey(vt.VtCore.key_f5, vt.VtCore.mod_none));
}

test "focus reports are gated by DECSET 1004" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    try std.testing.expectEqualStrings("", vt_core.encodeFocusIn());
    try std.testing.expectEqualStrings("", vt_core.encodeFocusOut());
    vt_core.feedSlice("\x1b[?1004h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[I", vt_core.encodeFocusIn());
    try std.testing.expectEqualStrings("\x1b[O", vt_core.encodeFocusOut());
    vt_core.feedSlice("\x1b[?1004l");
    vt_core.apply();
    try std.testing.expectEqualStrings("", vt_core.encodeFocusIn());
}

test "bracketed paste wrappers are gated by DECSET 2004" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    try std.testing.expectEqualStrings("", vt_core.encodePasteStart());
    try std.testing.expectEqualStrings("", vt_core.encodePasteEnd());
    vt_core.feedSlice("\x1b[?2004h");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[200~", vt_core.encodePasteStart());
    try std.testing.expectEqualStrings("\x1b[201~", vt_core.encodePasteEnd());
    vt_core.feedSlice("\x1b[?2004l");
    vt_core.apply();
    try std.testing.expectEqualStrings("", vt_core.encodePasteStart());
}

test "report queries append pending host output" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[2;3H\x1b[5n\x1b[6n\x1b[c\x1b[>c\x1b[>0q\x1b[#S");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[0n\x1b[2;3R\x1b[?62;22c\x1b[>1;10;0c\x1bP>|howl-vt-core dev\x1b\\\x1b[0;0#S", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    try std.testing.expectEqualStrings("", vt_core.pendingOutput());
}

test "ENQ default answerback is empty and printable space remains text" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 2, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("A \x05B");
    vt_core.apply();

    try std.testing.expectEqualStrings("", vt_core.pendingOutput());
    try std.testing.expectEqual(@as(u16, 0), vt_core.renderView().cursor_row);
    try std.testing.expectEqual(@as(u16, 3), vt_core.renderView().cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), vt_core.renderView().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, ' '), vt_core.renderView().cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), vt_core.renderView().cellAt(0, 2));
}

test "extended report queries append host output" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 18);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1bH\x1b[=c\x1b[\"v\x1b[0x\x1b[1x\x1b[2$w");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1bP!|00000000\x1b\\\x1b[4;18;1;1;1\"w\x1b[2;1;1;128;128;1;0x\x1b[3;1;1;128;128;1;0x\x1bP2$u1/9/17\x1b\\", vt_core.pendingOutput());
}

test "ANSI mode queries and XTREPORTCOLORS append host output" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[2h\x1b[4h\x1b[12h\x1b[20h\x1b]30001\x1b\\\x1b[2$p\x1b[4$p\x1b[12$p\x1b[20$p\x1b[#R");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[2;1$y\x1b[4;1$y\x1b[12;1$y\x1b[20;1$y\x1b[1;1#Q", vt_core.pendingOutput());
}

test "XTREPORTSGR reports common rectangle attrs conservatively" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 2, 4);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[31mAB\x1b[0mCD\x1b[1;1;1;2#|\x1b[1;1;1;4#|");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[0;31m\x1b[0m", vt_core.pendingOutput());
}

test "ANSI modes affect key encoding and insert writes" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 2, 4);
    defer vt_core.deinit();

    try std.testing.expectEqualStrings("\r", vt_core.encodeKey(vt.VtCore.key_enter, vt.VtCore.mod_none));
    vt_core.feedSlice("\x1b[20h\x1b[2h");
    vt_core.apply();
    try std.testing.expectEqualStrings("", vt_core.encodeKey('a', vt.VtCore.mod_none));

    vt_core.feedSlice("\x1b[2l");
    vt_core.apply();
    try std.testing.expectEqualStrings("\r\n", vt_core.encodeKey(vt.VtCore.key_enter, vt.VtCore.mod_none));

    vt_core.feedSlice("ABCD\x1b[4h\x1b[1;2H!\x1b[4$p");
    vt_core.apply();
    try std.testing.expectEqual(@as(u21, 'A'), vt_core.renderView().cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), vt_core.renderView().cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), vt_core.renderView().cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), vt_core.renderView().cellAt(0, 3));
    try std.testing.expectEqualStrings("\x1b[4;1$y", vt_core.pendingOutput());
}

test "checksum extension affects rectangular checksum reply" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 2, 2);
    defer vt_core.deinit();

    vt_core.feedSlice("ABCD\x1b[0#y\x1b[7;1;1;1;1;2;2*y");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP7!~FF7C\x1b\\", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b[1#y\x1b[8;1;1;1;1;2;2*y");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP8!~0083\x1b\\", vt_core.pendingOutput());
}

test "locator requests reply unavailable, then current position, then disable one-shot" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[0'|");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[0&w", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b[1;0'z");
    vt_core.apply();
    _ = vt_core.encodeMouse(.{ .kind = .move, .button = .none, .row = 2, .col = 3, .mod = 0, .buttons_down = 1 });
    vt_core.feedSlice("\x1b[0'|");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b[2;0'z\x1b[0'|");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", vt_core.pendingOutput());
    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b[0'|");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[0&w", vt_core.pendingOutput());
}

test "locator button and filter events append DECLRP" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[1;0'z\x1b[1;3'*{");
    vt_core.apply();

    _ = vt_core.encodeMouse(.{ .kind = .press, .button = .left, .row = 1, .col = 2, .mod = 0, .buttons_down = 1 });
    try std.testing.expectEqualStrings("\x1b[2;4;2;3;0&w", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    _ = vt_core.encodeMouse(.{ .kind = .release, .button = .left, .row = 1, .col = 2, .mod = 0, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[3;0;2;3;0&w", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b[2;2;2;2'w");
    vt_core.apply();
    _ = vt_core.encodeMouse(.{ .kind = .move, .button = .none, .row = 3, .col = 3, .mod = 0, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[10;0;4;4;0&w", vt_core.pendingOutput());
}

test "DECCIR reports default cursor information" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[1$w");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;BBBB\x1b\\", vt_core.pendingOutput());
}

test "DECCIR reports cursor position and rendition bits" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[3;7H\x1b[1m\x1b[4m\x1b[1$w");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP1$u3;7;1;C;@;@;0;2;@;BBBB\x1b\\", vt_core.pendingOutput());
}

test "DECCIR reports protection origin and wrap flags" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 1, 5);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[1\"q\x1b[?6hABCDE\x1b[1$w");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;5;1;@;A;I;0;2;@;BBBB\x1b\\", vt_core.pendingOutput());
}

test "DECCIR reports charset designation and GL shift" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b(0\x1b[1$w");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;0BBB\x1b\\", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b)0\x0E\x1b[1$w");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;1;2;@;00BB\x1b\\", vt_core.pendingOutput());
}

test "DECXCPR appends DEC cursor position report" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[3;4H\x1b[?6n");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[?3;4R", vt_core.pendingOutput());
}

test "DEC locator DSR replies status and type" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[?55n\x1b[?56n");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[?50n\x1b[?57;1n", vt_core.pendingOutput());
}

test "DEC mode queries append DECRPM replies" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[?1004h\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004$p\x1b[?2004$p\x1b[?1002$p\x1b[?1006$p\x1b[?25$p\x1b[?9999$p");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[?1004;1$y\x1b[?2004;1$y\x1b[?1002;1$y\x1b[?1006;1$y\x1b[?25;1$y\x1b[?9999;0$y", vt_core.pendingOutput());
}

test "DECRQSS replies for owned state and invalid requests" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[2;3r\x1b[?69h\x1b[2;7s\x1b[3 q\x1b[1\"q\x1b[2*x");
    vt_core.feedSlice("\x1bP$qr\x1b\\\x1bP$qs\x1b\\\x1bP$q q\x1b\\\x1bP$q\"q\x1b\\\x1bP$q*x\x1b\\\x1bP$qm\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings(
        "\x1bP1$r2;3r\x1b\\\x1bP1$r2;7s\x1b\\\x1bP1$r3 q\x1b\\\x1bP1$r1\"q\x1b\\\x1bP1$r2*x\x1b\\\x1bP0$r\x1b\\",
        vt_core.pendingOutput(),
    );
}

test "DCS resource queries return conservative invalid replies" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1bP+q436F\x1b\\\x1bP+Q6E616D65\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1bP0+r\x1b\\\x1bP0+R6E616D65\x1b\\", vt_core.pendingOutput());
}

test "XTSAVE and XTRESTORE restore supported DEC private modes" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[?1h\x1b[?7l\x1b[?25l\x1b[?1004h\x1b[?2004h");
    vt_core.feedSlice("\x1b[?1;7;25;1004;2004s");
    vt_core.feedSlice("\x1b[?1l\x1b[?7h\x1b[?25h\x1b[?1004l\x1b[?2004l");
    vt_core.feedSlice("\x1b[?1;7;25;1004;2004r");
    vt_core.feedSlice("\x1b[?1$p\x1b[?7$p\x1b[?25$p\x1b[?1004$p\x1b[?2004$p");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1bOA", vt_core.encodeKey(vt.VtCore.key_up, vt.VtCore.mod_none));
    try std.testing.expect(!vt_core.renderView().screen.auto_wrap);
    try std.testing.expect(!vt_core.renderView().cursor_visible);
    try std.testing.expectEqualStrings("\x1b[I", vt_core.encodeFocusIn());
    try std.testing.expectEqualStrings("\x1b[200~", vt_core.encodePasteStart());
    try std.testing.expectEqualStrings("\x1b[?1;1$y\x1b[?7;2$y\x1b[?25;2$y\x1b[?1004;1$y\x1b[?2004;1$y", vt_core.pendingOutput());
}

test "application keypad modes affect keypad encoding and DECRQM" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    try std.testing.expectEqualStrings("1", vt_core.encodeKey(vt.VtCore.key_kp_1, vt.VtCore.mod_none));
    try std.testing.expectEqualStrings("\r", vt_core.encodeKey(vt.VtCore.key_kp_enter, vt.VtCore.mod_none));

    vt_core.feedSlice("\x1b=\x1b[?66$p");
    vt_core.apply();
    try std.testing.expect(vt_core.isApplicationKeypad());
    try std.testing.expectEqualStrings("\x1b[?66;1$y", vt_core.pendingOutput());
    try std.testing.expectEqualStrings("\x1bOq", vt_core.encodeKey(vt.VtCore.key_kp_1, vt.VtCore.mod_none));
    try std.testing.expectEqualStrings("\x1bOM", vt_core.encodeKey(vt.VtCore.key_kp_enter, vt.VtCore.mod_none));

    vt_core.feedSlice("\x1b>");
    vt_core.apply();
    try std.testing.expect(!vt_core.isApplicationKeypad());
    try std.testing.expectEqualStrings("1", vt_core.encodeKey(vt.VtCore.key_kp_1, vt.VtCore.mod_none));
}

test "modifyOtherKeys set query disable and encoding" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    try std.testing.expectEqualStrings("a", vt_core.encodeKey('a', vt.VtCore.mod_alt));
    vt_core.feedSlice("\x1b[>4;2m\x1b[?4m");
    vt_core.apply();
    try std.testing.expectEqual(@as(i8, 2), vt_core.modifyOtherKeys());
    try std.testing.expectEqualStrings("\x1b[>4;2m", vt_core.pendingOutput());
    try std.testing.expectEqualStrings("\x1b[27;3;97~", vt_core.encodeKey('a', vt.VtCore.mod_alt));
    try std.testing.expectEqualStrings("a", vt_core.encodeKey('a', vt.VtCore.mod_none));

    vt_core.feedSlice("\x1b[>4;3m");
    vt_core.apply();
    try std.testing.expectEqualStrings("\x1b[27;1;97~", vt_core.encodeKey('a', vt.VtCore.mod_none));

    vt_core.feedSlice("\x1b[>4n");
    vt_core.apply();
    try std.testing.expectEqual(@as(i8, -1), vt_core.modifyOtherKeys());
}

test "xterm key format query reset and other-key encoding" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 4, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[>4;1f\x1b[?4g\x1b[>4;1m");
    vt_core.apply();
    try std.testing.expectEqual(@as(u16, 1), vt_core.keyFormatOption(4));
    try std.testing.expectEqualStrings("\x1b[>4;1f", vt_core.pendingOutput());
    try std.testing.expectEqualStrings("\x1b[97;3u", vt_core.encodeKey('a', vt.VtCore.mod_alt));

    vt_core.feedSlice("\x1b[>4f\x1b[?4g");
    vt_core.apply();
    try std.testing.expectEqual(@as(u16, 0), vt_core.keyFormatOption(4));
    try std.testing.expectEqualStrings("\x1b[>4;1f\x1b[>4;0f", vt_core.pendingOutput());
}
