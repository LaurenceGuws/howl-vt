const std = @import("std");
const action_vocabulary = @import("../../src/action/vocabulary.zig");
const host_state = @import("../../src/host/state.zig");
const screen_capture = @import("../support/screen_capture.zig");
const screen_set = @import("../../src/terminal/screen_set.zig");
const selection = @import("../../src/terminal/selection/state.zig");
const terminal_mod = @import("../../src/terminal/terminal.zig");
const input_encode = @import("../../src/input/encode.zig");
const input_keyboard = @import("../../src/input/keyboard.zig");
const input_mouse = @import("../../src/input/mouse.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const HostState = host_state;
const StreamHarness = stream_harness.Harness;

var encode_scratch: input_encode.Scratch = .{};

fn encodeKey(terminal: *Terminal, key: input_keyboard.Key, mod: input_keyboard.Modifier) []const u8 {
    return input_encode.encodeKey(terminal, &encode_scratch, key, mod);
}

fn encodeMouse(terminal: *Terminal, event: input_mouse.MouseEvent) []const u8 {
    return input_encode.encodeMouse(terminal, &encode_scratch, event);
}

fn encodeFocusIn(terminal: *Terminal) []const u8 {
    return input_encode.encodeFocusIn(terminal, &encode_scratch);
}

fn encodeFocusOut(terminal: *Terminal) []const u8 {
    return input_encode.encodeFocusOut(terminal, &encode_scratch);
}

fn encodePasteStart(terminal: *Terminal) []const u8 {
    return input_encode.encodePasteStart(terminal, &encode_scratch);
}

fn encodePasteEnd(terminal: *Terminal) []const u8 {
    return input_encode.encodePasteEnd(terminal, &encode_scratch);
}

fn visibleView(terminal: *const Terminal, scrollback_offset: u32) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, scrollback_offset);
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

fn write(stream: *StreamHarness, bytes: []const u8) void {
    stream.nextSlice(bytes) catch unreachable;
}

fn pendingOutput(terminal: *const Terminal) []const u8 {
    return HostState.pendingOutput(terminal);
}

fn clearPendingOutput(terminal: *Terminal) void {
    HostState.clearPendingOutput(terminal);
}

fn dcsPayloadKind(terminal: *const Terminal) ?action_vocabulary.DcsPayloadKind {
    return HostState.dcsPayloadKind(terminal);
}

fn dcsPayload(terminal: *const Terminal) ?[]const u8 {
    return HostState.dcsPayload(terminal);
}

fn legacyControl(terminal: *const Terminal) ?action_vocabulary.LegacyControlKind {
    return HostState.legacyControl(terminal);
}

fn reverseWraparoundMode(terminal: *const Terminal) bool {
    return HostState.reverseWraparoundMode(terminal);
}

fn extendedReverseWraparoundMode(terminal: *const Terminal) bool {
    return HostState.extendedReverseWraparoundMode(terminal);
}

fn mediaCopyRequest(terminal: *const Terminal) ?u16 {
    return HostState.mediaCopyRequest(terminal);
}

test "encodeMouse returns empty output and does not mutate state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "HELLO");

    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    const mouse_event = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    const output = encodeMouse(&terminal, mouse_event);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    try std.testing.expectEqualSlices(u8, "", output);

    var snap_after = try captureSnapshot(&terminal);
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
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const mouse_event = input_mouse.MouseEvent{
        .kind = .press,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };

    try std.testing.expectEqualStrings("", encodeMouse(&terminal, mouse_event));
    write(&stream, "\x1b[?1000h\x1b[?1006h");
    try std.testing.expectEqualStrings("\x1b[<0;4;3M", encodeMouse(&terminal, mouse_event));

    const move_event = input_mouse.MouseEvent{
        .kind = .move,
        .button = .left,
        .row = 2,
        .col = 3,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 1,
    };
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, move_event));
    write(&stream, "\x1b[?1002h");
    try std.testing.expectEqualStrings("\x1b[<32;4;3M", encodeMouse(&terminal, move_event));
    write(&stream, "\x1b[?1003h");
    const hover_event = input_mouse.MouseEvent{
        .kind = .move,
        .button = .none,
        .row = 1,
        .col = 1,
        .pixel_x = null,
        .pixel_y = null,
        .mod = 0,
        .buttons_down = 0,
    };
    try std.testing.expectEqualStrings("\x1b[<35;2;2M", encodeMouse(&terminal, hover_event));
}

