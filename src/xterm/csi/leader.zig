//! CSI leader-byte semantic event mapping.

const std = @import("std");
const events = @import("../../action/vocabulary.zig");
const params_mod = @import("params.zig");

const SemanticEvent = events.SemanticEvent;

pub fn process(final: u8, params: []const i32, leader: u8, intermediates: []const u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            'f' => keyFormatChange(params),
            'q' => multipleCursorOrXtVersion(params, intermediates),
            'm' => if (params_mod.paramAtOrDefault0(params, 0) == 4) SemanticEvent{ .modify_other_keys_set = @intCast(@max(if (params.len >= 2) params[1] else 0, 0)) } else null,
            'n' => if (params_mod.paramAtOrDefault0(params, 0) == 4) SemanticEvent.modify_other_keys_disable else null,
            'p' => pointerMode(params),
            'u' => SemanticEvent{ .kitty_keyboard_push = @intCast(@max(if (params.len != 0) params[0] else 0, 0)) },
            else => null,
        },
        '=' => switch (final) {
            'c' => SemanticEvent.tertiary_device_attributes,
            'u' => SemanticEvent{ .kitty_keyboard_set = .{ .flags = @intCast(@max(if (params.len != 0) params[0] else 0, 0)), .mode = @intCast(@max(if (params.len >= 2) params[1] else 1, 1)) } },
            else => null,
        },
        '<' => switch (final) {
            'u' => SemanticEvent{ .kitty_keyboard_pop = params_mod.paramAtOrDefault1(params, 0) },
            else => null,
        },
        else => null,
    };
}

fn multipleCursorOrXtVersion(params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (!params_mod.intermediatesHas(intermediates, ' ')) {
        return if (params_mod.paramAtOrDefault0(params, 0) == 0) SemanticEvent.xtversion else null;
    }
    if (params.len == 0) return SemanticEvent{ .kitty_multiple_cursor = .support_query };
    return switch (params_mod.paramAtOrDefault0(params, 0)) {
        0 => if (params.len >= 2 and params_mod.paramAtOrDefault0(params, 1) == 4) SemanticEvent{ .kitty_multiple_cursor = .clear_all } else null,
        100 => SemanticEvent{ .kitty_multiple_cursor = .cursor_query },
        101 => SemanticEvent{ .kitty_multiple_cursor = .color_query },
        else => null,
    };
}

fn keyFormatChange(params: []const i32) SemanticEvent {
    if (params.len == 0) return SemanticEvent{ .key_format_change = .{ .resource = null, .value = null } };
    const resource: u8 = @intCast(@min(params_mod.paramAtOrDefault0(params, 0), std.math.maxInt(u8)));
    if (params.len == 1) return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = null } };
    return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = params_mod.paramAtOrDefault0(params, 1) } };
}

fn pointerMode(params: []const i32) SemanticEvent {
    const value = if (params.len == 0) 1 else params_mod.paramAtOrDefault0(params, 0);
    return SemanticEvent{ .pointer_mode = @intCast(@min(value, 3)) };
}
