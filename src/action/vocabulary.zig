const parser_mod = @import("../parser/main.zig");

const csi_max_params = parser_mod.max_params;
pub const CsiSeparatorList = parser_mod.CsiSeparatorList;

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

pub const KeyFormatChange = struct {
    resource: ?u8,
    value: ?u16,
};

pub const KittyMultipleCursorCommand = enum {
    support_query,
    clear_all,
    cursor_query,
    color_query,
};

pub const DcsPayloadKind = enum {
    xtsettcap,
    decrsps,
    decudk,
    decaupss,
};

pub const DcsPayload = struct {
    kind: DcsPayloadKind,
    payload: []const u8,
};

pub const EraseMode = enum(u2) {
    cursor_to_end = 0,
    start_to_cursor = 1,
    all = 2,
    scrollback = 3,
};

pub const LegacyControlKind = enum {
    tek_point_plot,
    tek_graph,
    tek_incremental_plot,
    tek_alpha,
    tek_copy,
    tek_special_point_plot,
    tek_write_thru_short_dashed,
    hp_memory_lock,
};

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
        params: [csi_max_params]u16,
        param_count: u8,
    };

    pub const RectArea = struct {
        top: u16,
        left: u16,
        bottom: ?u16,
        right: ?u16,
    };

    pub const AttrParams = struct {
        params: [csi_max_params]u16,
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
    key_format_change: KeyFormatChange,
    key_format_query: u8,
    pointer_mode: u2,
    kitty_clipboard_mode: bool,
    reverse_wraparound_mode: bool,
    extended_reverse_wraparound_mode: bool,
    focus_reporting: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
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
    kitty_multiple_cursor: KittyMultipleCursorCommand,
    kitty_file_transfer: []const u8,
    kitty_text_size: []const u8,
    title_set: []const u8,
    color_control: TerminalColorControlCommand,
    hyperlink_set: []const u8,
    hyperlink_clear,
    clipboard_set: []const u8,
    dec_mode_query: u16,
    dec_mode_save: ModeParams,
    dec_mode_restore: ModeParams,
    dcs_request_status: []const u8,
    dcs_request_termcap: []const u8,
    dcs_request_resource: []const u8,
    dcs_payload: DcsPayload,
    device_status_report,
    dec_device_status_report: u16,
    cursor_position_report,
    dec_cursor_position_report,
    primary_device_attributes,
    secondary_device_attributes,
    tertiary_device_attributes,
    xtversion,
    xttitlepos,
    xtchecksum: u16,
    rect_checksum_request: struct { request_id: u16, page: u16, area: RectArea },
    selected_graphic_rendition_report: RectArea,
    presentation_state_report: u16,
    displayed_extent_report,
    parameters_report: u16,
    xtreportcolors,
    locator_reporting: struct { mode: u16, unit: u16 },
    locator_filter: OptionalRectArea,
    locator_events: ModeParams,
    locator_request: u16,
    media_copy_request: u16,
    legacy_control: LegacyControlKind,
    sgr: struct {
        params: []const i32,
        separators: CsiSeparatorList,
    },
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
    erase_display: EraseMode,
    erase_line: EraseMode,
    selective_erase_display: EraseMode,
    selective_erase_line: EraseMode,
    erase_chars: u16,
    shift_left_columns: u16,
    shift_right_columns: u16,
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
    reset_default_tab_stops,
};

