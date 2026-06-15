const std = @import("std");
const action_vocabulary = @import("vocabulary.zig");
const input_mouse = @import("input/mouse.zig");

const ModeAction = action_vocabulary.ModeAction;

const saved_dec_mode_limit = 16;
const SavedDecModeCount = u8;
const SavedDecModeSlot = u8;

pub const ModeState = struct {
    keyboard_action_mode: bool = false,
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    send_receive_mode: bool = false,
    newline_mode: bool = false,
    modify_other_keys: i8 = 0,
    key_format: [8]u16 = [_]u16{0} ** 8,
    focus_reporting: bool = false,
    bracketed_paste: bool = false,
    synchronized_output: bool = false,
    kitty_clipboard: bool = false,
    reverse_wraparound_mode: bool = false,
    extended_reverse_wraparound_mode: bool = false,
    mouse_tracking: input_mouse.MouseTrackingMode = .off,
    mouse_protocol: input_mouse.MouseProtocol = .none,
    pointer_mode: u2 = 1,
    saved_dec_modes: [saved_dec_mode_limit]SavedDecMode = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit,
    saved_dec_mode_count: SavedDecModeCount = 0,
};

pub fn apply(vt: anytype, mode_action: ModeAction) void {
    switch (mode_action) {
        .application_cursor_keys => |enabled| vt.modes.application_cursor_keys = enabled,
        .application_keypad => |enabled| vt.modes.application_keypad = enabled,
        .ansi_mode_set => |modes| setAnsiModes(vt, modes.params[0..modes.param_count], true),
        .ansi_mode_reset => |modes| setAnsiModes(vt, modes.params[0..modes.param_count], false),
        .modify_other_keys_set => |value| vt.modes.modify_other_keys = value,
        .modify_other_keys_disable => vt.modes.modify_other_keys = -1,
        .key_format_change => |change| {
            if (change.resource) |resource| {
                if (isKeyFormatResource(resource)) vt.modes.key_format[resource] = change.value orelse 0;
            } else {
                vt.modes.key_format = [_]u16{0} ** 8;
            }
        },
        .pointer_mode => |value| vt.modes.pointer_mode = value,
        .kitty_clipboard_mode => |enabled| vt.modes.kitty_clipboard = enabled,
        .reverse_wraparound_mode => |enabled| vt.modes.reverse_wraparound_mode = enabled,
        .extended_reverse_wraparound_mode => |enabled| vt.modes.extended_reverse_wraparound_mode = enabled,
        .focus_reporting => |enabled| vt.modes.focus_reporting = enabled,
        .bracketed_paste => |enabled| vt.modes.bracketed_paste = enabled,
        .synchronized_output => |enabled| vt.modes.synchronized_output = enabled,
        .mouse_tracking_off => vt.modes.mouse_tracking = .off,
        .mouse_tracking_x10 => vt.modes.mouse_tracking = .x10,
        .mouse_tracking_normal => vt.modes.mouse_tracking = .normal,
        .mouse_tracking_button_event => vt.modes.mouse_tracking = .button_event,
        .mouse_tracking_any_event => vt.modes.mouse_tracking = .any_event,
        .mouse_protocol_utf8 => |enabled| vt.modes.mouse_protocol = if (enabled) .utf8 else .none,
        .mouse_protocol_sgr => |enabled| vt.modes.mouse_protocol = if (enabled) .sgr else .none,
        .mouse_protocol_urxvt => |enabled| vt.modes.mouse_protocol = if (enabled) .urxvt else .none,
        .dec_mode_save => |modes| saveDecModes(vt, modes.params[0..modes.param_count]),
        .dec_mode_restore => |modes| restoreDecModes(vt, modes.params[0..modes.param_count]),
    }
}

pub const SavedDecMode = struct {
    mode: u16,
    state: u8,
};

pub const DecView = struct {
    application_cursor_keys: bool,
    application_keypad: bool,
    auto_wrap: bool,
    left_right_margin_mode: bool,
    cursor_visible: bool,
    alt_active: bool,
    mouse_tracking: input_mouse.MouseTrackingMode,
    mouse_protocol: input_mouse.MouseProtocol,
    focus_reporting: bool,
    bracketed_paste: bool,
    synchronized_output: bool,
    kitty_clipboard: bool,
};

pub const AnsiView = struct {
    keyboard_action_mode: bool,
    insert_mode: bool,
    send_receive_mode: bool,
    newline_mode: bool,
};