test "mouse reporting supports legacy x10 normal utf8 and urxvt encodings" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const press = input_mouse.MouseEvent{ .kind = .press, .button = .left, .row = 2, .col = 3, .mod = input_keyboard.mod_shift | input_keyboard.mod_alt, .buttons_down = 1 };
    const release = input_mouse.MouseEvent{ .kind = .release, .button = .left, .row = 2, .col = 3, .mod = 0, .buttons_down = 0 };
    const wheel = input_mouse.MouseEvent{ .kind = .wheel, .button = .wheel_down, .row = 2, .col = 3, .mod = 0, .buttons_down = 0 };

    write(&stream, "\x1b[?9h");
    try std.testing.expectEqualStrings("\x1b[M $#", encodeMouse(&terminal, press));
    try std.testing.expectEqualStrings("", encodeMouse(&terminal, release));

    write(&stream, "\x1b[?1000h");
    try std.testing.expectEqualStrings("\x1b[M,$#", encodeMouse(&terminal, press));
    try std.testing.expectEqualStrings("\x1b[M#$#", encodeMouse(&terminal, release));
    try std.testing.expectEqualStrings("\x1b[Ma$#", encodeMouse(&terminal, wheel));

    write(&stream, "\x1b[?1005h");
    const far_press = input_mouse.MouseEvent{ .kind = .press, .button = .left, .row = 240, .col = 240, .mod = 0, .buttons_down = 1 };
    try std.testing.expectEqualStrings("\x1b[M \xc4\x91\xc4\x91", encodeMouse(&terminal, far_press));

    write(&stream, "\x1b[?1015h");
    try std.testing.expectEqualStrings("\x1b[32;241;241M", encodeMouse(&terminal, far_press));
}

test "mouse mode queries and save restore include extended protocols" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[?1003h\x1b[?1005h\x1b[?1003;1005s");
    write(&stream, "\x1b[?1000h\x1b[?1006h");
    write(&stream, "\x1b[?1003;1005r");
    write(&stream, "\x1b[?9$p\x1b[?1000$p\x1b[?1003$p\x1b[?1005$p\x1b[?1006$p\x1b[?1015$p");

    try std.testing.expectEqualStrings("\x1b[?9;2$y\x1b[?1000;2$y\x1b[?1003;1$y\x1b[?1005;1$y\x1b[?1006;2$y\x1b[?1015;2$y", pendingOutput(&terminal));
}

test "application cursor mode changes arrow key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqualStrings("\x1b[A", encodeKey(&terminal, input_keyboard.key_up, input_keyboard.mod_none));
    write(&stream, "\x1b[?1h");
    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&terminal, input_keyboard.key_up, input_keyboard.mod_none));
    try std.testing.expectEqualStrings("\x1b[1;5A", encodeKey(&terminal, input_keyboard.key_up, input_keyboard.mod_ctrl));
    write(&stream, "\x1b[?1l");
    try std.testing.expectEqualStrings("\x1b[A", encodeKey(&terminal, input_keyboard.key_up, input_keyboard.mod_none));
}