pub const ScreenAction = union(enum) {
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
    cursor_style: SemanticEvent.CursorStyle,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    save_cursor,
    restore_cursor,
    sgr: struct {
        params: []const i32,
        separators: CsiSeparatorList,
    },
    insert_lines: u16,
    delete_lines: u16,
    insert_chars: u16,
    delete_chars: u16,
    scroll_up_lines: u16,
    scroll_down_lines: u16,
    set_scroll_region: struct { top: u16, bottom: ?u16 },
    reset_screen,
    erase_display: EraseMode,
    erase_line: EraseMode,
    selective_erase_display: EraseMode,
    selective_erase_line: EraseMode,
    erase_chars: u16,
    shift_left_columns: u16,
    shift_right_columns: u16,
    character_protection: bool,
    rect_erase: SemanticEvent.RectArea,
    rect_selective_erase: SemanticEvent.RectArea,
    rect_fill: struct { area: SemanticEvent.RectArea, ch: u21 },
    rect_copy: SemanticEvent.RectCopy,
    rect_attrs_change: struct { area: SemanticEvent.RectArea, attrs: SemanticEvent.AttrParams, reverse: bool },
    insert_columns: u16,
    delete_columns: u16,
    attr_change_extent_rect: bool,
    left_right_margin_mode: bool,
    set_left_right_margins: struct { left: u16, right: ?u16 },
    reset_default_tab_stops,
};

pub const ReportAction = union(enum) {
    ansi_mode_query: u16,
    modify_other_keys_query,
    key_format_query: u8,
    dec_mode_query: u16,
    dcs_request_status: []const u8,
    dcs_request_termcap: []const u8,
    dcs_request_resource: []const u8,
    device_status_report,
    dec_device_status_report: u16,
    cursor_position_report,
    dec_cursor_position_report,
    primary_device_attributes,
    secondary_device_attributes,
    tertiary_device_attributes,
    xtversion,
    xttitlepos,
    xtchecksum: u16,
    rect_checksum_request: struct { request_id: u16, page: u16, area: SemanticEvent.RectArea },
    selected_graphic_rendition_report: SemanticEvent.RectArea,
    presentation_state_report: u16,
    displayed_extent_report,
    parameters_report: u16,
    xtreportcolors,
};

pub const ModeAction = union(enum) {
    enter_alt_screen: struct { clear: bool, save_cursor: bool },
    exit_alt_screen: struct { restore_cursor: bool },
    application_cursor_keys: bool,
    application_keypad: bool,
    ansi_mode_set: SemanticEvent.ModeParams,
    ansi_mode_reset: SemanticEvent.ModeParams,
    modify_other_keys_set: i8,
    modify_other_keys_disable,
    key_format_change: KeyFormatChange,
    pointer_mode: u2,
    kitty_clipboard_mode: bool,
    reverse_wraparound_mode: bool,
    extended_reverse_wraparound_mode: bool,
    focus_reporting: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
    mouse_tracking_off,
    mouse_tracking_x10,
    mouse_tracking_normal,
    mouse_tracking_button_event,
    mouse_tracking_any_event,
    mouse_protocol_utf8: bool,
    mouse_protocol_sgr: bool,
    mouse_protocol_urxvt: bool,
    dec_mode_save: SemanticEvent.ModeParams,
    dec_mode_restore: SemanticEvent.ModeParams,
};

pub const KittyAction = union(enum) {
    kitty_keyboard_set: struct { flags: u32, mode: u8 },
    kitty_keyboard_query,
    kitty_keyboard_push: u32,
    kitty_keyboard_pop: u16,
    kitty_shell_mark: KittyShellMark,
    kitty_notification: KittyNotificationCommand,
    kitty_pointer_shape: KittyPointerShapeCommand,
    kitty_color_stack: KittyColorStackCommand,
    kitty_multiple_cursor: KittyMultipleCursorCommand,
    kitty_file_transfer: []const u8,
    kitty_text_size: []const u8,
};

pub const HostAction = union(enum) {
    title_set: []const u8,
    color_control: TerminalColorControlCommand,
    hyperlink_set: []const u8,
    hyperlink_clear,
    clipboard_set: []const u8,
    locator_reporting: struct { mode: u16, unit: u16 },
    locator_filter: SemanticEvent.OptionalRectArea,
    locator_events: SemanticEvent.ModeParams,
    locator_request: u16,
    media_copy_request: u16,
    dcs_payload: DcsPayload,
    legacy_control: LegacyControlKind,
};
