//! Host input values and encoding.

const std = @import("std");
const keyboard = @import("input/keyboard.zig");
const mouse = @import("input/mouse.zig");
const tokens = @import("input/tokens.zig");

pub const Keyboard = keyboard;
pub const Mouse = mouse;
pub const Tokens = tokens;

pub const Key = keyboard.Key;
pub const Modifier = keyboard.Modifier;

pub const MouseButton = mouse.MouseButton;
pub const MouseEventKind = mouse.MouseEventKind;
pub const MouseEvent = mouse.MouseEvent;
pub const MouseTrackingMode = mouse.MouseTrackingMode;
pub const MouseProtocol = mouse.MouseProtocol;

pub const mouse_button_none: MouseButton = MouseButton.none;
pub const mouse_button_left: MouseButton = MouseButton.left;
pub const mouse_button_middle: MouseButton = MouseButton.middle;
pub const mouse_button_right: MouseButton = MouseButton.right;
pub const mouse_button_wheel_up: MouseButton = MouseButton.wheel_up;
pub const mouse_button_wheel_down: MouseButton = MouseButton.wheel_down;

pub const mouse_press: MouseEventKind = MouseEventKind.press;
pub const mouse_release: MouseEventKind = MouseEventKind.release;
pub const mouse_move: MouseEventKind = MouseEventKind.move;
pub const mouse_wheel: MouseEventKind = MouseEventKind.wheel;

pub const KeyEvent = struct {
    key: Key,
    mods: Modifier = mod_none,
};

pub const FocusEvent = enum {
    in,
    out,
};

pub const Event = union(enum) {
    bytes: []const u8,
    key: KeyEvent,
    mouse: MouseEvent,
    focus: FocusEvent,
    paste: []const u8,
};

pub const Encoded = struct {
    allocator: ?std.mem.Allocator = null,
    bytes: []const u8 = "",

    pub fn deinit(self: *Encoded) void {
        if (self.allocator) |allocator| allocator.free(self.bytes);
        self.* = .{};
    }
};

pub const mod_none: Modifier = keyboard.VTERM_MOD_NONE;
pub const mod_shift: Modifier = keyboard.VTERM_MOD_SHIFT;
pub const mod_alt: Modifier = keyboard.VTERM_MOD_ALT;
pub const mod_ctrl: Modifier = keyboard.VTERM_MOD_CTRL;

pub const key_enter: Key = keyboard.VTERM_KEY_ENTER;
pub const key_tab: Key = keyboard.VTERM_KEY_TAB;
pub const key_backspace: Key = keyboard.VTERM_KEY_BACKSPACE;
pub const key_escape: Key = keyboard.VTERM_KEY_ESCAPE;
pub const key_up: Key = keyboard.VTERM_KEY_UP;
pub const key_down: Key = keyboard.VTERM_KEY_DOWN;
pub const key_left: Key = keyboard.VTERM_KEY_LEFT;
pub const key_right: Key = keyboard.VTERM_KEY_RIGHT;
pub const key_insert: Key = keyboard.VTERM_KEY_INS;
pub const key_delete: Key = keyboard.VTERM_KEY_DEL;
pub const key_home: Key = keyboard.VTERM_KEY_HOME;
pub const key_end: Key = keyboard.VTERM_KEY_END;
pub const key_pageup: Key = keyboard.VTERM_KEY_PAGEUP;
pub const key_pagedown: Key = keyboard.VTERM_KEY_PAGEDOWN;
pub const key_f1: Key = keyboard.VTERM_KEY_F1;
pub const key_f2: Key = keyboard.VTERM_KEY_F2;
pub const key_f3: Key = keyboard.VTERM_KEY_F3;
pub const key_f4: Key = keyboard.VTERM_KEY_F4;
pub const key_f5: Key = keyboard.VTERM_KEY_F5;
pub const key_f6: Key = keyboard.VTERM_KEY_F6;
pub const key_f7: Key = keyboard.VTERM_KEY_F7;
pub const key_f8: Key = keyboard.VTERM_KEY_F8;
pub const key_f9: Key = keyboard.VTERM_KEY_F9;
pub const key_f10: Key = keyboard.VTERM_KEY_F10;
pub const key_f11: Key = keyboard.VTERM_KEY_F11;
pub const key_f12: Key = keyboard.VTERM_KEY_F12;
pub const key_kp_0: Key = keyboard.VTERM_KEY_KP_0;
pub const key_kp_1: Key = keyboard.VTERM_KEY_KP_1;
pub const key_kp_2: Key = keyboard.VTERM_KEY_KP_2;
pub const key_kp_3: Key = keyboard.VTERM_KEY_KP_3;
pub const key_kp_4: Key = keyboard.VTERM_KEY_KP_4;
pub const key_kp_5: Key = keyboard.VTERM_KEY_KP_5;
pub const key_kp_6: Key = keyboard.VTERM_KEY_KP_6;
pub const key_kp_7: Key = keyboard.VTERM_KEY_KP_7;
pub const key_kp_8: Key = keyboard.VTERM_KEY_KP_8;
pub const key_kp_9: Key = keyboard.VTERM_KEY_KP_9;
pub const key_kp_decimal: Key = keyboard.VTERM_KEY_KP_DECIMAL;
pub const key_kp_add: Key = keyboard.VTERM_KEY_KP_ADD;
pub const key_kp_subtract: Key = keyboard.VTERM_KEY_KP_SUBTRACT;
pub const key_kp_multiply: Key = keyboard.VTERM_KEY_KP_MULTIPLY;
pub const key_kp_divide: Key = keyboard.VTERM_KEY_KP_DIVIDE;
pub const key_kp_enter: Key = keyboard.VTERM_KEY_KP_ENTER;
