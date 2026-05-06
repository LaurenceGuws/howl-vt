//! Responsibility: map parsed records into semantic grid operations.
//! Ownership: interpret translation layer.
//! Reason: separate escape parsing from grid behavior intent.

const std = @import("std");
const bridge_mod = @import("bridge.zig");

/// Bridge event alias for semantic mapping.
const Event = bridge_mod.Event;

/// Screen-directed semantic event union.
pub const SemanticEvent = union(enum) {
    pub const CursorShape = enum {
        block,
        underline,
        bar,
    };

    pub const CursorStyle = struct {
        shape: CursorShape,
        blink: bool,
    };

    pub const ModeParams = struct {
        params: [16]u16,
        param_count: u8,
    };

    pub const RectArea = struct {
        top: u16,
        left: u16,
        bottom: ?u16,
        right: ?u16,
    };

    pub const AttrParams = struct {
        params: [16]u16,
        param_count: u8,
    };

    pub const RectCopy = struct {
        area: RectArea,
        source_page: u16,
        dest_top: u16,
        dest_left: u16,
        dest_page: u16,
    };

    pub const OptionalRectArea = struct {
        top: ?u16,
        left: ?u16,
        bottom: ?u16,
        right: ?u16,
    };

    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_next_line: u16,
    cursor_prev_line: u16,
    cursor_horizontal_absolute: u16,
    cursor_vertical_absolute: u16,
    cursor_position: struct { row: u16, col: u16 },
    write_text: []const u8,
    write_codepoint: u21,
    repeat_preceding: u16,
    line_feed,
    next_line,
    reverse_index,
    carriage_return,
    backspace,
    horizontal_tab,
    horizontal_tab_forward: u16,
    horizontal_tab_back: u16,
    horizontal_tab_set,
    tab_clear_current,
    tab_clear_all,
    cursor_visible: bool,
    cursor_style: CursorStyle,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    application_cursor_keys: bool,
    application_keypad: bool,
    ansi_mode_set: ModeParams,
    ansi_mode_reset: ModeParams,
    ansi_mode_query: u16,
    modify_other_keys_set: i8,
    modify_other_keys_query,
    modify_other_keys_disable,
    focus_reporting: bool,
    bracketed_paste: bool,
    mouse_tracking_off,
    mouse_tracking_x10,
    mouse_tracking_normal,
    mouse_tracking_button_event,
    mouse_tracking_any_event,
    mouse_protocol_utf8: bool,
    mouse_protocol_sgr: bool,
    mouse_protocol_urxvt: bool,
    kitty_keyboard_set: struct { flags: u32, mode: u8 },
    kitty_keyboard_query,
    kitty_keyboard_push: u32,
    kitty_keyboard_pop: u16,
    kitty_shell_mark: KittyShellMark,
    kitty_notification: KittyNotificationCommand,
    kitty_pointer_shape: KittyPointerShapeCommand,
    kitty_color_stack: KittyColorStackCommand,
    terminal_color_control: TerminalColorControlCommand,
    hyperlink_set: []const u8,
    hyperlink_clear,
    clipboard_set: []const u8,
    dec_mode_query: u16,
    dec_mode_save: ModeParams,
    dec_mode_restore: ModeParams,
    device_status_report,
    cursor_position_report,
    dec_cursor_position_report,
    primary_device_attributes,
    secondary_device_attributes,
    tertiary_device_attributes,
    xtchecksum: u16,
    rect_checksum_request: struct { request_id: u16, page: u16, area: RectArea },
    presentation_state_report: u16,
    displayed_extent_report,
    terminal_parameters_report: u16,
    xtreportcolors,
    locator_reporting: struct { mode: u16, unit: u16 },
    locator_filter: OptionalRectArea,
    locator_events: ModeParams,
    locator_request: u16,
    sgr: struct {
        params: [16]i32,
        separators: [16]u8,
        param_count: u8,
    },
    kitty_graphics: KittyGraphicsCommand,
    enter_alt_screen: struct { clear: bool, save_cursor: bool },
    exit_alt_screen: struct { restore_cursor: bool },
    save_cursor,
    restore_cursor,
    insert_lines: u16,
    delete_lines: u16,
    insert_chars: u16,
    delete_chars: u16,
    scroll_up_lines: u16,
    scroll_down_lines: u16,
    set_scroll_region: struct {
        top: u16,
        bottom: ?u16,
    },
    reset_screen,
    erase_display: u2,
    erase_line: u2,
    selective_erase_display: u2,
    selective_erase_line: u2,
    erase_chars: u16,
    character_protection: bool,
    rect_erase: RectArea,
    rect_selective_erase: RectArea,
    rect_fill: struct { area: RectArea, ch: u21 },
    rect_copy: RectCopy,
    rect_attrs_change: struct { area: RectArea, attrs: AttrParams, reverse: bool },
    insert_columns: u16,
    delete_columns: u16,
    attr_change_extent_rect: bool,
    left_right_margin_mode: bool,
    set_left_right_margins: struct { left: u16, right: ?u16 },
};

