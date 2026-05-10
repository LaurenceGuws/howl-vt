//! Responsibility: map parsed events into typed terminal actions.
//! Ownership: interpret action mapping.
//! Reason: separate escape parsing from vt-core consequences.

const types = @import("types.zig");
const apc = @import("apc.zig");
const parsed_events = @import("../parsed_events.zig");
const c0 = @import("c0.zig");
const csi = @import("csi.zig");
const dcs = @import("dcs.zig");
const esc = @import("esc.zig");
const kitty = @import("kitty.zig");
const osc = @import("osc.zig");

/// Parsed-event alias for action mapping.
const Event = parsed_events.Event;
pub const KittyGraphicsCommand = types.KittyGraphicsCommand;
pub const KittyShellMark = types.KittyShellMark;
pub const KittyNotificationCommand = types.KittyNotificationCommand;
pub const KittyPointerShapeCommand = types.KittyPointerShapeCommand;
pub const KittyColorStackCommand = types.KittyColorStackCommand;
pub const TerminalColorControlCommand = types.TerminalColorControlCommand;
pub const DcsPayloadKind = types.DcsPayloadKind;
pub const LegacyControlKind = types.LegacyControlKind;
pub const EscAction = esc.EscAction;
pub const SemanticEvent = types.SemanticEvent;
pub const ScreenAction = types.ScreenAction;
pub const ReportAction = types.ReportAction;
pub const ModeAction = types.ModeAction;
pub const KittyAction = types.KittyAction;
pub const HostAction = types.HostAction;

/// Map parsed event to terminal event when supported.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| return csi.process(sc.final, sc.params, sc.separators, sc.param_count, sc.leader, sc.private, sc.intermediates, sc.intermediates_len),
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return c0.process(c),
        .osc => |osc_event| return osc.process(osc_event.kind, osc_event.command, osc_event.payload),
        .esc_final => |final| return esc.process(final),
        .apc => |apc_data| return apc.process(apc_data),
        .dcs => |dcs_data| return dcs.process(dcs_data),
        .pm, .invalid_sequence => return null,
    }
}