test "kitty keyboard set query push and pop flags" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[=5u\x1b[?u");
    try std.testing.expectEqual(@as(u32, 5), input_encode.kittyKeyboardFlags(&terminal));
    try std.testing.expectEqualStrings("\x1b[?5u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    write(&stream, "\x1b[>1u\x1b[?u");
    try std.testing.expectEqual(@as(u32, 1), input_encode.kittyKeyboardFlags(&terminal));
    try std.testing.expectEqualStrings("\x1b[?1u", pendingOutput(&terminal));
    clearPendingOutput(&terminal);

    write(&stream, "\x1b[<u\x1b[?u");
    try std.testing.expectEqual(@as(u32, 5), input_encode.kittyKeyboardFlags(&terminal));
    try std.testing.expectEqualStrings("\x1b[?5u", pendingOutput(&terminal));
}

test "kitty keyboard flags stay separate across alternate screen" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[=1u\x1b[?1049h\x1b[=8u");
    try std.testing.expect(visibleView(&terminal, 0).is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 8), input_encode.kittyKeyboardFlags(&terminal));
    write(&stream, "\x1b[?1049l");
    try std.testing.expectEqual(@as(u32, 1), input_encode.kittyKeyboardFlags(&terminal));
}

test "kitty keyboard mode switches existing keys to CSI-u family" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[=1u");
    try std.testing.expectEqualStrings("\x1b[27u", encodeKey(&terminal, input_keyboard.key_escape, input_keyboard.mod_none));
    try std.testing.expectEqualStrings("\x1b[127;5u", encodeKey(&terminal, input_keyboard.key_backspace, input_keyboard.mod_ctrl));
    try std.testing.expectEqualStrings("\x1b[1;5A", encodeKey(&terminal, input_keyboard.key_up, input_keyboard.mod_ctrl));
    try std.testing.expectEqualStrings("\x1b[15~", encodeKey(&terminal, input_keyboard.key_f5, input_keyboard.mod_none));
}

test "focus reports are gated by DECSET 1004" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqualStrings("", encodeFocusIn(&terminal));
    try std.testing.expectEqualStrings("", encodeFocusOut(&terminal));
    write(&stream, "\x1b[?1004h");
    try std.testing.expectEqualStrings("\x1b[I", encodeFocusIn(&terminal));
    try std.testing.expectEqualStrings("\x1b[O", encodeFocusOut(&terminal));
    write(&stream, "\x1b[?1004l");
    try std.testing.expectEqualStrings("", encodeFocusIn(&terminal));
}

test "bracketed paste wrappers are gated by DECSET 2004" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqualStrings("", encodePasteStart(&terminal));
    try std.testing.expectEqualStrings("", encodePasteEnd(&terminal));
    write(&stream, "\x1b[?2004h");
    try std.testing.expectEqualStrings("\x1b[200~", encodePasteStart(&terminal));
    try std.testing.expectEqualStrings("\x1b[201~", encodePasteEnd(&terminal));
    write(&stream, "\x1b[?2004l");
    try std.testing.expectEqualStrings("", encodePasteStart(&terminal));
}

test "report queries append pending host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[2;3H\x1b[5n\x1b[6n\x1b[c\x1b[>c\x1b[>0q\x1b[#S");
    try std.testing.expectEqualStrings("\x1b[0n\x1b[2;3R\x1b[?62;22c\x1b[>1;10;0c\x1bP>|howl-vt dev\x1b\\\x1b[0;0#S", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
}

test "report query limit fails without partial pending output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const fill_len = HostState.pending_output_max_bytes - 3;
    const fill = try allocator.alloc(u8, fill_len);
    defer allocator.free(fill);
    @memset(fill, 'x');
    try HostState.appendPendingOutput(&terminal, fill);

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1b[5n"));
    try std.testing.expectEqual(fill_len, pendingOutput(&terminal).len);
}

test "ENQ default answerback is empty and printable space remains text" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "A \x05B");

    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    const view = visibleView(&terminal, 0);
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
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1bH\x1b[=c\x1b[\"v\x1b[0x\x1b[1x\x1b[2$w");

    try std.testing.expectEqualStrings("\x1bP!|00000000\x1b\\\x1b[4;18;1;1;1\"w\x1b[2;1;1;128;128;1;0x\x1b[3;1;1;128;128;1;0x\x1bP2$u1/9/17\x1b\\", pendingOutput(&terminal));
}

test "ANSI mode queries and XTREPORTCOLORS append host output" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[2h\x1b[4h\x1b[12h\x1b[20h\x1b]30001\x1b\\\x1b[2$p\x1b[4$p\x1b[12$p\x1b[20$p\x1b[#R");
    try std.testing.expectEqualStrings("\x1b[2;1$y\x1b[4;1$y\x1b[12;1$y\x1b[20;1$y\x1b[1;1#Q", pendingOutput(&terminal));
}

test "XTREPORTSGR reports common rectangle attrs conservatively" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[31mAB\x1b[0mCD\x1b[1;1;1;2#|\x1b[1;1;1;4#|");
    try std.testing.expectEqualStrings("\x1b[0;31m\x1b[0m", pendingOutput(&terminal));
}

test "XTREPORTSGR reports extended style attrs" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 1, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[1;2;3;8;9mAB\x1b[1;1;1;2#|");
    try std.testing.expectEqualStrings("\x1b[0;1;2;3;8;9m", pendingOutput(&terminal));
}

test "ANSI modes affect key encoding and insert writes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqualStrings("\r", encodeKey(&terminal, input_keyboard.key_enter, input_keyboard.mod_none));
    write(&stream, "\x1b[20h\x1b[2h");
    try std.testing.expectEqualStrings("", encodeKey(&terminal, 'a', input_keyboard.mod_none));

    write(&stream, "\x1b[2l");
    try std.testing.expectEqualStrings("\r\n", encodeKey(&terminal, input_keyboard.key_enter, input_keyboard.mod_none));

    write(&stream, "ABCD\x1b[4h\x1b[1;2H!\x1b[4$p");
    const view = visibleView(&terminal, 0);
    try std.testing.expectEqual(@as(u21, 'A'), view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), view.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'B'), view.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'C'), view.cellAt(0, 3));
    try std.testing.expectEqualStrings("\x1b[4;1$y", pendingOutput(&terminal));
}

test "checksum extension affects rectangular checksum reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "ABCD\x1b[0#y\x1b[7;1;1;1;1;2;2*y");
    try std.testing.expectEqualStrings("\x1bP7!~FF7C\x1b\\", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[1#y\x1b[8;1;1;1;1;2;2*y");
    try std.testing.expectEqualStrings("\x1bP8!~0083\x1b\\", pendingOutput(&terminal));
}

test "locator requests reply unavailable, then current position, then disable one-shot" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[1;0'z");
    _ = encodeMouse(&terminal, .{ .kind = .move, .button = .none, .row = 2, .col = 3, .mod = 0, .buttons_down = 1 });
    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[2;0'z\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[1;4;3;4;0&w", pendingOutput(&terminal));
    clearPendingOutput(&terminal);
    write(&stream, "\x1b[0'|");
    try std.testing.expectEqualStrings("\x1b[0&w", pendingOutput(&terminal));
}

test "locator button and filter events append DECLRP" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[1;0'z\x1b[1;3'*{");

    _ = encodeMouse(&terminal, .{ .kind = .press, .button = .left, .row = 1, .col = 2, .mod = 0, .buttons_down = 1 });
    try std.testing.expectEqualStrings("\x1b[2;4;2;3;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    _ = encodeMouse(&terminal, .{ .kind = .release, .button = .left, .row = 1, .col = 2, .mod = 0, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[3;0;2;3;0&w", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b[2;2;2;2'w");
    _ = encodeMouse(&terminal, .{ .kind = .move, .button = .none, .row = 3, .col = 3, .mod = 0, .buttons_down = 0 });
    try std.testing.expectEqualStrings("\x1b[10;0;4;4;0&w", pendingOutput(&terminal));
}

test "DECCIR reports default cursor information" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;BBBB\x1b\\", pendingOutput(&terminal));
}

test "DECCIR reports cursor position and rendition bits" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[3;7H\x1b[1m\x1b[4m\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u3;7;1;C;@;@;0;2;@;BBBB\x1b\\", pendingOutput(&terminal));
}

test "DECCIR reports protection origin and wrap flags" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 1, 5);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[1\"q\x1b[?6hABCDE\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u1;5;1;@;A;I;0;2;@;BBBB\x1b\\", pendingOutput(&terminal));
}

test "DECCIR reports charset designation and GL shift" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b(0\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;0BBB\x1b\\", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b)0\x0E\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;1;2;@;00BB\x1b\\", pendingOutput(&terminal));
}

test "DECCIR reports charset designation and GL shift across slices" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 10);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b(0");
    write(&stream, "\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;0;2;@;0BBB\x1b\\", pendingOutput(&terminal));

    clearPendingOutput(&terminal);
    write(&stream, "\x1b)0");
    write(&stream, "\x0E");
    write(&stream, "\x1b[1$w");
    try std.testing.expectEqualStrings("\x1bP1$u1;1;1;@;@;@;1;2;@;00BB\x1b\\", pendingOutput(&terminal));
}

test "DECXCPR appends DEC cursor position report" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[3;4H\x1b[?6n");
    try std.testing.expectEqualStrings("\x1b[?3;4R", pendingOutput(&terminal));
}

test "DEC locator DSR replies status and type" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[?55n\x1b[?56n");
    try std.testing.expectEqualStrings("\x1b[?50n\x1b[?57;1n", pendingOutput(&terminal));
}

test "DEC mode queries append DECRPM replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[?1004h\x1b[?2004h\x1b[?1002h\x1b[?1006h\x1b[?1004$p\x1b[?2004$p\x1b[?1002$p\x1b[?1006$p\x1b[?25$p\x1b[?9999$p");
    try std.testing.expectEqualStrings("\x1b[?1004;1$y\x1b[?2004;1$y\x1b[?1002;1$y\x1b[?1006;1$y\x1b[?25;1$y\x1b[?9999;0$y", pendingOutput(&terminal));
}

test "DECRQSS replies for owned state and invalid requests" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[2;3r\x1b[?69h\x1b[2;7s\x1b[3 q\x1b[1\"q\x1b[2*x");
    write(&stream, "\x1bP$qr\x1b\\\x1bP$qs\x1b\\\x1bP$q q\x1b\\\x1bP$q\"q\x1b\\\x1bP$q*x\x1b\\\x1bP$qm\x1b\\");

    try std.testing.expectEqualStrings(
        "\x1bP1$r2;3r\x1b\\\x1bP1$r2;7s\x1b\\\x1bP1$r3 q\x1b\\\x1bP1$r1\"q\x1b\\\x1bP1$r2*x\x1b\\\x1bP0$r\x1b\\",
        pendingOutput(&terminal),
    );
}

test "DCS resource queries return conservative invalid replies" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1bP+q436F\x1b\\\x1bP+Q6E616D65\x1b\\");

    try std.testing.expectEqualStrings("\x1bP0+r\x1b\\\x1bP0+R6E616D65\x1b\\", pendingOutput(&terminal));
}

test "DCS legacy payload protocols retain latest host-neutral payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1bP+p436F=7661\x1b\\");
    try std.testing.expect(dcsPayloadKind(&terminal).? == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", dcsPayload(&terminal).?);
}

test "DCS legacy payload protocols retain latest host-neutral payload across slices" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1bP+p436F=");
    try stream.nextSlice("7661\x1b\\");
    try std.testing.expect(dcsPayloadKind(&terminal).? == .xtsettcap);
    try std.testing.expectEqualStrings("436F=7661", dcsPayload(&terminal).?);
}

test "legacy Tektronix C0 and ESC controls retain latest host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1c\x1d\x1e\x1f");
    try std.testing.expect(legacyControl(&terminal).? == .tek_alpha);

    write(&stream, "\x1b\x17\x1b\x1c\x1bl\x1bs");
    try std.testing.expect(legacyControl(&terminal).? == .tek_write_thru_short_dashed);
}

test "XTSAVE and XTRESTORE restore supported DEC private modes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[?1h\x1b[?7l\x1b[?25l\x1b[?1004h\x1b[?2004h");
    write(&stream, "\x1b[?1;7;25;1004;2004s");
    write(&stream, "\x1b[?1l\x1b[?7h\x1b[?25h\x1b[?1004l\x1b[?2004l");
    write(&stream, "\x1b[?1;7;25;1004;2004r");
    write(&stream, "\x1b[?1$p\x1b[?7$p\x1b[?25$p\x1b[?1004$p\x1b[?2004$p");

    const view = visibleView(&terminal, 0);
    try std.testing.expectEqualStrings("\x1bOA", encodeKey(&terminal, input_keyboard.key_up, input_keyboard.mod_none));
    try std.testing.expect(!view.screen.auto_wrap);
    try std.testing.expect(!view.cursor_visible);
    try std.testing.expectEqualStrings("\x1b[I", encodeFocusIn(&terminal));
    try std.testing.expectEqualStrings("\x1b[200~", encodePasteStart(&terminal));
    try std.testing.expectEqualStrings("\x1b[?1;1$y\x1b[?7;2$y\x1b[?25;2$y\x1b[?1004;1$y\x1b[?2004;1$y", pendingOutput(&terminal));
}

test "application keypad modes affect keypad encoding and DECRQM" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqualStrings("1", encodeKey(&terminal, input_keyboard.key_kp_1, input_keyboard.mod_none));
    try std.testing.expectEqualStrings("\r", encodeKey(&terminal, input_keyboard.key_kp_enter, input_keyboard.mod_none));

    write(&stream, "\x1b=\x1b[?66$p");
    try std.testing.expect(input_encode.isApplicationKeypad(&terminal));
    try std.testing.expectEqualStrings("\x1b[?66;1$y", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1bOq", encodeKey(&terminal, input_keyboard.key_kp_1, input_keyboard.mod_none));
    try std.testing.expectEqualStrings("\x1bOM", encodeKey(&terminal, input_keyboard.key_kp_enter, input_keyboard.mod_none));

    write(&stream, "\x1b>");
    try std.testing.expect(!input_encode.isApplicationKeypad(&terminal));
    try std.testing.expectEqualStrings("1", encodeKey(&terminal, input_keyboard.key_kp_1, input_keyboard.mod_none));
}

test "modifyOtherKeys set query disable and encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqualStrings("a", encodeKey(&terminal, 'a', input_keyboard.mod_alt));
    write(&stream, "\x1b[>4;2m\x1b[?4m");
    try std.testing.expectEqual(@as(i8, 2), input_encode.modifyOtherKeys(&terminal));
    try std.testing.expectEqualStrings("\x1b[>4;2m", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1b[27;3;97~", encodeKey(&terminal, 'a', input_keyboard.mod_alt));
    try std.testing.expectEqualStrings("a", encodeKey(&terminal, 'a', input_keyboard.mod_none));

    write(&stream, "\x1b[>4;3m");
    try std.testing.expectEqualStrings("\x1b[27;1;97~", encodeKey(&terminal, 'a', input_keyboard.mod_none));

    write(&stream, "\x1b[>4n");
    try std.testing.expectEqual(@as(i8, -1), input_encode.modifyOtherKeys(&terminal));
}

test "xterm key format query reset and other-key encoding" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[>4;1f\x1b[?4g\x1b[>4;1m");
    try std.testing.expectEqual(@as(u16, 1), input_encode.keyFormatOption(&terminal, 4));
    try std.testing.expectEqualStrings("\x1b[>4;1f", pendingOutput(&terminal));
    try std.testing.expectEqualStrings("\x1b[97;3u", encodeKey(&terminal, 'a', input_keyboard.mod_alt));

    write(&stream, "\x1b[>4f\x1b[?4g");
    try std.testing.expectEqual(@as(u16, 0), input_encode.keyFormatOption(&terminal, 4));
    try std.testing.expectEqualStrings("\x1b[>4;1f\x1b[>4;0f", pendingOutput(&terminal));
}

test "low priority private modes and media copy retain host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    write(&stream, "\x1b[?45h\x1b[?1045h\x1b[?5i");
    try std.testing.expect(reverseWraparoundMode(&terminal));
    try std.testing.expect(extendedReverseWraparoundMode(&terminal));
    try std.testing.expectEqual(@as(?u16, 5), mediaCopyRequest(&terminal));

    write(&stream, "\x1b[?45l\x1b[?1045l");
    try std.testing.expect(!reverseWraparoundMode(&terminal));
    try std.testing.expect(!extendedReverseWraparoundMode(&terminal));
}
