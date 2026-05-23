const std = @import("std");
const host_state = @import("../host/state.zig");
const kitty_state = @import("../kitty/state.zig");
const terminal_mod = @import("../terminal.zig");
const screen_mod = @import("../screen.zig");
const stream_harness = @import("stream_harness.zig");

const HostState = host_state;
const KittyState = kitty_state;
const Terminal = terminal_mod.Terminal;
const Screen = screen_mod.Screen;
const Grid = Screen;
const StreamHarness = stream_harness.Harness;

test "OSC title updates terminal title under stream path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]0;My Title\x07");
    try std.testing.expectEqualStrings("My Title", terminal.host.current_title.?);
}

test "raw OSC title updates terminal title through OSC owner path" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]Raw Title\x07");
    try std.testing.expectEqualStrings("Raw Title", terminal.host.current_title.?);
}

test "OSC title limit fails without dropping current title" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]0;ok\x07");

    const title_len = HostState.title_max_bytes + 1;
    const payload = try allocator.alloc(u8, title_len);
    defer allocator.free(payload);
    @memset(payload, 'a');

    var seq = std.ArrayList(u8).empty;
    defer seq.deinit(allocator);
    try seq.appendSlice(allocator, "\x1b]0;");
    try seq.appendSlice(allocator, payload);
    try seq.appendSlice(allocator, "\x07");

    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice(seq.items));
    try std.testing.expectEqualStrings("ok", terminal.host.current_title.?);
}

test "OSC 8 assigns link ids and preserves URI lookup" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]8;;https://example.com\x07abc\x1b]8;;\x07z");

    const screen = terminal.screen_state.activeConst();
    const first = screen.cellInfoAt(0, 0).attrs.link_id;
    const second = screen.cellInfoAt(0, 1).attrs.link_id;
    const third = screen.cellInfoAt(0, 2).attrs.link_id;
    const trailing = screen.cellInfoAt(0, 3).attrs.link_id;
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqual(@as(u32, 0), trailing);
    try std.testing.expectEqualStrings("https://example.com", HostState.hyperlinkUriForId(&terminal, first).?);
}

test "OSC 52 produces pending clipboard request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]52;c;Zm9v\x07");
    try std.testing.expectEqualStrings("c;Zm9v", HostState.pendingClipboardSet(&terminal).?);
    HostState.clearPendingClipboardSet(&terminal);
    try std.testing.expectEqual(@as(?[]const u8, null), HostState.pendingClipboardSet(&terminal));
}

test "OSC 52 decoded clipboard drain clears pending request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]52;c;SG93bA==\x07");

    const text = (try HostState.drainPendingClipboardSet(&terminal, allocator)).?;
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Howl", text);
    try std.testing.expectEqual(@as(?[]const u8, null), HostState.pendingClipboardSet(&terminal));
}

test "OSC 52 query clipboard drain clears without request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]52;c;?\x07");

    try std.testing.expectEqual(@as(?[]u8, null), try HostState.drainPendingClipboardSet(&terminal, allocator));
    try std.testing.expectEqual(@as(?[]const u8, null), HostState.pendingClipboardSet(&terminal));
}

test "kitty clipboard OSC 5522 and mode query use host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[?5522h\x1b[?5522$p\x1b]5522;type=write;AAAA\x1b\\");

    try std.testing.expect(HostState.kittyClipboardMode(&terminal));
    try std.testing.expectEqualStrings("\x1b[?5522;1$y", HostState.pendingOutput(&terminal));
    try std.testing.expectEqualStrings("type=write;AAAA", HostState.pendingClipboardSet(&terminal).?);
}

test "kitty file transfer and text sizing OSC payloads are retained" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]5113;cmd=data;AAAA\x1b\\\x1b]66;s=2;Hi\x1b\\");

    try std.testing.expectEqualStrings("cmd=data;AAAA", KittyState.fileTransferRequest(&terminal).?);
    try std.testing.expectEqualStrings("s=2;Hi", KittyState.textSizeRequest(&terminal).?);
}

test "kitty shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");

    const mark = KittyState.shellMark(&terminal);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);
}

test "kitty notification OSC 99 queues host-neutral request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]99;i=1:d=0;Hello\x1b\\\x1b]99;i=1:p=body;World\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.notificationCount(&terminal));
    try std.testing.expectEqualStrings("i=1:d=0", KittyState.notificationAt(&terminal, 0).?.metadata);
    try std.testing.expectEqualStrings("Hello", KittyState.notificationAt(&terminal, 0).?.payload);
    try std.testing.expectEqualStrings("i=1:p=body", KittyState.notificationAt(&terminal, 1).?.metadata);
    try std.testing.expectEqualStrings("World", KittyState.notificationAt(&terminal, 1).?.payload);
}

