//! Responsibility: map OSC parser events into typed terminal actions.
//! Ownership: interpret OSC action mapping.
//! Reason: keep string-protocol meaning separate from the top-level action router.

const std = @import("std");
const action_types = @import("action_types.zig");
const parser_events = @import("parser_events.zig");
const kitty_actions = @import("kitty_actions.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(kind: parser_events.OscKind, command: ?u16, payload: []const u8) ?SemanticEvent {
    if (command) |cmd| switch (cmd) {
        22 => return SemanticEvent{ .kitty_pointer_shape = kitty_actions.parsePointerShape(payload) },
        4, 10, 11, 12, 21, 104, 110, 111, 112 => return SemanticEvent{ .terminal_color_control = .{ .command = cmd, .payload = payload } },
        9, 99 => if (kitty_actions.parseNotification(payload)) |notification| return SemanticEvent{ .kitty_notification = notification },
        133 => if (kitty_actions.parseShellMark(payload)) |mark| return SemanticEvent{ .kitty_shell_mark = mark },
        66 => return SemanticEvent{ .kitty_text_size = payload },
        5522 => return SemanticEvent{ .clipboard_set = payload },
        5113 => return SemanticEvent{ .kitty_file_transfer = payload },
        30001 => return SemanticEvent{ .kitty_color_stack = .push },
        30101 => return SemanticEvent{ .kitty_color_stack = .pop },
        else => {},
    };
    return switch (kind) {
        .hyperlink => blk: {
            const separator = std.mem.indexOfScalar(u8, payload, ';') orelse break :blk null;
            const uri = payload[separator + 1 ..];
            if (uri.len == 0) break :blk SemanticEvent.hyperlink_clear;
            break :blk SemanticEvent{ .hyperlink_set = uri };
        },
        .clipboard => SemanticEvent{ .clipboard_set = payload },
        else => null,
    };
}