pub fn decModeState(vt: anytype, mode: u16) u8 {
    const active_state = vt.screen_state.activeConst();
    return decModeStateForView(.{
        .application_cursor_keys = vt.modes.application_cursor_keys,
        .application_keypad = vt.modes.application_keypad,
        .auto_wrap = active_state.auto_wrap,
        .left_right_margin_mode = active_state.left_right_margin_mode,
        .cursor_visible = active_state.cursor.visible,
        .alt_active = vt.screen_state.alt_active,
        .mouse_tracking = vt.modes.mouse_tracking,
        .mouse_protocol = vt.modes.mouse_protocol,
        .focus_reporting = vt.modes.focus_reporting,
        .bracketed_paste = vt.modes.bracketed_paste,
        .synchronized_output = vt.modes.synchronized_output,
        .kitty_clipboard = vt.modes.kitty_clipboard,
    }, mode);
}

pub fn ansiModeState(vt: anytype, mode: u16) u8 {
    const active_state = vt.screen_state.activeConst();
    return ansiModeStateForView(.{
        .keyboard_action_mode = vt.modes.keyboard_action_mode,
        .insert_mode = active_state.insert_mode,
        .send_receive_mode = vt.modes.send_receive_mode,
        .newline_mode = vt.modes.newline_mode,
    }, mode);
}

pub fn saveDecModes(vt: anytype, modes: []const u16) void {
    for (modes) |mode| {
        if (!canSetDecMode(mode)) continue;
        const slot = savedDecModeSlot(vt.modes.saved_dec_modes[0..], &vt.modes.saved_dec_mode_count, mode);
        vt.modes.saved_dec_modes[savedIndex(slot)] = .{
            .mode = mode,
            .state = decModeState(vt, mode),
        };
    }
}

pub fn restoreDecModes(vt: anytype, modes: []const u16) void {
    for (modes) |mode| {
        const state = savedDecModeState(vt.modes.saved_dec_modes[0..], vt.modes.saved_dec_mode_count, mode) orelse continue;
        switch (state) {
            1 => setDecMode(vt, mode, true),
            2 => setDecMode(vt, mode, false),
            else => {},
        }
    }
}

pub fn setDecMode(vt: anytype, mode: u16, enabled: bool) void {
    const active_state = vt.screen_state.active();
    switch (mode) {
        1 => vt.modes.application_cursor_keys = enabled,
        6 => active_state.apply(.{ .origin_mode = enabled }),
        7 => active_state.apply(.{ .auto_wrap = enabled }),
        69 => active_state.apply(.{ .left_right_margin_mode = enabled }),
        25 => active_state.apply(.{ .cursor_visible = enabled }),
        66 => vt.modes.application_keypad = enabled,
        47 => vt.switchScreenMode(enabled, false, false),
        1047 => vt.switchScreenMode(enabled, true, false),
        1049 => vt.switchScreenMode(enabled, true, true),
        9 => vt.modes.mouse_tracking = if (enabled) .x10 else .off,
        1000 => vt.modes.mouse_tracking = if (enabled) .normal else .off,
        1002 => vt.modes.mouse_tracking = if (enabled) .button_event else .off,
        1003 => vt.modes.mouse_tracking = if (enabled) .any_event else .off,
        1004 => vt.modes.focus_reporting = enabled,
        1005 => vt.modes.mouse_protocol = if (enabled) .utf8 else .none,
        1006 => vt.modes.mouse_protocol = if (enabled) .sgr else .none,
        1015 => vt.modes.mouse_protocol = if (enabled) .urxvt else .none,
        2004 => vt.modes.bracketed_paste = enabled,
        2026 => vt.modes.synchronized_output = enabled,
        5522 => vt.modes.kitty_clipboard = enabled,
        else => {},
    }
}

pub fn setAnsiModes(vt: anytype, modes: []const u16, enabled: bool) void {
    const active_state = vt.screen_state.active();
    for (modes) |mode| switch (mode) {
        2 => vt.modes.keyboard_action_mode = enabled,
        4 => active_state.apply(.{ .insert_mode = enabled }),
        12 => vt.modes.send_receive_mode = enabled,
        20 => vt.modes.newline_mode = enabled,
        else => {},
    };
}

