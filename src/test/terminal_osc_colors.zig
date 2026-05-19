//! OSC and terminal color protocol tests.

const std = @import("std");
const action = @import("../action.zig");
const host_state = @import("../host/state.zig");
const kitty_state = @import("../kitty/state.zig");
const terminal_mod = @import("../terminal.zig");
const screen_mod = @import("../screen.zig");

const Action = action;
const HostState = host_state;
const KittyState = kitty_state;
const Terminal = terminal_mod.Terminal;
const Screen = screen_mod.Screen;
const Grid = Screen;

fn feedSlice(terminal: *Terminal, bytes: []const u8) void {
    terminal.parser_queue.feedSliceChecked(bytes) catch unreachable;
}

fn apply(terminal: *Terminal) void {
    Action.apply(terminal);
}

fn applyLimit(terminal: *Terminal, max_events: u32) Action.ApplySummary {
    return Action.applyLimit(terminal, max_events);
}

test "applyLimit returns typed OSC title payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]0;My Title\x07");
    const result = applyLimit(&terminal, 1);
    try std.testing.expectEqualStrings("My Title", result.latest_title.?);
}

test "OSC 8 assigns link ids and preserves URI lookup" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]8;;https://example.com\x07abc\x1b]8;;\x07z");
    apply(&terminal);

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

    feedSlice(&terminal, "\x1b]52;c;Zm9v\x07");
    apply(&terminal);
    try std.testing.expectEqualStrings("c;Zm9v", HostState.pendingClipboardSet(&terminal).?);
    HostState.clearPendingClipboardSet(&terminal);
    try std.testing.expectEqual(@as(?[]const u8, null), HostState.pendingClipboardSet(&terminal));
}

test "OSC 52 decoded clipboard drain clears pending request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]52;c;SG93bA==\x07");
    apply(&terminal);

    const text = (try HostState.drainPendingClipboardSet(&terminal, allocator)).?;
    defer allocator.free(text);
    try std.testing.expectEqualStrings("Howl", text);
    try std.testing.expectEqual(@as(?[]const u8, null), HostState.pendingClipboardSet(&terminal));
}

test "OSC 52 query clipboard drain clears without request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]52;c;?\x07");
    apply(&terminal);

    try std.testing.expectEqual(@as(?[]u8, null), try HostState.drainPendingClipboardSet(&terminal, allocator));
    try std.testing.expectEqual(@as(?[]const u8, null), HostState.pendingClipboardSet(&terminal));
}

test "kitty clipboard OSC 5522 and mode query use host-neutral state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b[?5522h\x1b[?5522$p\x1b]5522;type=write;AAAA\x1b\\");
    apply(&terminal);

    try std.testing.expect(HostState.kittyClipboardMode(&terminal));
    try std.testing.expectEqualStrings("\x1b[?5522;1$y", HostState.pendingOutput(&terminal));
    try std.testing.expectEqualStrings("type=write;AAAA", HostState.pendingClipboardSet(&terminal).?);
}

test "kitty file transfer and text sizing OSC payloads are retained" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]5113;cmd=data;AAAA\x1b\\\x1b]66;s=2;Hi\x1b\\");
    apply(&terminal);

    try std.testing.expectEqualStrings("cmd=data;AAAA", KittyState.fileTransferRequest(&terminal).?);
    try std.testing.expectEqualStrings("s=2;Hi", KittyState.textSizeRequest(&terminal).?);
}

test "kitty shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");
    apply(&terminal);

    const mark = KittyState.shellMark(&terminal);
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);
}

test "kitty notification OSC 99 queues host-neutral request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]99;i=1:d=0;Hello\x1b\\\x1b]99;i=1:p=body;World\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 2), KittyState.notificationCount(&terminal));
    try std.testing.expectEqualStrings("i=1:d=0", KittyState.notificationAt(&terminal, 0).?.metadata);
    try std.testing.expectEqualStrings("Hello", KittyState.notificationAt(&terminal, 0).?.payload);
    try std.testing.expectEqualStrings("i=1:p=body", KittyState.notificationAt(&terminal, 1).?.metadata);
    try std.testing.expectEqualStrings("World", KittyState.notificationAt(&terminal, 1).?.payload);
}

test "kitty notification OSC 9 alias queues host-neutral request" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]9;i=3:p=body;Alias\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 1), KittyState.notificationCount(&terminal));
    try std.testing.expectEqualStrings("i=3:p=body", KittyState.notificationAt(&terminal, 0).?.metadata);
    try std.testing.expectEqualStrings("Alias", KittyState.notificationAt(&terminal, 0).?.payload);
}

