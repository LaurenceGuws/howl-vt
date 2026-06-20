const events = @import("semantic_event.zig");
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

const ModeAction = mode_apply.ModeAction;
const KittyAction = kitty_apply.KittyAction;
const HostAction = host_apply.HostAction;

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
    switch (event) {
        .ansi_mode_query => |v| try report_apply.apply(vt, .{ .ansi_mode_query = v }),
        .modify_other_keys_query => try report_apply.apply(vt, .modify_other_keys_query),
        .key_format_query => |v| try report_apply.apply(vt, .{ .key_format_query = v }),
        .dec_mode_query => |v| try report_apply.apply(vt, .{ .dec_mode_query = v }),
        .dcs_request_status => |v| try report_apply.apply(vt, .{ .dcs_request_status = v }),
        .dcs_request_termcap => |v| try report_apply.apply(vt, .{ .dcs_request_termcap = v }),
        .dcs_request_resource => |v| try report_apply.apply(vt, .{ .dcs_request_resource = v }),
        .device_status_report => try report_apply.apply(vt, .device_status_report),
        .dec_device_status_report => |v| try report_apply.apply(vt, .{ .dec_device_status_report = v }),
        .cursor_position_report => try report_apply.apply(vt, .cursor_position_report),
        .dec_cursor_position_report => try report_apply.apply(vt, .dec_cursor_position_report),
        .primary_device_attributes => try report_apply.apply(vt, .primary_device_attributes),
        .secondary_device_attributes => try report_apply.apply(vt, .secondary_device_attributes),
        .tertiary_device_attributes => try report_apply.apply(vt, .tertiary_device_attributes),
        .xtversion => try report_apply.apply(vt, .xtversion),
        .xttitlepos => try report_apply.apply(vt, .xttitlepos),
        .xtchecksum => |v| try report_apply.apply(vt, .{ .xtchecksum = v }),
        .rect_checksum_request => |v| try report_apply.apply(vt, .{ .rect_checksum_request = .{ .request_id = v.request_id, .page = v.page, .area = v.area } }),
        .selected_graphic_rendition_report => |v| try report_apply.apply(vt, .{ .selected_graphic_rendition_report = v }),
        .screen_extent_report => try report_apply.apply(vt, .screen_extent_report),
        .parameters_report => |v| try report_apply.apply(vt, .{ .parameters_report = v }),
        .xtreportcolors => try report_apply.apply(vt, .xtreportcolors),
        else => {},
    }
    switch (event) {
        .ansi_mode_query,
        .modify_other_keys_query,
        .key_format_query,
        .dec_mode_query,
        .dcs_request_status,
        .dcs_request_termcap,
        .dcs_request_resource,
        .device_status_report,
        .dec_device_status_report,
        .cursor_position_report,
        .dec_cursor_position_report,
        .primary_device_attributes,
        .secondary_device_attributes,
        .tertiary_device_attributes,
        .xtversion,
        .xttitlepos,
        .xtchecksum,
        .rect_checksum_request,
        .selected_graphic_rendition_report,
        .screen_extent_report,
        .parameters_report,
        .xtreportcolors,
        => return true,
        else => {},
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
    switch (event) {
        .cursor_up => |v| vt.screen_state.active().applyScreen(.{ .cursor_up = v }),
        .cursor_down => |v| vt.screen_state.active().applyScreen(.{ .cursor_down = v }),
        .cursor_forward => |v| vt.screen_state.active().applyScreen(.{ .cursor_forward = v }),
        .cursor_back => |v| vt.screen_state.active().applyScreen(.{ .cursor_back = v }),
        .cursor_next_line => |v| vt.screen_state.active().applyScreen(.{ .cursor_next_line = v }),
        .cursor_prev_line => |v| vt.screen_state.active().applyScreen(.{ .cursor_prev_line = v }),
        .cursor_horizontal_absolute => |v| vt.screen_state.active().applyScreen(.{ .cursor_horizontal_absolute = v }),
        .cursor_vertical_absolute => |v| vt.screen_state.active().applyScreen(.{ .cursor_vertical_absolute = v }),
        .cursor_position => |v| vt.screen_state.active().applyScreen(.{ .cursor_position = .{ .row = v.row, .col = v.col } }),
        .write_text => |v| vt.screen_state.active().applyScreen(.{ .write_text = v }),
        .write_codepoint => |v| vt.screen_state.active().applyScreen(.{ .write_codepoint = v }),
        .repeat_preceding => |v| vt.screen_state.active().applyScreen(.{ .repeat_preceding = v }),
        .line_feed => vt.screen_state.active().applyScreen(.line_feed),
        .next_line => vt.screen_state.active().applyScreen(.next_line),
        .reverse_index => vt.screen_state.active().applyScreen(.reverse_index),
        .carriage_return => vt.screen_state.active().applyScreen(.carriage_return),
        .backspace => vt.screen_state.active().applyScreen(.backspace),
        .horizontal_tab => vt.screen_state.active().applyScreen(.horizontal_tab),
        .horizontal_tab_forward => |v| vt.screen_state.active().applyScreen(.{ .horizontal_tab_forward = v }),
        .horizontal_tab_back => |v| vt.screen_state.active().applyScreen(.{ .horizontal_tab_back = v }),
        .horizontal_tab_set => vt.screen_state.active().applyScreen(.horizontal_tab_set),
        .tab_clear_current => vt.screen_state.active().applyScreen(.tab_clear_current),
        .tab_clear_all => vt.screen_state.active().applyScreen(.tab_clear_all),
        .cursor_visible => |v| vt.screen_state.active().applyScreen(.{ .cursor_visible = v }),
        .cursor_style => |v| vt.screen_state.active().applyScreen(.{ .cursor_style = v }),
        .cursor_color => |v| vt.screen_state.active().applyScreen(.{ .cursor_color = v }),
        .cursor_text_color => |v| vt.screen_state.active().applyScreen(.{ .cursor_text_color = v }),
        .auto_wrap => |v| vt.screen_state.active().applyScreen(.{ .auto_wrap = v }),
        .origin_mode => |v| vt.screen_state.active().applyScreen(.{ .origin_mode = v }),
        .insert_mode => |v| vt.screen_state.active().applyScreen(.{ .insert_mode = v }),
        .sgr => |v| vt.screen_state.active().applyScreen(.{ .sgr = .{ .params = v.params, .separators = v.separators } }),
        .insert_lines => |v| vt.screen_state.active().applyScreen(.{ .insert_lines = v }),
        .delete_lines => |v| vt.screen_state.active().applyScreen(.{ .delete_lines = v }),
        .insert_chars => |v| vt.screen_state.active().applyScreen(.{ .insert_chars = v }),
        .delete_chars => |v| vt.screen_state.active().applyScreen(.{ .delete_chars = v }),
        .scroll_up_lines => |v| vt.screen_state.active().applyScreen(.{ .scroll_up_lines = v }),
        .scroll_down_lines => |v| vt.screen_state.active().applyScreen(.{ .scroll_down_lines = v }),
        .set_scroll_region => |v| vt.screen_state.active().applyScreen(.{ .set_scroll_region = .{ .top = v.top, .bottom = v.bottom } }),
        .erase_display_below => |protected| vt.screen_state.active().applyScreen(.{ .erase_display_below = protected }),
        .erase_display_above => |protected| vt.screen_state.active().applyScreen(.{ .erase_display_above = protected }),
        .erase_display_complete => |protected| vt.screen_state.active().applyScreen(.{ .erase_display_complete = protected }),
        .erase_display_scrollback => |protected| vt.screen_state.active().applyScreen(.{ .erase_display_scrollback = protected }),
        .erase_display_scroll_complete => |protected| vt.screen_state.active().applyScreen(.{ .erase_display_scroll_complete = protected }),
        .erase_line => |v| vt.screen_state.active().applyScreen(.{ .erase_line = v }),
        .selective_erase_line => |v| vt.screen_state.active().applyScreen(.{ .selective_erase_line = v }),
        .erase_chars => |v| vt.screen_state.active().applyScreen(.{ .erase_chars = v }),
        .shift_left_columns => |v| vt.screen_state.active().applyScreen(.{ .shift_left_columns = v }),
        .shift_right_columns => |v| vt.screen_state.active().applyScreen(.{ .shift_right_columns = v }),
        .character_protection => |v| vt.screen_state.active().applyScreen(.{ .character_protection = v }),
        .rect_erase => |v| vt.screen_state.active().applyScreen(.{ .rect_erase = v }),
        .rect_selective_erase => |v| vt.screen_state.active().applyScreen(.{ .rect_selective_erase = v }),
        .rect_fill => |v| vt.screen_state.active().applyScreen(.{ .rect_fill = .{ .area = v.area, .ch = v.ch } }),
        .rect_copy => |v| vt.screen_state.active().applyScreen(.{ .rect_copy = v }),
        .rect_attrs_change => |v| vt.screen_state.active().applyScreen(.{ .rect_attrs_change = .{ .area = v.area, .attrs = v.attrs, .reverse = v.reverse } }),
        .insert_columns => |v| vt.screen_state.active().applyScreen(.{ .insert_columns = v }),
        .delete_columns => |v| vt.screen_state.active().applyScreen(.{ .delete_columns = v }),
        .attr_change_extent_rect => |v| vt.screen_state.active().applyScreen(.{ .attr_change_extent_rect = v }),
        .left_right_margin_mode => |v| vt.screen_state.active().applyScreen(.{ .left_right_margin_mode = v }),
        .set_left_right_margins => |v| vt.screen_state.active().applyScreen(.{ .set_left_right_margins = .{ .left = v.left, .right = v.right } }),
        .reset_default_tab_stops => vt.screen_state.active().applyScreen(.reset_default_tab_stops),
        else => return true,
    }
    return true;
}

fn modeAction(event: SemanticEvent) ?ModeAction {
    return switch (event) {
        .application_cursor_keys => |v| ModeAction{ .application_cursor_keys = v },
        .application_keypad => |v| ModeAction{ .application_keypad = v },
        .reverse_screen_mode => |v| ModeAction{ .reverse_screen_mode = v },
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