/// Map bridge event to semantic event when supported.
pub fn process(event: Event) ?SemanticEvent {
    switch (event) {
        .style_change => |sc| return processCsi(sc.final, sc.params, sc.separators, sc.param_count, sc.leader, sc.private, sc.intermediates, sc.intermediates_len),
        .text => |s| return SemanticEvent{ .write_text = s },
        .codepoint => |cp| return SemanticEvent{ .write_codepoint = cp },
        .control => |c| return processControl(c),
        .osc => |osc| return processOsc(osc.kind, osc.command, osc.payload),
        .esc_final => |final| return processEscFinal(final),
        .apc => |apc| return processApc(apc),
        .dcs, .invalid_sequence => return null,
    }
}

pub const KittyGraphicsCommand = struct {
    action: u8,
    image_id: u32,
    image_number: u32,
    placement_id: u32,
    format: u16,
    width: u32,
    height: u32,
    columns: u32,
    rows: u32,
    x: u32,
    y: u32,
    z: i32,
    medium: u8,
    more_chunks: bool,
    quiet: bool,
    delete_target: u8,
    payload: []const u8,
};

pub const KittyShellMark = struct {
    kind: u8,
    status: ?i32,
    metadata: []const u8,
};

pub const KittyNotificationCommand = struct {
    metadata: []const u8,
    payload: []const u8,
};

pub const KittyPointerShapeCommand = struct {
    action: u8,
    names: []const u8,
};

pub const KittyColorStackCommand = enum {
    push,
    pop,
};

pub const TerminalColorControlCommand = struct {
    command: u16,
    payload: []const u8,
};

fn processApc(data: []const u8) ?SemanticEvent {
    return parseKittyGraphics(data) orelse null;
}

fn parseKittyGraphics(data: []const u8) ?SemanticEvent {
    if (data.len == 0 or data[0] != 'G') return null;
    const body = data[1..];
    const separator = std.mem.indexOfScalar(u8, body, ';') orelse body.len;
    const control = body[0..separator];
    const payload = if (separator < body.len) body[separator + 1 ..] else "";
    var cmd = KittyGraphicsCommand{
        .action = 't',
        .image_id = 0,
        .image_number = 0,
        .placement_id = 0,
        .format = 32,
        .width = 0,
        .height = 0,
        .columns = 0,
        .rows = 0,
        .x = 0,
        .y = 0,
        .z = 0,
        .medium = 'd',
        .more_chunks = false,
        .quiet = false,
        .delete_target = 0,
        .payload = payload,
    };

    var fields = std.mem.splitScalar(u8, control, ',');
    while (fields.next()) |field| {
        if (field.len < 3 or field[1] != '=') continue;
        const key = field[0];
        const value = field[2..];
        switch (key) {
            'a' => {
                if (value.len > 0) cmd.action = value[0];
            },
            'i' => cmd.image_id = parseU32(value),
            'I' => cmd.image_number = parseU32(value),
            'p' => cmd.placement_id = parseU32(value),
            'f' => cmd.format = parseU16(value),
            's' => cmd.width = parseU32(value),
            'v' => cmd.height = parseU32(value),
            'c' => cmd.columns = parseU32(value),
            'r' => cmd.rows = parseU32(value),
            'x' => cmd.x = parseU32(value),
            'y' => cmd.y = parseU32(value),
            'z' => cmd.z = parseI32(value),
            't' => {
                if (value.len > 0) cmd.medium = value[0];
            },
            'm' => cmd.more_chunks = parseU32(value) != 0,
            'q' => cmd.quiet = parseU32(value) != 0,
            'd' => {
                if (value.len > 0) cmd.delete_target = value[0];
            },
            else => {},
        }
    }
    return SemanticEvent{ .kitty_graphics = cmd };
}

