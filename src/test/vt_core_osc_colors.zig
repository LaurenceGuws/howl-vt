//! Responsibility: OSC and color-control host-neutral coverage.
//! Ownership: vt-core OSC and color protocol tests.
//! Reason: keep OSC/title/color behavior explicit without bloating the main vt-core facade.

const std = @import("std");
const vt = @import("vt_core");
const grid_owner = @import("../grid.zig");

const Grid = grid_owner;

test "latestTitleSet returns typed OSC title payload" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]0;My Title\x07");
    try std.testing.expectEqualStrings("My Title", vt_core.latestTitleSet().?);
}

test "OSC 8 assigns link ids and preserves URI lookup" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]8;;https://example.com\x07abc\x1b]8;;\x07z");
    vt_core.apply();

    const first = vt_core.screen().cellInfoAt(0, 0).attrs.link_id;
    const second = vt_core.screen().cellInfoAt(0, 1).attrs.link_id;
    const third = vt_core.screen().cellInfoAt(0, 2).attrs.link_id;
    const trailing = vt_core.screen().cellInfoAt(0, 3).attrs.link_id;
    try std.testing.expect(first != 0);
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(first, third);
    try std.testing.expectEqual(@as(u32, 0), trailing);
    try std.testing.expectEqualStrings("https://example.com", vt_core.hyperlinkUriForId(first).?);
}

test "OSC 52 produces pending clipboard request" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]52;c;Zm9v\x07");
    vt_core.apply();
    try std.testing.expectEqualStrings("c;Zm9v", vt_core.pendingClipboardSet().?);
    vt_core.clearPendingClipboardSet();
    try std.testing.expectEqual(@as(?[]const u8, null), vt_core.pendingClipboardSet());
}

test "kitty clipboard OSC 5522 and mode query use host-neutral state" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[?5522h\x1b[?5522$p\x1b]5522;type=write;AAAA\x1b\\");
    vt_core.apply();

    try std.testing.expect(vt_core.kittyClipboardMode());
    try std.testing.expectEqualStrings("\x1b[?5522;1$y", vt_core.pendingOutput());
    try std.testing.expectEqualStrings("type=write;AAAA", vt_core.pendingClipboardSet().?);
}

test "kitty file transfer and text sizing OSC payloads are retained" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]5113;cmd=data;AAAA\x1b\\\x1b]66;s=2;Hi\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings("cmd=data;AAAA", vt_core.kittyFileTransferRequest().?);
    try std.testing.expectEqualStrings("s=2;Hi", vt_core.kittyTextSizeRequest().?);
}

test "kitty shell integration OSC 133 records latest mark" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]133;C;cmdline=ls\x07\x1b]133;D;2\x07");
    vt_core.apply();

    const mark = vt_core.kittyShellMark();
    try std.testing.expectEqual(@as(u8, 'D'), mark.kind);
    try std.testing.expectEqual(@as(?i32, 2), mark.status);
    try std.testing.expectEqualStrings("2", mark.metadata);
}

test "kitty notification OSC 99 queues host-neutral request" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]99;i=1:d=0;Hello\x1b\\\x1b]99;i=1:p=body;World\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 2), vt_core.kittyNotificationCount());
    try std.testing.expectEqualStrings("i=1:d=0", vt_core.kittyNotificationAt(0).?.metadata);
    try std.testing.expectEqualStrings("Hello", vt_core.kittyNotificationAt(0).?.payload);
    try std.testing.expectEqualStrings("i=1:p=body", vt_core.kittyNotificationAt(1).?.metadata);
    try std.testing.expectEqualStrings("World", vt_core.kittyNotificationAt(1).?.payload);
}

test "kitty notification OSC 9 alias queues host-neutral request" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]9;i=3:p=body;Alias\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyNotificationCount());
    try std.testing.expectEqualStrings("i=3:p=body", vt_core.kittyNotificationAt(0).?.metadata);
    try std.testing.expectEqualStrings("Alias", vt_core.kittyNotificationAt(0).?.payload);
}

test "kitty pointer shape OSC 22 maintains per-screen stack and replies to queries" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]22;pointer\x1b\\\x1b]22;>wait,crosshair\x1b\\\x1b]22;?__current__,pointer,no-such\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings("crosshair", vt_core.kittyPointerShape());
    try std.testing.expectEqualStrings("\x1b]22;crosshair,1,0\x1b\\", vt_core.pendingOutput());

    vt_core.clearPendingOutput();
    vt_core.feedSlice("\x1b[?1049h\x1b]22;text\x1b\\\x1b[?1049l");
    vt_core.apply();
    try std.testing.expectEqualStrings("crosshair", vt_core.kittyPointerShape());
}

