//! Responsibility: map private CSI sequences into typed terminal actions.
//! Ownership: interpret private CSI action mapping.
//! Reason: keep DEC/private mode recognition out of the general CSI router.

const std = @import("std");

const action_types = @import("action_types.zig");
const csi_params = @import("csi_params.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, count: u8, leader: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (leader == '?' and final == 'u') return SemanticEvent.kitty_keyboard_query;
    if (leader == '?' and final == 'g') return SemanticEvent{ .key_format_query = @intCast(@min(csi_params.paramOrDefault0(params[0]), std.math.maxInt(u8))) };
    if (leader == '?' and final == 'J') return SemanticEvent{ .selective_erase_display = csi_params.eraseMode(params[0]) };
    if (leader == '?' and final == 'K') return SemanticEvent{ .selective_erase_line = csi_params.eraseMode(params[0]) };
    if (leader == '?' and final == 'W' and csi_params.paramOrDefault0(params[0]) == 5) return SemanticEvent.reset_default_tab_stops;
    if (leader == '?' and count >= 1) {
        if (final == 'm' and csi_params.paramOrDefault0(params[0]) == 4) return SemanticEvent.modify_other_keys_query;
        if (final == 'p' and csi_params.intermediatesLenHas(intermediates, intermediates_len, '$')) {
            return SemanticEvent{ .dec_mode_query = csi_params.paramOrDefault0(params[0]) };
        }
        if (final == 's' and intermediates_len == 0) return SemanticEvent{ .dec_mode_save = csi_params.collectParams(params, count) };
        if (final == 'r' and intermediates_len == 0) return SemanticEvent{ .dec_mode_restore = csi_params.collectParams(params, count) };
        if (final == 'n') return switch (csi_params.paramOrDefault0(params[0])) {
            6 => SemanticEvent.dec_cursor_position_report,
            55, 56 => |status| SemanticEvent{ .dec_device_status_report = status },
            else => null,
        };
        return switch (params[0]) {
            25 => switch (final) {
                'h' => SemanticEvent{ .cursor_visible = true },
                'l' => SemanticEvent{ .cursor_visible = false },
                else => null,
            },
            7 => switch (final) {
                'h' => SemanticEvent{ .auto_wrap = true },
                'l' => SemanticEvent{ .auto_wrap = false },
                else => null,
            },
            6 => switch (final) {
                'h' => SemanticEvent{ .origin_mode = true },
                'l' => SemanticEvent{ .origin_mode = false },
                else => null,
            },
            1 => switch (final) {
                'h' => SemanticEvent{ .application_cursor_keys = true },
                'l' => SemanticEvent{ .application_cursor_keys = false },
                else => null,
            },
            66 => switch (final) {
                'h' => SemanticEvent{ .application_keypad = true },
                'l' => SemanticEvent{ .application_keypad = false },
                else => null,
            },
            69 => switch (final) {
                'h' => SemanticEvent{ .left_right_margin_mode = true },
                'l' => SemanticEvent{ .left_right_margin_mode = false },
                else => null,
            },
            1004 => switch (final) {
                'h' => SemanticEvent{ .focus_reporting = true },
                'l' => SemanticEvent{ .focus_reporting = false },
                else => null,
            },
            2004 => switch (final) {
                'h' => SemanticEvent{ .bracketed_paste = true },
                'l' => SemanticEvent{ .bracketed_paste = false },
                else => null,
            },
            5522 => switch (final) {
                'h' => SemanticEvent{ .kitty_clipboard_mode = true },
                'l' => SemanticEvent{ .kitty_clipboard_mode = false },
                else => null,
            },
            9 => switch (final) {
                'h' => SemanticEvent.mouse_tracking_x10,
                'l' => SemanticEvent.mouse_tracking_off,
                else => null,
            },
            1000 => switch (final) {
                'h' => SemanticEvent.mouse_tracking_normal,
                'l' => SemanticEvent.mouse_tracking_off,
                else => null,
            },
            1002 => switch (final) {
                'h' => SemanticEvent.mouse_tracking_button_event,
                'l' => SemanticEvent.mouse_tracking_off,
                else => null,
            },
            1003 => switch (final) {
                'h' => SemanticEvent.mouse_tracking_any_event,
                'l' => SemanticEvent.mouse_tracking_off,
                else => null,
            },
            1005 => switch (final) {
                'h' => SemanticEvent{ .mouse_protocol_utf8 = true },
                'l' => SemanticEvent{ .mouse_protocol_utf8 = false },
                else => null,
            },
            1006 => switch (final) {
                'h' => SemanticEvent{ .mouse_protocol_sgr = true },
                'l' => SemanticEvent{ .mouse_protocol_sgr = false },
                else => null,
            },
            1015 => switch (final) {
                'h' => SemanticEvent{ .mouse_protocol_urxvt = true },
                'l' => SemanticEvent{ .mouse_protocol_urxvt = false },
                else => null,
            },
            47 => switch (final) {
                'h' => SemanticEvent{ .enter_alt_screen = .{ .clear = false, .save_cursor = false } },
                'l' => SemanticEvent{ .exit_alt_screen = .{ .restore_cursor = false } },
                else => null,
            },
            1047 => switch (final) {
                'h' => SemanticEvent{ .enter_alt_screen = .{ .clear = true, .save_cursor = false } },
                'l' => SemanticEvent{ .exit_alt_screen = .{ .restore_cursor = false } },
                else => null,
            },
            1049 => switch (final) {
                'h' => SemanticEvent{ .enter_alt_screen = .{ .clear = true, .save_cursor = true } },
                'l' => SemanticEvent{ .exit_alt_screen = .{ .restore_cursor = true } },
                else => null,
            },
            else => null,
        };
    }
    return null;
}