fn parseU32(value: []const u8) u32 {
    return std.fmt.parseUnsigned(u32, value, 10) catch 0;
}

fn parseU16(value: []const u8) u16 {
    return std.fmt.parseUnsigned(u16, value, 10) catch 0;
}

fn parseI32(value: []const u8) i32 {
    return std.fmt.parseInt(i32, value, 10) catch 0;
}

fn processEscFinal(final: u8) ?SemanticEvent {
    return switch (final) {
        'D' => SemanticEvent.line_feed,
        'E' => SemanticEvent.next_line,
        'M' => SemanticEvent.reverse_index,
        'Z' => SemanticEvent.primary_device_attributes,
        'H' => SemanticEvent.horizontal_tab_set,
        'c' => SemanticEvent.reset_screen,
        '7' => SemanticEvent.save_cursor,
        '8' => SemanticEvent.restore_cursor,
        '=' => SemanticEvent{ .application_keypad = true },
        '>' => SemanticEvent{ .application_keypad = false },
        else => null,
    };
}

fn processOsc(kind: bridge_mod.OscKind, command: ?u16, payload: []const u8) ?SemanticEvent {
    if (command) |cmd| switch (cmd) {
        22 => return parseKittyPointerShape(payload),
        4, 10, 11, 12, 21, 104, 110, 111, 112 => return SemanticEvent{ .terminal_color_control = .{ .command = cmd, .payload = payload } },
        99 => return parseKittyNotification(payload),
        133 => return parseKittyShellMark(payload),
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

fn parseKittyShellMark(payload: []const u8) ?SemanticEvent {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    const kind = payload[0];
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D' and metadata.len > 0) std.fmt.parseInt(i32, metadata, 10) catch null else null;
    return SemanticEvent{ .kitty_shell_mark = .{ .kind = kind, .status = status, .metadata = metadata } };
}

fn parseKittyNotification(payload: []const u8) ?SemanticEvent {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    return SemanticEvent{ .kitty_notification = .{
        .metadata = payload[0..separator],
        .payload = payload[separator + 1 ..],
    } };
}

fn parseKittyPointerShape(payload: []const u8) ?SemanticEvent {
    if (payload.len == 0) return SemanticEvent{ .kitty_pointer_shape = .{ .action = '=', .names = "" } };
    const action = switch (payload[0]) {
        '=', '>', '<', '?' => payload[0],
        else => '=',
    };
    const names = if (action == '=') blk: {
        if (payload[0] == '=') break :blk payload[1..];
        break :blk payload;
    } else payload[1..];
    return SemanticEvent{ .kitty_pointer_shape = .{ .action = action, .names = names } };
}

fn processCsi(final: u8, params: [16]i32, separators: [16]u8, count: u8, leader: u8, private: bool, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (private) {
        if (leader == '?' and final == 'u') return SemanticEvent.kitty_keyboard_query;
        if (leader == '?' and final == 'J') return SemanticEvent{ .selective_erase_display = eraseMode(params[0]) };
        if (leader == '?' and final == 'K') return SemanticEvent{ .selective_erase_line = eraseMode(params[0]) };
        if (leader == '?' and count >= 1) {
            if (final == 'm' and paramOrDefault0(params[0]) == 4) return SemanticEvent.modify_other_keys_query;
            if (final == 'p' and intermediatesLenHas(intermediates, intermediates_len, '$')) {
                return SemanticEvent{ .dec_mode_query = paramOrDefault0(params[0]) };
            }
            if (final == 's' and intermediates_len == 0) return SemanticEvent{ .dec_mode_save = collectParams(params, count) };
            if (final == 'r' and intermediates_len == 0) return SemanticEvent{ .dec_mode_restore = collectParams(params, count) };
            if (final == 'n' and paramOrDefault0(params[0]) == 6) return SemanticEvent.dec_cursor_position_report;
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
    if (leader == '>') {
        return switch (final) {
            'c' => SemanticEvent.secondary_device_attributes,
            'm' => if (paramOrDefault0(params[0]) == 4) SemanticEvent{ .modify_other_keys_set = @intCast(@max(if (count >= 2) params[1] else 0, 0)) } else null,
            'n' => if (paramOrDefault0(params[0]) == 4) SemanticEvent.modify_other_keys_disable else null,
            'u' => SemanticEvent{ .kitty_keyboard_push = @intCast(@max(params[0], 0)) },
            else => null,
        };
    }
    if (leader == '=') {
        if (final == 'c') return SemanticEvent.tertiary_device_attributes;
        if (final == 'u') return SemanticEvent{ .kitty_keyboard_set = .{ .flags = @intCast(@max(params[0], 0)), .mode = @intCast(@max(if (count >= 2) params[1] else 1, 1)) } };
        return null;
    }
    if (leader == '<') {
        if (final == 'u') return SemanticEvent{ .kitty_keyboard_pop = paramOrDefault1(params[0]) };
        return null;
    }
    if (leader != 0) return null;
    if (intermediates_len == 2 and intermediates[0] == '\'' and intermediates[1] == '*') {
        if (final == '{') return SemanticEvent{ .locator_events = collectParams(params, count) };
        return null;
    }
    if (intermediates_len == 1) {
        switch (intermediates[0]) {
            '"' => {
                if (final == 'q') return switch (paramOrDefault0(params[0])) {
                    0, 2 => SemanticEvent{ .character_protection = false },
                    1 => SemanticEvent{ .character_protection = true },
                    else => null,
                };
                if (final == 'v') return SemanticEvent.displayed_extent_report;
                return switch (paramOrDefault0(params[0])) {
                    else => null,
                };
            },
            '$' => return switch (final) {
                'p' => SemanticEvent{ .ansi_mode_query = paramOrDefault0(params[0]) },
                'r' => SemanticEvent{ .rect_attrs_change = .{
                    .area = rectArea(params, count, 0),
                    .attrs = attrParams(params, count, 4),
                    .reverse = false,
                } },
                't' => SemanticEvent{ .rect_attrs_change = .{
                    .area = rectArea(params, count, 0),
                    .attrs = attrParams(params, count, 4),
                    .reverse = true,
                } },
                'v' => SemanticEvent{ .rect_copy = .{
                    .area = rectArea(params, count, 0),
                    .source_page = if (count >= 5) paramOrDefault1(params[4]) else 1,
                    .dest_top = if (count >= 6) paramOrDefault1(params[5]) - 1 else 0,
                    .dest_left = if (count >= 7) paramOrDefault1(params[6]) - 1 else 0,
                    .dest_page = if (count >= 8) paramOrDefault1(params[7]) else 1,
                } },
                'x' => blk: {
                    const ch = paramOrDefault0(params[0]);
                    if (!isValidRectFillChar(ch)) break :blk null;
                    break :blk SemanticEvent{ .rect_fill = .{ .area = rectArea(params, count, 1), .ch = ch } };
                },
                'z' => SemanticEvent{ .rect_erase = rectArea(params, count, 0) },
                '{' => SemanticEvent{ .rect_selective_erase = rectArea(params, count, 0) },
                'w' => SemanticEvent{ .presentation_state_report = paramOrDefault0(params[0]) },
                else => null,
            },
            '*' => {
                if (final == 'x') return switch (paramOrDefault0(params[0])) {
                    0, 1 => SemanticEvent{ .attr_change_extent_rect = false },
                    2 => SemanticEvent{ .attr_change_extent_rect = true },
                    else => null,
                };
                if (final == 'y') return SemanticEvent{ .rect_checksum_request = .{
                    .request_id = paramOrDefault0(params[0]),
                    .page = if (count >= 2) paramOrDefault1(params[1]) else 1,
                    .area = rectArea(params, count, 2),
                } };
                return null;
            },
            '#' => return switch (final) {
                'y' => SemanticEvent{ .xtchecksum = paramOrDefault0(params[0]) },
                'R' => SemanticEvent.xtreportcolors,
                else => null,
            },
            '\'' => return switch (final) {
                'w' => SemanticEvent{ .locator_filter = optionalRectArea(params, count) },
                '}' => SemanticEvent{ .insert_columns = paramOrDefault1(params[0]) },
                'z' => SemanticEvent{ .locator_reporting = .{ .mode = paramOrDefault0(params[0]), .unit = paramOrDefault0(if (count >= 2) params[1] else 0) } },
                '|' => SemanticEvent{ .locator_request = paramOrDefault0(params[0]) },
                '~' => SemanticEvent{ .delete_columns = paramOrDefault1(params[0]) },
                else => null,
            },
            else => {},
        }
    }
    if (final == 'q' and intermediates_len == 1 and intermediates[0] == ' ') {
        return SemanticEvent{ .cursor_style = cursorStyle(paramOrDefault0(params[0])) };
    }
    switch (final) {
        '@' => return SemanticEvent{ .insert_chars = paramOrDefault1(params[0]) },
        'A' => return SemanticEvent{ .cursor_up = paramOrDefault1(params[0]) },
        'B', 'e' => return SemanticEvent{ .cursor_down = paramOrDefault1(params[0]) },
        'C', 'a' => return SemanticEvent{ .cursor_forward = paramOrDefault1(params[0]) },
        'b' => return SemanticEvent{ .repeat_preceding = paramOrDefault1(params[0]) },
        'D' => return SemanticEvent{ .cursor_back = paramOrDefault1(params[0]) },
        'E' => return SemanticEvent{ .cursor_next_line = paramOrDefault1(params[0]) },
        'F' => return SemanticEvent{ .cursor_prev_line = paramOrDefault1(params[0]) },
        'G', '`' => return SemanticEvent{ .cursor_horizontal_absolute = paramOrDefault1(params[0]) - 1 },
        'd' => return SemanticEvent{ .cursor_vertical_absolute = paramOrDefault1(params[0]) - 1 },
        'I' => return SemanticEvent{ .horizontal_tab_forward = paramOrDefault1(params[0]) },
        'g' => switch (paramOrDefault0(params[0])) {
            0 => return SemanticEvent.tab_clear_current,
            3 => return SemanticEvent.tab_clear_all,
            else => return null,
        },
        'Z' => return SemanticEvent{ .horizontal_tab_back = paramOrDefault1(params[0]) },
        'L' => return SemanticEvent{ .insert_lines = paramOrDefault1(params[0]) },
        'M' => return SemanticEvent{ .delete_lines = paramOrDefault1(params[0]) },
        'P' => return SemanticEvent{ .delete_chars = paramOrDefault1(params[0]) },
        'S' => return SemanticEvent{ .scroll_up_lines = paramOrDefault1(params[0]) },
        'T' => return SemanticEvent{ .scroll_down_lines = paramOrDefault1(params[0]) },
        'h' => return SemanticEvent{ .ansi_mode_set = collectParams(params, count) },
        'l' => return SemanticEvent{ .ansi_mode_reset = collectParams(params, count) },
        'm' => return SemanticEvent{ .sgr = .{ .params = params, .separators = separators, .param_count = count } },
        's' => if (count == 0) return SemanticEvent.save_cursor else return SemanticEvent{ .set_left_right_margins = .{
            .left = paramOrDefault1(params[0]) - 1,
            .right = if (count >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        } },
        'u' => return SemanticEvent.restore_cursor,
        'H', 'f' => {
            const row = paramOrDefault1(params[0]);
            const col = paramOrDefault1(if (count >= 1) params[1] else 0);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'r' => return SemanticEvent{ .set_scroll_region = .{
            .top = paramOrDefault1(params[0]) - 1,
            .bottom = if (count >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        } },
        'J' => return SemanticEvent{ .erase_display = eraseMode(params[0]) },
        'K' => return SemanticEvent{ .erase_line = eraseMode(params[0]) },
        'X' => return SemanticEvent{ .erase_chars = paramOrDefault1(params[0]) },
        'x' => return SemanticEvent{ .terminal_parameters_report = paramOrDefault0(params[0]) },
        'n' => switch (paramOrDefault0(params[0])) {
            5 => return SemanticEvent.device_status_report,
            6 => return SemanticEvent.cursor_position_report,
            else => return null,
        },
        'c' => return SemanticEvent.primary_device_attributes,
        'p' => {
            if (count == 0 and intermediates_len == 1 and intermediates[0] == '!') {
                return SemanticEvent.reset_screen;
            }
            return null;
        },
        else => return null,
    }
}

fn optionalRectArea(params: [16]i32, count: u8) SemanticEvent.OptionalRectArea {
    return .{
        .top = if (count >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (count >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (count >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (count >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

fn rectArea(params: [16]i32, count: u8, start_idx: usize) SemanticEvent.RectArea {
    return .{
        .top = if (count > start_idx) paramOrDefault1(params[start_idx]) - 1 else 0,
        .left = if (count > start_idx + 1) paramOrDefault1(params[start_idx + 1]) - 1 else 0,
        .bottom = if (count > start_idx + 2) paramOrDefault1(params[start_idx + 2]) - 1 else null,
        .right = if (count > start_idx + 3) paramOrDefault1(params[start_idx + 3]) - 1 else null,
    };
}

fn attrParams(params: [16]i32, count: u8, start_idx: usize) SemanticEvent.AttrParams {
    var out = [_]u16{0} ** 16;
    var idx: usize = start_idx;
    var dst: usize = 0;
    while (idx < count and dst < out.len) : ({
        idx += 1;
        dst += 1;
    }) {
        out[dst] = paramOrDefault0(params[idx]);
    }
    return .{ .params = out, .param_count = @intCast(dst) };
}

fn isValidRectFillChar(ch: u16) bool {
    return (ch >= 32 and ch <= 126) or (ch >= 160 and ch <= 255);
}

fn processControl(c: u8) ?SemanticEvent {
    return switch (c) {
        0x0A, 0x0B, 0x0C => SemanticEvent.line_feed,
        0x0D => SemanticEvent.carriage_return,
        0x08 => SemanticEvent.backspace,
        0x09 => SemanticEvent.horizontal_tab,
        else => null,
    };
}

fn eraseMode(v: i32) u2 {
    return switch (v) {
        1 => 1,
        2 => 2,
        3 => 3,
        else => 0,
    };
}

fn cursorStyle(param: u16) SemanticEvent.CursorStyle {
    return switch (param) {
        2 => .{ .shape = .block, .blink = false },
        3 => .{ .shape = .underline, .blink = true },
        4 => .{ .shape = .underline, .blink = false },
        5 => .{ .shape = .bar, .blink = true },
        6 => .{ .shape = .bar, .blink = false },
        else => .{ .shape = .block, .blink = true },
    };
}

fn collectParams(params: [16]i32, count: u8) SemanticEvent.ModeParams {
    var out = [_]u16{0} ** 16;
    const n = @min(count, out.len);
    var idx: usize = 0;
    while (idx < n) : (idx += 1) out[idx] = paramOrDefault0(params[idx]);
    return .{ .params = out, .param_count = @intCast(n) };
}

fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn paramOrDefault0(v: i32) u16 {
    if (v <= 0) return 0;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

fn intermediatesLenHas(intermediates: [4]u8, len: u8, needle: u8) bool {
    var idx: usize = 0;
    while (idx < len) : (idx += 1) {
        if (intermediates[idx] == needle) return true;
    }
    return false;
}
