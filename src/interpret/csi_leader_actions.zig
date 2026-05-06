//! Responsibility: map non-private CSI leader sequences into typed terminal actions.
//! Ownership: interpret CSI leader action mapping.
//! Reason: isolate kitty keyboard and device-attribute leader semantics.

const action_types = @import("action_types.zig");
const csi_params = @import("csi_params.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, count: u8, leader: u8) ?SemanticEvent {
    return switch (leader) {
        '>' => switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            'q' => if (csi_params.paramOrDefault0(params[0]) == 0) SemanticEvent.xtversion else null,
            'm' => if (csi_params.paramOrDefault0(params[0]) == 4) SemanticEvent{ .modify_other_keys_set = @intCast(@max(if (count >= 2) params[1] else 0, 0)) } else null,
            'n' => if (csi_params.paramOrDefault0(params[0]) == 4) SemanticEvent.modify_other_keys_disable else null,
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