pub fn screenAction(event: SemanticEvent) ?ScreenAction {
    return switch (event) {
        .cursor_up => |v| ScreenAction{ .cursor_up = v },
        .cursor_down => |v| ScreenAction{ .cursor_down = v },
        .cursor_forward => |v| ScreenAction{ .cursor_forward = v },
        .cursor_back => |v| ScreenAction{ .cursor_back = v },
        .cursor_next_line => |v| ScreenAction{ .cursor_next_line = v },
        .cursor_prev_line => |v| ScreenAction{ .cursor_prev_line = v },
        .cursor_horizontal_absolute => |v| ScreenAction{ .cursor_horizontal_absolute = v },
        .cursor_vertical_absolute => |v| ScreenAction{ .cursor_vertical_absolute = v },
        .cursor_position => |v| ScreenAction{ .cursor_position = .{ .row = v.row, .col = v.col } },
        .write_text => |v| ScreenAction{ .write_text = v },
        .write_codepoint => |v| ScreenAction{ .write_codepoint = v },
        .repeat_preceding => |v| ScreenAction{ .repeat_preceding = v },
        .line_feed => .line_feed,
        .next_line => .next_line,
        .reverse_index => .reverse_index,
        .carriage_return => .carriage_return,
        .backspace => .backspace,
        .horizontal_tab => .horizontal_tab,
        .horizontal_tab_forward => |v| ScreenAction{ .horizontal_tab_forward = v },
        .horizontal_tab_back => |v| ScreenAction{ .horizontal_tab_back = v },
        .horizontal_tab_set => .horizontal_tab_set,
        .tab_clear_current => .tab_clear_current,
        .tab_clear_all => .tab_clear_all,
        .cursor_visible => |v| ScreenAction{ .cursor_visible = v },
        .cursor_style => |v| ScreenAction{ .cursor_style = v },
        .auto_wrap => |v| ScreenAction{ .auto_wrap = v },
        .origin_mode => |v| ScreenAction{ .origin_mode = v },
        .insert_mode => |v| ScreenAction{ .insert_mode = v },
        .save_cursor => .save_cursor,
        .restore_cursor => .restore_cursor,
        .sgr => |v| ScreenAction{ .sgr = .{ .params = v.params, .separators = v.separators, .param_count = v.param_count } },
        .insert_lines => |v| ScreenAction{ .insert_lines = v },
        .delete_lines => |v| ScreenAction{ .delete_lines = v },
        .insert_chars => |v| ScreenAction{ .insert_chars = v },
        .delete_chars => |v| ScreenAction{ .delete_chars = v },
        .scroll_up_lines => |v| ScreenAction{ .scroll_up_lines = v },
        .scroll_down_lines => |v| ScreenAction{ .scroll_down_lines = v },
        .set_scroll_region => |v| ScreenAction{ .set_scroll_region = .{ .top = v.top, .bottom = v.bottom } },
        .reset_screen => .reset_screen,
        .erase_display => |v| ScreenAction{ .erase_display = v },
        .erase_line => |v| ScreenAction{ .erase_line = v },
        .selective_erase_display => |v| ScreenAction{ .selective_erase_display = v },
        .selective_erase_line => |v| ScreenAction{ .selective_erase_line = v },
        .erase_chars => |v| ScreenAction{ .erase_chars = v },
        .shift_left_columns => |v| ScreenAction{ .shift_left_columns = v },
        .shift_right_columns => |v| ScreenAction{ .shift_right_columns = v },
        .character_protection => |v| ScreenAction{ .character_protection = v },
        .rect_erase => |v| ScreenAction{ .rect_erase = v },
        .rect_selective_erase => |v| ScreenAction{ .rect_selective_erase = v },
        .rect_fill => |v| ScreenAction{ .rect_fill = .{ .area = v.area, .ch = v.ch } },
        .rect_copy => |v| ScreenAction{ .rect_copy = v },
        .rect_attrs_change => |v| ScreenAction{ .rect_attrs_change = .{ .area = v.area, .attrs = v.attrs, .reverse = v.reverse } },
        .insert_columns => |v| ScreenAction{ .insert_columns = v },
        .delete_columns => |v| ScreenAction{ .delete_columns = v },
        .attr_change_extent_rect => |v| ScreenAction{ .attr_change_extent_rect = v },
        .left_right_margin_mode => |v| ScreenAction{ .left_right_margin_mode = v },
        .set_left_right_margins => |v| ScreenAction{ .set_left_right_margins = .{ .left = v.left, .right = v.right } },
        .reset_default_tab_stops => .reset_default_tab_stops,
        else => null,
    };
}

pub fn reportAction(event: SemanticEvent) ?ReportAction {
    return switch (event) {
        .ansi_mode_query => |v| ReportAction{ .ansi_mode_query = v },
        .modify_other_keys_query => .modify_other_keys_query,
        .key_format_query => |v| ReportAction{ .key_format_query = v },
        .dec_mode_query => |v| ReportAction{ .dec_mode_query = v },
        .dcs_request_status => |v| ReportAction{ .dcs_request_status = v },
        .dcs_request_termcap => |v| ReportAction{ .dcs_request_termcap = v },
        .dcs_request_resource => |v| ReportAction{ .dcs_request_resource = v },
        .device_status_report => .device_status_report,
        .dec_device_status_report => |v| ReportAction{ .dec_device_status_report = v },
        .cursor_position_report => .cursor_position_report,
        .dec_cursor_position_report => .dec_cursor_position_report,
        .primary_device_attributes => .primary_device_attributes,
        .secondary_device_attributes => .secondary_device_attributes,
        .tertiary_device_attributes => .tertiary_device_attributes,
        .xtversion => .xtversion,
        .xttitlepos => .xttitlepos,
        .xtchecksum => |v| ReportAction{ .xtchecksum = v },
        .rect_checksum_request => |v| ReportAction{ .rect_checksum_request = .{ .request_id = v.request_id, .page = v.page, .area = v.area } },
        .selected_graphic_rendition_report => |v| ReportAction{ .selected_graphic_rendition_report = v },
        .presentation_state_report => |v| ReportAction{ .presentation_state_report = v },
        .displayed_extent_report => .displayed_extent_report,
        .parameters_report => |v| ReportAction{ .parameters_report = v },
        .xtreportcolors => .xtreportcolors,
        else => null,
    };
}