test "kitty notification OSC 9 alias queues host-neutral request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]9;i=3:p=body;Alias\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.notificationCount(&terminal));
    try std.testing.expectEqualStrings("i=3:p=body", KittyState.notificationAt(&terminal, 0).?.metadata);
    try std.testing.expectEqualStrings("Alias", KittyState.notificationAt(&terminal, 0).?.payload);
}

test "kitty pointer shape OSC 22 maintains per-screen stack and replies to queries" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]22;pointer\x1b\\\x1b]22;>wait,crosshair\x1b\\\x1b]22;?__current__,pointer,no-such\x1b\\");

    try std.testing.expectEqualStrings("crosshair", KittyState.pointerShape(&terminal));
    try std.testing.expectEqualStrings("\x1b]22;crosshair,1,0\x1b\\", HostState.pendingOutput(&terminal));

    HostState.clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b[?1049h\x1b]22;text\x1b\\\x1b[?1049l");
    try std.testing.expectEqualStrings("crosshair", KittyState.pointerShape(&terminal));
}

test "kitty multiple cursor support clear and empty queries" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[> q\x1b[>100 q\x1b[>101 q\x1b[>0;4 q");

    try std.testing.expectEqual(@as(u16, 0), KittyState.multipleCursorCount(&terminal));
    try std.testing.expectEqualStrings("\x1b[>1;2;3;29;30;40;100;101 q\x1b[>100 q\x1b[>101;30:0;40:0 q", HostState.pendingOutput(&terminal));
}

test "xterm pointer mode stores bounded resource value" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expectEqual(@as(u2, 1), HostState.pointerMode(&terminal));
    try stream.nextSlice("\x1b[>2p");
    try std.testing.expectEqual(@as(u2, 2), HostState.pointerMode(&terminal));

    try stream.nextSlice("\x1b[>9p");
    try std.testing.expectEqual(@as(u2, 3), HostState.pointerMode(&terminal));

    try stream.nextSlice("\x1b[>p");
    try std.testing.expectEqual(@as(u2, 1), HostState.pointerMode(&terminal));
}

test "kitty color stack OSC 30001 and 30101 track depth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]30001\x1b\\\x1b]30001\x1b\\\x1b]30101\x1b\\");
    try std.testing.expectEqual(@as(u16, 1), KittyState.colorStackDepth(&terminal));
}

test "kitty OSC 21 sets queries and resets terminal colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]21;foreground=#112233;background=rgb:44/55/66;cursor=\x1b\\");
    try stream.nextSlice("\x1b]21;foreground=?;background=?;cursor=?;no_such=?\x1b\\");

    const colors = HostState.terminalColorState(&terminal);
    try std.testing.expectEqual(Grid.Color{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Grid.Color{ .r = 0x44, .g = 0x55, .b = 0x66 }, colors.background);
    try std.testing.expectEqual(@as(?Grid.Color, null), colors.cursor);
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:11/22/33\x1b\\\x1b]21;background=rgb:44/55/66\x1b\\\x1b]21;cursor=\x1b\\\x1b]21;no_such=?\x1b\\", HostState.pendingOutput(&terminal));

    try stream.nextSlice("\x1b]21;foreground;background\x1b\\");
    try std.testing.expectEqual(Grid.default_fg, HostState.terminalColorState(&terminal).foreground);
    try std.testing.expectEqual(Grid.default_bg, HostState.terminalColorState(&terminal).background);
}

test "xterm OSC colors set query and reset palette and dynamic colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]4;1;#010203\x1b\\\x1b]10;#aabbcc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;red\x1b\\");
    try stream.nextSlice("\x1b]4;1;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");

    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, HostState.terminalColorState(&terminal).palette[1]);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:01/02/03\x1b\\\x1b]10;rgb:aa/bb/cc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;rgb:ff/00/00\x1b\\", HostState.pendingOutput(&terminal));

    try stream.nextSlice("\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    try std.testing.expectEqual(Grid.Color{ .r = 205, .g = 49, .b = 49 }, HostState.terminalColorState(&terminal).palette[1]);
    try std.testing.expectEqual(Grid.default_fg, HostState.terminalColorState(&terminal).foreground);
    try std.testing.expectEqual(Grid.default_bg, HostState.terminalColorState(&terminal).background);
    try std.testing.expectEqual(@as(?Grid.Color, null), HostState.terminalColorState(&terminal).cursor);
}

