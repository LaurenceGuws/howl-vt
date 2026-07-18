const std = @import("std");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");

/// Physical key event with typed key identity and modifier state.
pub const KeyEvent = struct {
    key: keyboard.Key,
    mods: keyboard.Modifier = .{},
};

pub const FocusEvent = enum {
    in,
    out,
};

/// Host input accepted by the terminal embedding surface.
///
/// `bytes` carries committed text, while `key` carries a named or validated
/// Unicode physical-key event for terminal keyboard protocol encoding.
pub const Event = union(enum) {
    bytes: []const u8,
    key: KeyEvent,
    mouse: mouse.MouseEvent,
    focus: FocusEvent,
    paste: []const u8,
};

test "event owner exposes input union tags" {
    const key_event: Event = .{ .key = .{ .key = .{ .named = .enter } } };
    const focus_event: Event = .{ .focus = .in };

    try std.testing.expectEqual(@as(std.meta.Tag(Event), .key), std.meta.activeTag(key_event));
    try std.testing.expectEqual(@as(std.meta.Tag(Event), .focus), std.meta.activeTag(focus_event));
}
