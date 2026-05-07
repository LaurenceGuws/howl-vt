//! Responsibility: own terminal mode query and save/restore bookkeeping helpers.
//! Ownership: terminal mode protocol domain owner.
//! Reason: keep DEC/ANSI mode bookkeeping out of the vt-core facade.

const input_mod = @import("input.zig");

const Input = input_mod;

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
    mouse_tracking: Input.MouseTrackingMode,
    mouse_protocol: Input.MouseProtocol,
    focus_reporting: bool,
    bracketed_paste: bool,
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
        .cursor_visible = active_state.cursor_visible,
        .alt_active = vt.screen_state.alt_active,
        .mouse_tracking = vt.modes.mouse_tracking,
        .mouse_protocol = vt.modes.mouse_protocol,
        .focus_reporting = vt.modes.focus_reporting,
        .bracketed_paste = vt.modes.bracketed_paste,
        .kitty_clipboard = vt.modes.kitty_clipboard,
    }, mode);
}

pub fn ansiModeState(vt: anytype, mode: u16) u8 {
    const active_state = vt.screen_state.activeConst();
    return ansiModeStateForView(.{
        .keyboard_action_mode = vt.modes.keyboard_action_mode,
        .insert_mode = active_state.insertMode(),
        .send_receive_mode = vt.modes.send_receive_mode,
        .newline_mode = vt.modes.newline_mode,
    }, mode);
}

pub fn saveDecModes(vt: anytype, modes: []const u16) void {
    for (modes) |mode| {
        if (!canSetDecMode(mode)) continue;
        vt.modes.saved_dec_modes[savedDecModeSlot(vt.modes.saved_dec_modes[0..], &vt.modes.saved_dec_mode_count, mode)] = .{
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
        47 => if (enabled) enterAltScreen(vt, false, false) else exitAltScreen(vt, false),
        1047 => if (enabled) enterAltScreen(vt, true, false) else exitAltScreen(vt, false),
        1049 => if (enabled) enterAltScreen(vt, true, true) else exitAltScreen(vt, true),
        9 => vt.modes.mouse_tracking = if (enabled) .x10 else .off,
        1000 => vt.modes.mouse_tracking = if (enabled) .normal else .off,
        1002 => vt.modes.mouse_tracking = if (enabled) .button_event else .off,
        1003 => vt.modes.mouse_tracking = if (enabled) .any_event else .off,
        1004 => vt.modes.focus_reporting = enabled,
        1005 => vt.modes.mouse_protocol = if (enabled) .utf8 else .none,
        1006 => vt.modes.mouse_protocol = if (enabled) .sgr else .none,
        1015 => vt.modes.mouse_protocol = if (enabled) .urxvt else .none,
        2004 => vt.modes.bracketed_paste = enabled,
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

pub fn enterAltScreen(vt: anytype, clear_alt: bool, save_cursor: bool) void {
    vt.screen_state.enterAlt(clear_alt, save_cursor);
    vt.selection.clear();
}

pub fn exitAltScreen(vt: anytype, restore_cursor: bool) void {
    vt.screen_state.exitAlt(restore_cursor);
    vt.selection.clear();
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

pub fn savedDecModeSlot(saved_modes: []SavedDecMode, saved_count: *u8, mode: u16) usize {
    var idx: usize = 0;
    while (idx < saved_count.*) : (idx += 1) {
        if (saved_modes[idx].mode == mode) return idx;
    }
    if (saved_count.* < saved_modes.len) {
        const slot = saved_count.*;
        saved_count.* += 1;
        return slot;
    }
    return saved_modes.len - 1;
}

pub fn savedDecModeState(saved_modes: []const SavedDecMode, saved_count: u8, mode: u16) ?u8 {
    var idx: usize = 0;
    while (idx < saved_count) : (idx += 1) {
        if (saved_modes[idx].mode == mode) return saved_modes[idx].state;
    }
    return null;
}

pub fn canSetDecMode(mode: u16) bool {
    return switch (mode) {
        1, 6, 7, 9, 25, 47, 66, 69, 1047, 1049, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 2004 => true,
        else => false,
    };
}
