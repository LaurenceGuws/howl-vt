//! Responsibility: own terminal mode query and save/restore bookkeeping helpers.
//! Ownership: terminal mode protocol domain owner.
//! Reason: keep DEC/ANSI mode bookkeeping out of the vt-core facade.

const input_mod = @import("input.zig");

const Input = input_mod.Input;

pub const TerminalMode = struct {
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
    };

    pub const AnsiView = struct {
        keyboard_action_mode: bool,
        insert_mode: bool,
        send_receive_mode: bool,
        newline_mode: bool,
    };

    pub fn decModeState(view: DecView, mode: u16) u8 {
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
            else => 0,
        };
    }

    pub fn ansiModeState(view: AnsiView, mode: u16) u8 {
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
};