pub fn decModeStateForView(view: DecView, mode: u16) u8 {
    return switch (mode) {
        1 => boolToDecModeState(view.application_cursor_keys),
        7 => boolToDecModeState(view.auto_wrap),
        69 => boolToDecModeState(view.left_right_margin_mode),
        66 => boolToDecModeState(view.application_keypad),
        25 => boolToDecModeState(view.cursor_visible),
        47, 1047, 1049 => boolToDecModeState(view.alt_active),
        9 => if (view.mouse_tracking == .x10) 1 else 2,
        1000 => if (view.mouse_tracking == .normal) 1 else 2,
        1002 => if (view.mouse_tracking == .button_event) 1 else 2,
        1003 => if (view.mouse_tracking == .any_event) 1 else 2,
        1004 => boolToDecModeState(view.focus_reporting),
        1005 => boolToDecModeState(view.mouse_protocol == .utf8),
        1006 => boolToDecModeState(view.mouse_protocol == .sgr),
        1015 => boolToDecModeState(view.mouse_protocol == .urxvt),
        2004 => boolToDecModeState(view.bracketed_paste),
        2026 => boolToDecModeState(view.synchronized_output),
        5522 => boolToDecModeState(view.kitty_clipboard),
        else => 0,
    };
}

pub fn ansiModeStateForView(view: AnsiView, mode: u16) u8 {
    return switch (mode) {
        2 => boolToDecModeState(view.keyboard_action_mode),
        4 => boolToDecModeState(view.insert_mode),
        12 => boolToDecModeState(view.send_receive_mode),
        20 => boolToDecModeState(view.newline_mode),
        else => 0,
    };
}

pub fn boolToDecModeState(enabled: bool) u8 {
    return if (enabled) 1 else 2;
}

pub fn savedDecModeSlot(saved_modes: []SavedDecMode, saved_count: *SavedDecModeCount, mode: u16) SavedDecModeSlot {
    const cap = savedDecModeCap(saved_modes);
    var slot: SavedDecModeSlot = 0;
    while (slot < saved_count.*) : (slot += 1) {
        if (saved_modes[savedIndex(slot)].mode == mode) return slot;
    }
    if (saved_count.* < cap) {
        const new_slot = saved_count.*;
        saved_count.* += 1;
        return new_slot;
    }
    return cap - 1;
}

pub fn savedDecModeState(saved_modes: []const SavedDecMode, saved_count: SavedDecModeCount, mode: u16) ?u8 {
    var slot: SavedDecModeSlot = 0;
    while (slot < saved_count) : (slot += 1) {
        const idx = savedIndex(slot);
        if (saved_modes[idx].mode == mode) return saved_modes[idx].state;
    }
    return null;
}

pub fn canSetDecMode(mode: u16) bool {
    return switch (mode) {
        1, 6, 7, 9, 25, 47, 66, 69, 1047, 1049, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 2004, 2026, 5522 => true,
        else => false,
    };
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

fn savedIndex(slot: SavedDecModeSlot) usize {
    return @intCast(slot);
}

fn savedDecModeCap(saved_modes: []const SavedDecMode) SavedDecModeCount {
    std.debug.assert(saved_modes.len <= std.math.maxInt(SavedDecModeCount));
    return @intCast(saved_modes.len);
}

test "saved dec mode slot reuses existing entry" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    saved[0] = .{ .mode = 7, .state = 1 };
    var count: SavedDecModeCount = 1;
    try std.testing.expectEqual(@as(SavedDecModeSlot, 0), savedDecModeSlot(saved[0..], &count, 7));
    try std.testing.expectEqual(@as(SavedDecModeCount, 1), count);
}

test "saved dec mode slot appends and saturates" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    var count: SavedDecModeCount = 0;
    try std.testing.expectEqual(@as(SavedDecModeSlot, 0), savedDecModeSlot(saved[0..], &count, 7));
    try std.testing.expectEqual(@as(SavedDecModeCount, 1), count);
    count = saved_dec_mode_limit;
    try std.testing.expectEqual(@as(SavedDecModeSlot, saved_dec_mode_limit - 1), savedDecModeSlot(saved[0..], &count, 2004));
}

test "saved dec mode state scans only saved entries" {
    var saved = [_]SavedDecMode{.{ .mode = 0, .state = 0 }} ** saved_dec_mode_limit;
    saved[0] = .{ .mode = 7, .state = 1 };
    saved[1] = .{ .mode = 1004, .state = 2 };
    saved[2] = .{ .mode = 2004, .state = 1 };
    try std.testing.expectEqual(@as(?u8, 2), savedDecModeState(saved[0..], 2, 1004));
    try std.testing.expectEqual(@as(?u8, null), savedDecModeState(saved[0..], 2, 2004));
}
