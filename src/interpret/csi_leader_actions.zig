//! Responsibility: map non-private CSI leader sequences into typed terminal actions.
//! Ownership: interpret CSI leader action mapping.
//! Reason: isolate kitty keyboard and device-attribute leader semantics.

const std = @import("std");

const action_types = @import("action_types.zig");
const csi_params = @import("csi_params.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, count: u8, leader: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            'f' => keyFormatChange(params, count),
            'q' => multipleCursorOrXtVersion(params, count, intermediates, intermediates_len),
            'm' => if (csi_params.paramOrDefault0(params[0]) == 4) SemanticEvent{ .modify_other_keys_set = @intCast(@max(if (count >= 2) params[1] else 0, 0)) } else null,
            'n' => if (csi_params.paramOrDefault0(params[0]) == 4) SemanticEvent.modify_other_keys_disable else null,
            'p' => pointerMode(params, count),
            'u' => SemanticEvent{ .kitty_keyboard_push = @intCast(@max(params[0], 0)) },
            else => null,
        },
        '=' => switch (final) {
            'c' => SemanticEvent.tertiary_device_attributes,
            'u' => SemanticEvent{ .kitty_keyboard_set = .{ .flags = @intCast(@max(params[0], 0)), .mode = @intCast(@max(if (count >= 2) params[1] else 1, 1)) } },
            else => null,
        },
        '<' => switch (final) {
            'u' => SemanticEvent{ .kitty_keyboard_pop = csi_params.paramOrDefault1(params[0]) },
            else => null,
        },
        else => null,
    };
}

fn multipleCursorOrXtVersion(params: [16]i32, count: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (!csi_params.intermediatesLenHas(intermediates, intermediates_len, ' ')) {
        return if (csi_params.paramOrDefault0(params[0]) == 0) SemanticEvent.xtversion else null;
    }
    if (count == 0) return SemanticEvent{ .kitty_multiple_cursor = .support_query };
    return switch (csi_params.paramOrDefault0(params[0])) {
        0 => if (count >= 2 and csi_params.paramOrDefault0(params[1]) == 4) SemanticEvent{ .kitty_multiple_cursor = .clear_all } else null,
        100 => SemanticEvent{ .kitty_multiple_cursor = .cursor_query },
        101 => SemanticEvent{ .kitty_multiple_cursor = .color_query },
        else => null,
    };
}

fn keyFormatChange(params: [16]i32, count: u8) SemanticEvent {
    if (count == 0) return SemanticEvent{ .key_format_change = .{ .resource = null, .value = null } };
    const resource: u8 = @intCast(@min(csi_params.paramOrDefault0(params[0]), std.math.maxInt(u8)));
    if (count == 1) return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = null } };
    return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = csi_params.paramOrDefault0(params[1]) } };
}

fn pointerMode(params: [16]i32, count: u8) SemanticEvent {
    const value = if (count == 0) 1 else csi_params.paramOrDefault0(params[0]);
    return SemanticEvent{ .pointer_mode = @intCast(@min(value, 3)) };
}