pub fn modeAction(event: SemanticEvent) ?ModeAction {
    return switch (event) {
        .enter_alt_screen => |v| ModeAction{ .enter_alt_screen = .{ .clear = v.clear, .save_cursor = v.save_cursor } },
        .exit_alt_screen => |v| ModeAction{ .exit_alt_screen = .{ .restore_cursor = v.restore_cursor } },
        .application_cursor_keys => |v| ModeAction{ .application_cursor_keys = v },
        .application_keypad => |v| ModeAction{ .application_keypad = v },
        .ansi_mode_set => |v| ModeAction{ .ansi_mode_set = v },
        .ansi_mode_reset => |v| ModeAction{ .ansi_mode_reset = v },
        .modify_other_keys_set => |v| ModeAction{ .modify_other_keys_set = v },
        .modify_other_keys_disable => .modify_other_keys_disable,
        .key_format_change => |v| ModeAction{ .key_format_change = v },
        .pointer_mode => |v| ModeAction{ .pointer_mode = v },
        .kitty_clipboard_mode => |v| ModeAction{ .kitty_clipboard_mode = v },
        .sixel_display_mode => |v| ModeAction{ .sixel_display_mode = v },
        .reverse_wraparound_mode => |v| ModeAction{ .reverse_wraparound_mode = v },
        .extended_reverse_wraparound_mode => |v| ModeAction{ .extended_reverse_wraparound_mode = v },
        .focus_reporting => |v| ModeAction{ .focus_reporting = v },
        .bracketed_paste => |v| ModeAction{ .bracketed_paste = v },
        .synchronized_output => |v| ModeAction{ .synchronized_output = v },
        .mouse_tracking_off => .mouse_tracking_off,
        .mouse_tracking_x10 => .mouse_tracking_x10,
        .mouse_tracking_normal => .mouse_tracking_normal,
        .mouse_tracking_button_event => .mouse_tracking_button_event,
        .mouse_tracking_any_event => .mouse_tracking_any_event,
        .mouse_protocol_utf8 => |v| ModeAction{ .mouse_protocol_utf8 = v },
        .mouse_protocol_sgr => |v| ModeAction{ .mouse_protocol_sgr = v },
        .mouse_protocol_urxvt => |v| ModeAction{ .mouse_protocol_urxvt = v },
        .dec_mode_save => |v| ModeAction{ .dec_mode_save = v },
        .dec_mode_restore => |v| ModeAction{ .dec_mode_restore = v },
        else => null,
    };
}

pub fn kittyAction(event: SemanticEvent) ?KittyAction {
    return switch (event) {
        .kitty_keyboard_set => |v| KittyAction{ .kitty_keyboard_set = .{ .flags = v.flags, .mode = v.mode } },
        .kitty_keyboard_query => .kitty_keyboard_query,
        .kitty_keyboard_push => |v| KittyAction{ .kitty_keyboard_push = v },
        .kitty_keyboard_pop => |v| KittyAction{ .kitty_keyboard_pop = v },
        .kitty_shell_mark => |v| KittyAction{ .kitty_shell_mark = v },
        .kitty_notification => |v| KittyAction{ .kitty_notification = v },
        .kitty_pointer_shape => |v| KittyAction{ .kitty_pointer_shape = v },
        .kitty_color_stack => |v| KittyAction{ .kitty_color_stack = v },
        .kitty_multiple_cursor => |v| KittyAction{ .kitty_multiple_cursor = v },
        .kitty_file_transfer => |v| KittyAction{ .kitty_file_transfer = v },
        .kitty_text_size => |v| KittyAction{ .kitty_text_size = v },
        .kitty_graphics => |v| KittyAction{ .kitty_graphics = v },
        else => null,
    };
}

pub fn hostAction(event: SemanticEvent) ?HostAction {
    return switch (event) {
        .color_control => |v| HostAction{ .color_control = v },
        .hyperlink_set => |v| HostAction{ .hyperlink_set = v },
        .hyperlink_clear => .hyperlink_clear,
        .clipboard_set => |v| HostAction{ .clipboard_set = v },
        .locator_reporting => |v| HostAction{ .locator_reporting = .{ .mode = v.mode, .unit = v.unit } },
        .locator_filter => |v| HostAction{ .locator_filter = v },
        .locator_events => |v| HostAction{ .locator_events = v },
        .locator_request => |v| HostAction{ .locator_request = v },
        .media_copy_request => |v| HostAction{ .media_copy_request = v },
        .dcs_payload => |v| HostAction{ .dcs_payload = v },
        .legacy_control => |v| HostAction{ .legacy_control = v },
        .reset_screen => .reset_screen,
        else => null,
    };
}
