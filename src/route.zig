const events = @import("vocabulary.zig");
const host_apply = @import("host_apply.zig");
const kitty_apply = @import("kitty/apply.zig");
const mode_apply = @import("mode.zig");
const report_apply = @import("report.zig");
const parsed_events = @import("parser/events.zig");
const c0 = @import("c0.zig");
const csi = @import("csi.zig");
const dcs = @import("dcs.zig");
const esc = @import("esc.zig");
const osc = @import("osc.zig");
const osc_color = @import("osc_color.zig");
const host_state = @import("host_state.zig");

/// Parsed-event alias for action mapping.
const Event = parsed_events.Event;
pub const SemanticEvent = events.SemanticEvent;

const ScreenAction = events.ScreenAction;
const ReportAction = events.ReportAction;
const ModeAction = events.ModeAction;
const KittyAction = events.KittyAction;
const HostAction = events.HostAction;

pub const EventEffect = struct {
    changed: bool,
    title_changed: bool,
};

/// Map parsed event to terminal event when supported.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| {
            const params = sc.params[0..sc.param_count];
            const intermediates = sc.intermediates[0..sc.intermediates_len];
            return csi.process(sc.final, params, sc.separators, sc.leader, sc.private, intermediates);
        },
        .invoke_charset, .configure_charset => return null,
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return c0.process(c0.fromByte(c)),
        .osc => |osc_event| return processOscEvent(osc_event),
        .esc_dispatch => |esc_dispatch| return esc.process(esc_dispatch.final),
        .apc => return null,
        .dcs => |dcs_data| return dcs.process(dcs_data),
        .pm, .invalid_sequence => return null,
    }
}

fn processOscEvent(osc_event: anytype) ?SemanticEvent {
    const semantic = osc.process(osc_event) orelse return null;
    if (semantic == .color_control) {
        if (osc_color.cursorColorEvent(semantic.color_control)) |cursor_event| return cursor_event;
    }
    return semantic;
}

pub fn apply(vt: anytype, event: Event) host_state.ApplyError!EventEffect {
    switch (event) {
        .invoke_charset => |slot| {
            vt.gl_index = slot;
            return .{ .changed = true, .title_changed = false };
        },
        .configure_charset => |cfg| {
            switch (cfg.slot) {
                0 => vt.g0_designation = cfg.designation,
                1 => vt.g1_designation = cfg.designation,
                else => unreachable,
            }
            return .{ .changed = true, .title_changed = false };
        },
        else => {},
    }

    const semantic = process(event) orelse return .{ .changed = false, .title_changed = false };
    const changed = try applySemantic(vt, semantic);
    if (legacyCursorColorControl(event)) |host_action| {
        try host_apply.apply(vt, host_action);
    }
    return .{ .changed = changed, .title_changed = semantic == .title_set };
}

fn legacyCursorColorControl(event: Event) ?HostAction {
    const osc_event = switch (event) {
        .osc => |value| value,
        else => return null,
    };
    const semantic = osc.process(osc_event) orelse return null;
    if (semantic != .color_control) return null;
    if (osc_color.cursorColorEvent(semantic.color_control) == null) return null;
    return .{ .color_control = semantic.color_control };
}

fn applySemantic(vt: anytype, event: SemanticEvent) host_state.ApplyError!bool {
    if (event == .reset_screen) {
        vt.resetScreen();
        return true;
    }
    switch (event) {
        .save_cursor => {
            vt.saveCursor();
            return true;
        },
        .restore_cursor => {
            vt.restoreCursor();
            return true;
        },
        .enter_alt_screen => |opts| {
            vt.switchScreenMode(true, opts.clear, opts.save_cursor);
            return true;
        },
        .exit_alt_screen => |opts| {
            vt.switchScreenMode(false, false, opts.restore_cursor);
            return true;
        },
        else => {},
    }
    if (reportAction(event)) |report_action| {
        try report_apply.apply(vt, report_action);
        return true;
    }
    if (kittyAction(event)) |kitty_action| {
        return try kitty_apply.apply(vt, kitty_action);
    }
    if (modeAction(event)) |mode_action| {
        mode_apply.apply(vt, mode_action);
        return true;
    }
    if (hostAction(event)) |host_action| {
        try host_apply.apply(vt, host_action);
        return true;
    }
    const screen_event = screenAction(event) orelse unreachable;
    vt.screen_state.active().applyScreen(screen_event);
    return true;
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
        .cursor_color => |v| ScreenAction{ .cursor_color = v },
        .cursor_text_color => |v| ScreenAction{ .cursor_text_color = v },
        .auto_wrap => |v| ScreenAction{ .auto_wrap = v },
        .origin_mode => |v| ScreenAction{ .origin_mode = v },
        .insert_mode => |v| ScreenAction{ .insert_mode = v },
        .sgr => |v| ScreenAction{ .sgr = .{ .params = v.params, .separators = v.separators } },
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

fn reportAction(event: SemanticEvent) ?ReportAction {
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

fn modeAction(event: SemanticEvent) ?ModeAction {
    return switch (event) {
        .application_cursor_keys => |v| ModeAction{ .application_cursor_keys = v },
        .application_keypad => |v| ModeAction{ .application_keypad = v },
        .ansi_mode_set => |v| ModeAction{ .ansi_mode_set = v },
        .ansi_mode_reset => |v| ModeAction{ .ansi_mode_reset = v },
        .modify_other_keys_set => |v| ModeAction{ .modify_other_keys_set = v },
        .modify_other_keys_disable => .modify_other_keys_disable,
        .key_format_change => |v| ModeAction{ .key_format_change = v },
        .pointer_mode => |v| ModeAction{ .pointer_mode = v },
        .kitty_clipboard_mode => |v| ModeAction{ .kitty_clipboard_mode = v },
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

fn kittyAction(event: SemanticEvent) ?KittyAction {
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
        else => null,
    };
}

fn hostAction(event: SemanticEvent) ?HostAction {
    return switch (event) {
        .title_set => |v| HostAction{ .title_set = v },
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
        else => null,
    };
}