test "xterm extra dynamic colors set query and reset host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]13;#010203\x1b\\\x1b]14;#040506\x1b\\\x1b]15;#070809\x1b\\\x1b]16;#0a0b0c\x1b\\\x1b]17;#0d0e0f\x1b\\\x1b]18;#101112\x1b\\\x1b]19;#131415\x1b\\");
    try stream.nextSlice("\x1b]13;?\x1b\\\x1b]14;?\x1b\\\x1b]15;?\x1b\\\x1b]16;?\x1b\\\x1b]17;?\x1b\\\x1b]18;?\x1b\\\x1b]19;?\x1b\\");

    const colors = HostState.terminalColorState(&terminal);
    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, colors.pointer_foreground.?);
    try std.testing.expectEqual(Grid.Color{ .r = 4, .g = 5, .b = 6 }, colors.pointer_background.?);
    try std.testing.expectEqual(Grid.Color{ .r = 7, .g = 8, .b = 9 }, colors.tektronix_foreground.?);
    try std.testing.expectEqual(Grid.Color{ .r = 10, .g = 11, .b = 12 }, colors.tektronix_background.?);
    try std.testing.expectEqual(Grid.Color{ .r = 13, .g = 14, .b = 15 }, colors.selection_background.?);
    try std.testing.expectEqual(Grid.Color{ .r = 16, .g = 17, .b = 18 }, colors.tektronix_cursor.?);
    try std.testing.expectEqual(Grid.Color{ .r = 19, .g = 20, .b = 21 }, colors.selection_foreground.?);
    try std.testing.expectEqualStrings("\x1b]13;rgb:01/02/03\x1b\\\x1b]14;rgb:04/05/06\x1b\\\x1b]15;rgb:07/08/09\x1b\\\x1b]16;rgb:0a/0b/0c\x1b\\\x1b]17;rgb:0d/0e/0f\x1b\\\x1b]18;rgb:10/11/12\x1b\\\x1b]19;rgb:13/14/15\x1b\\", HostState.pendingOutput(&terminal));

    HostState.clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b]113\x1b\\\x1b]114\x1b\\\x1b]115\x1b\\\x1b]116\x1b\\\x1b]117\x1b\\\x1b]118\x1b\\\x1b]119\x1b\\");
    const reset = HostState.terminalColorState(&terminal);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.pointer_foreground);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.pointer_background);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.tektronix_foreground);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.tektronix_background);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.selection_background);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.tektronix_cursor);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.selection_foreground);
}

test "xterm special colors via OSC 5 and OSC 4 special offsets" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]5;0;#010203;1;#040506\x1b\\\x1b]4;258;#070809;260;#0a0b0c\x1b\\");
    try stream.nextSlice("\x1b]5;0;?;1;?\x1b\\\x1b]4;258;?;260;?\x1b\\");

    const colors = HostState.terminalColorState(&terminal);
    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, colors.special_palette[0].?);
    try std.testing.expectEqual(Grid.Color{ .r = 4, .g = 5, .b = 6 }, colors.special_palette[1].?);
    try std.testing.expectEqual(Grid.Color{ .r = 7, .g = 8, .b = 9 }, colors.special_palette[2].?);
    try std.testing.expectEqual(Grid.Color{ .r = 10, .g = 11, .b = 12 }, colors.special_palette[4].?);
    try std.testing.expectEqualStrings("\x1b]5;0;rgb:01/02/03\x1b\\\x1b]5;1;rgb:04/05/06\x1b\\\x1b]4;258;rgb:07/08/09\x1b\\\x1b]4;260;rgb:0a/0b/0c\x1b\\", HostState.pendingOutput(&terminal));

    HostState.clearPendingOutput(&terminal);
    try stream.nextSlice("\x1b]104;258;260\x1b\\");
    const reset = HostState.terminalColorState(&terminal);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.special_palette[2]);
    try std.testing.expectEqual(@as(?Grid.Color, null), reset.special_palette[4]);
}

test "kitty color stack restores terminal color snapshots" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    try stream.nextSlice("\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b]30101\x1b\\");

    try std.testing.expectEqual(@as(u16, 0), KittyState.colorStackDepth(&terminal));
    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, HostState.terminalColorState(&terminal).foreground);
    try std.testing.expectEqual(Grid.Color{ .r = 4, .g = 5, .b = 6 }, HostState.terminalColorState(&terminal).palette[1]);
}
