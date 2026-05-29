const std = @import("std");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");

pub const KeyEvent = struct {
    key: keyboard.Key,
    mods: keyboard.Modifier = keyboard.mod_none,
};

pub const FocusEvent = enum {
    in,
    out,
};

pub const Event = union(enum) {
    bytes: []const u8,
    key: KeyEvent,
    mouse: mouse.MouseEvent,
    focus: FocusEvent,
    paste: []const u8,
};

test "event owner exposes input union tags" {
    const key_event: Event = .{ .key = .{ .key = keyboard.key_enter } };
    const focus_event: Event = .{ .focus = .in };

    try std.testing.expectEqual(@as(std.meta.Tag(Event), .key), std.meta.activeTag(key_event));
    try std.testing.expectEqual(@as(std.meta.Tag(Event), .focus), std.meta.activeTag(focus_event));
}