test "kitty multiple cursor support clear and empty queries" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b[> q\x1b[>100 q\x1b[>101 q\x1b[>0;4 q");
    vt_core.apply();

    try std.testing.expectEqual(@as(u16, 0), vt_core.kittyMultipleCursorCount());
    try std.testing.expectEqualStrings("\x1b[>1;2;3;29;30;40;100;101 q\x1b[>100 q\x1b[>101;30:0;40:0 q", vt_core.pendingOutput());
}

test "xterm pointer mode stores bounded resource value" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    try std.testing.expectEqual(@as(u2, 1), vt_core.pointerMode());
    vt_core.feedSlice("\x1b[>2p");
    vt_core.apply();
    try std.testing.expectEqual(@as(u2, 2), vt_core.pointerMode());

    vt_core.feedSlice("\x1b[>9p");
    vt_core.apply();
    try std.testing.expectEqual(@as(u2, 3), vt_core.pointerMode());

    vt_core.feedSlice("\x1b[>p");
    vt_core.apply();
    try std.testing.expectEqual(@as(u2, 1), vt_core.pointerMode());
}

test "kitty color stack OSC 30001 and 30101 track depth" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]30001\x1b\\\x1b]30001\x1b\\\x1b]30101\x1b\\");
    vt_core.apply();
    try std.testing.expectEqual(@as(u16, 1), vt_core.kittyColorStackDepth());
}

test "kitty OSC 21 sets queries and resets terminal colors" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]21;foreground=#112233;background=rgb:44/55/66;cursor=\x1b\\");
    vt_core.feedSlice("\x1b]21;foreground=?;background=?;cursor=?;no_such=?\x1b\\");
    vt_core.apply();

    const colors = vt_core.terminalColorState();
    try std.testing.expectEqual(Grid.Color{ .r = 0x11, .g = 0x22, .b = 0x33 }, colors.foreground);
    try std.testing.expectEqual(Grid.Color{ .r = 0x44, .g = 0x55, .b = 0x66 }, colors.background);
    try std.testing.expectEqual(@as(?Grid.Color, null), colors.cursor);
    try std.testing.expectEqualStrings("\x1b]21;foreground=rgb:11/22/33\x1b\\\x1b]21;background=rgb:44/55/66\x1b\\\x1b]21;cursor=\x1b\\\x1b]21;no_such=?\x1b\\", vt_core.pendingOutput());

    vt_core.feedSlice("\x1b]21;foreground;background\x1b\\");
    vt_core.apply();
    try std.testing.expectEqual(Grid.default_fg, vt_core.terminalColorState().foreground);
    try std.testing.expectEqual(Grid.default_bg, vt_core.terminalColorState().background);
}

test "xterm OSC colors set query and reset palette and dynamic colors" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]4;1;#010203\x1b\\\x1b]10;#aabbcc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;red\x1b\\");
    vt_core.feedSlice("\x1b]4;1;?\x1b\\\x1b]10;?\x1b\\\x1b]11;?\x1b\\\x1b]12;?\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, vt_core.terminalColorState().palette[1]);
    try std.testing.expectEqualStrings("\x1b]4;1;rgb:01/02/03\x1b\\\x1b]10;rgb:aa/bb/cc\x1b\\\x1b]11;rgb:0d/0e/0f\x1b\\\x1b]12;rgb:ff/00/00\x1b\\", vt_core.pendingOutput());

    vt_core.feedSlice("\x1b]104;1\x1b\\\x1b]110\x1b\\\x1b]111\x1b\\\x1b]112\x1b\\");
    vt_core.apply();
    try std.testing.expectEqual(Grid.Color{ .r = 205, .g = 49, .b = 49 }, vt_core.terminalColorState().palette[1]);
    try std.testing.expectEqual(Grid.default_fg, vt_core.terminalColorState().foreground);
    try std.testing.expectEqual(Grid.default_bg, vt_core.terminalColorState().background);
    try std.testing.expectEqual(@as(?Grid.Color, null), vt_core.terminalColorState().cursor);
}

test "kitty color stack restores terminal color snapshots" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b]21;foreground=#010203;1=#040506\x1b\\\x1b]30001\x1b\\");
    vt_core.feedSlice("\x1b]21;foreground=#aabbcc;1=#ddeeff\x1b\\\x1b]30101\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(u16, 0), vt_core.kittyColorStackDepth());
    try std.testing.expectEqual(Grid.Color{ .r = 1, .g = 2, .b = 3 }, vt_core.terminalColorState().foreground);
    try std.testing.expectEqual(Grid.Color{ .r = 4, .g = 5, .b = 6 }, vt_core.terminalColorState().palette[1]);
}