test "kitty pointer shape OSC 22 maintains per-screen stack and replies to queries" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]22;pointer\x1b\\\x1b]22;>wait,crosshair\x1b\\\x1b]22;?__current__,pointer,no-such\x1b\\");
    apply(&terminal);

    try std.testing.expectEqualStrings("crosshair", KittyState.pointerShape(&terminal));
    try std.testing.expectEqualStrings("\x1b]22;crosshair,1,0\x1b\\", HostState.pendingOutput(&terminal));

    HostState.clearPendingOutput(&terminal);
    feedSlice(&terminal, "\x1b[?1049h\x1b]22;text\x1b\\\x1b[?1049l");
    apply(&terminal);
    try std.testing.expectEqualStrings("crosshair", KittyState.pointerShape(&terminal));
}

test "kitty multiple cursor support clear and empty queries" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b[> q\x1b[>100 q\x1b[>101 q\x1b[>0;4 q");
    apply(&terminal);

    try std.testing.expectEqual(@as(u16, 0), KittyState.multipleCursorCount(&terminal));
    try std.testing.expectEqualStrings("\x1b[>1;2;3;29;30;40;100;101 q\x1b[>100 q\x1b[>101;30:0;40:0 q", HostState.pendingOutput(&terminal));
}

test "xterm pointer mode stores bounded resource value" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    try std.testing.expectEqual(@as(u2, 1), HostState.pointerMode(&terminal));
    feedSlice(&terminal, "\x1b[>2p");
    apply(&terminal);
    try std.testing.expectEqual(@as(u2, 2), HostState.pointerMode(&terminal));

    feedSlice(&terminal, "\x1b[>9p");
    apply(&terminal);
    try std.testing.expectEqual(@as(u2, 3), HostState.pointerMode(&terminal));

    feedSlice(&terminal, "\x1b[>p");
    apply(&terminal);
    try std.testing.expectEqual(@as(u2, 1), HostState.pointerMode(&terminal));
}

test "kitty color stack OSC 30001 and 30101 track depth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]30001\x1b\\\x1b]30001\x1b\\\x1b]30101\x1b\\");
    apply(&terminal);
    try std.testing.expectEqual(@as(u16, 1), KittyState.colorStackDepth(&terminal));
}

test "kitty OSC 21 sets queries and resets terminal colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]21;foreground=#112233;background=rgb:44/55/66;cursor=\x1b\\");
    feedSlice(&terminal, "\x1b]21;foreground=?;background=?;cursor=?;no_such=?\x1b\\");
    apply(&terminal);

    const colors = HostState.terminalColorState(&terminal);
    try std.testing.expectEqual(Grid.Color{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Grid.Color{ .r = 0x44, .g = 0x55, .b = 0x66 }, colors.background);
    try std.testing.expectEqual(@as(?Grid.Color, null), colors.cursor);
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:11/22/33\x1b\\\x1b]21;background=rgb:44/55/66\x1b\\\x1b]21;cursor=\x1b\\\x1b]21;no_such=?\x1b\\", HostState.pendingOutput(&terminal));

    feedSlice(&terminal, "\x1b]21;foreground;background\x1b\\");
    apply(&terminal);
    try std.testing.expectEqual(Grid.default_fg, HostState.terminalColorState(&terminal).foreground);
    try std.testing.expectEqual(Grid.default_bg, HostState.terminalColorState(&terminal).background);
}

test "xterm OSC colors set query and reset palette and dynamic colors" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]4;1;#010203\x1b\\\x1b]10;#aabbcc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;red\x1b\\");
    feedSlice(&terminal, "\x1b]4;1;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, HostState.terminalColorState(&terminal).palette[1]);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:01/02/03\x1b\\\x1b]10;rgb:aa/bb/cc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;rgb:ff/00/00\x1b\\", HostState.pendingOutput(&terminal));

    feedSlice(&terminal, "\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    apply(&terminal);
    try std.testing.expectEqual(Grid.Color{ .r = 205, .g = 49, .b = 49 }, HostState.terminalColorState(&terminal).palette[1]);
    try std.testing.expectEqual(Grid.default_fg, HostState.terminalColorState(&terminal).foreground);
    try std.testing.expectEqual(Grid.default_bg, HostState.terminalColorState(&terminal).background);
    try std.testing.expectEqual(@as(?Grid.Color, null), HostState.terminalColorState(&terminal).cursor);
}

test "kitty color stack restores terminal color snapshots" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 8);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    feedSlice(&terminal, "\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b]30101\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(u16, 0), KittyState.colorStackDepth(&terminal));
    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, HostState.terminalColorState(&terminal).foreground);
    try std.testing.expectEqual(Grid.Color{ .r = 4, .g = 5, .b = 6 }, HostState.terminalColorState(&terminal).palette[1]);
}
