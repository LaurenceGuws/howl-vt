//! Responsibility: map non-private CSI leader sequences into typed terminal actions.
//! Ownership: interpret CSI leader action mapping.
//! Reason: isolate kitty keyboard and device-attribute leader semantics.

const std = @import("std");

const types = @import("../actions/types.zig");
const params_mod = @import("params.zig");

const SemanticEvent = types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, count: u8, leader: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            'f' => keyFormatChange(params, count),
            'q' => multipleCursorOrXtVersion(params, count, intermediates, intermediates_len),
            'm' => if (params_mod.paramOrDefault0(params[0]) == 4) SemanticEvent{ .modify_other_keys_set = @intCast(@max(if (count >= 2) params[1] else 0, 0)) } else null,
            'n' => if (params_mod.paramOrDefault0(params[0]) == 4) SemanticEvent.modify_other_keys_disable else null,
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
            'u' => SemanticEvent{ .kitty_keyboard_pop = params_mod.paramOrDefault1(params[0]) },
            else => null,
        },
        else => null,
    };
}

fn multipleCursorOrXtVersion(params: [16]i32, count: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (!params_mod.intermediatesLenHas(intermediates, intermediates_len, ' ')) {
        return if (params_mod.paramOrDefault0(params[0]) == 0) SemanticEvent.xtversion else null;
    }
    if (count == 0) return SemanticEvent{ .kitty_multiple_cursor = .support_query };
    return switch (params_mod.paramOrDefault0(params[0])) {
        0 => if (count >= 2 and params_mod.paramOrDefault0(params[1]) == 4) SemanticEvent{ .kitty_multiple_cursor = .clear_all } else null,
        100 => SemanticEvent{ .kitty_multiple_cursor = .cursor_query },
        101 => SemanticEvent{ .kitty_multiple_cursor = .color_query },
        else => null,
    };
}

fn keyFormatChange(params: [16]i32, count: u8) SemanticEvent {
    if (count == 0) return SemanticEvent{ .key_format_change = .{ .resource = null, .value = null } };
    const resource: u8 = @intCast(@min(params_mod.paramOrDefault0(params[0]), std.math.maxInt(u8)));
    if (count == 1) return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = null } };
    return SemanticEvent{ .key_format_change = .{ .resource = resource, .value = params_mod.paramOrDefault0(params[1]) } };
}

fn pointerMode(params: [16]i32, count: u8) SemanticEvent {
    const value = if (count == 0) 1 else params_mod.paramOrDefault0(params[0]);
    return SemanticEvent{ .pointer_mode = @intCast(@min(value, 3)) };
}
