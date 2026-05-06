//! Responsibility: parse host-facing input tokens into input vocabulary.
//! Ownership: input host-token parsing authority.
//! Reason: keep platform token parsing separate from terminal escape encoding.

const std = @import("std");
const keymap = @import("keymap.zig");

/// Convert a host key token into input key vocabulary.
pub fn parseKeyToken(name: []const u8) ?keymap.Key {
    if (std.mem.eql(u8, name, "KEYCODE_ENTER")) return keymap.VTERM_KEY_ENTER;
    if (std.mem.eql(u8, name, "KEYCODE_TAB")) return keymap.VTERM_KEY_TAB;
    if (std.mem.eql(u8, name, "KEYCODE_DEL")) return keymap.VTERM_KEY_BACKSPACE;
    if (std.mem.eql(u8, name, "KEYCODE_ESCAPE")) return keymap.VTERM_KEY_ESCAPE;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_UP")) return keymap.VTERM_KEY_UP;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_DOWN")) return keymap.VTERM_KEY_DOWN;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_LEFT")) return keymap.VTERM_KEY_LEFT;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_RIGHT")) return keymap.VTERM_KEY_RIGHT;
    if (std.mem.eql(u8, name, "KEYCODE_INSERT")) return keymap.VTERM_KEY_INS;
    if (std.mem.eql(u8, name, "KEYCODE_FORWARD_DEL")) return keymap.VTERM_KEY_DEL;
    if (std.mem.eql(u8, name, "KEYCODE_MOVE_HOME")) return keymap.VTERM_KEY_HOME;
    if (std.mem.eql(u8, name, "KEYCODE_MOVE_END")) return keymap.VTERM_KEY_END;
    if (std.mem.eql(u8, name, "KEYCODE_PAGE_UP")) return keymap.VTERM_KEY_PAGEUP;
    if (std.mem.eql(u8, name, "KEYCODE_PAGE_DOWN")) return keymap.VTERM_KEY_PAGEDOWN;
    if (std.mem.eql(u8, name, "KEYCODE_F1")) return keymap.VTERM_KEY_F1;
    if (std.mem.eql(u8, name, "KEYCODE_F2")) return keymap.VTERM_KEY_F2;
    if (std.mem.eql(u8, name, "KEYCODE_F3")) return keymap.VTERM_KEY_F3;
    if (std.mem.eql(u8, name, "KEYCODE_F4")) return keymap.VTERM_KEY_F4;
    if (std.mem.eql(u8, name, "KEYCODE_F5")) return keymap.VTERM_KEY_F5;
    if (std.mem.eql(u8, name, "KEYCODE_F6")) return keymap.VTERM_KEY_F6;
    if (std.mem.eql(u8, name, "KEYCODE_F7")) return keymap.VTERM_KEY_F7;
    if (std.mem.eql(u8, name, "KEYCODE_F8")) return keymap.VTERM_KEY_F8;
    if (std.mem.eql(u8, name, "KEYCODE_F9")) return keymap.VTERM_KEY_F9;
    if (std.mem.eql(u8, name, "KEYCODE_F10")) return keymap.VTERM_KEY_F10;
    if (std.mem.eql(u8, name, "KEYCODE_F11")) return keymap.VTERM_KEY_F11;
    if (std.mem.eql(u8, name, "KEYCODE_F12")) return keymap.VTERM_KEY_F12;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_0")) return keymap.VTERM_KEY_KP_0;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_1")) return keymap.VTERM_KEY_KP_1;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_2")) return keymap.VTERM_KEY_KP_2;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_3")) return keymap.VTERM_KEY_KP_3;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_4")) return keymap.VTERM_KEY_KP_4;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_5")) return keymap.VTERM_KEY_KP_5;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_6")) return keymap.VTERM_KEY_KP_6;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_7")) return keymap.VTERM_KEY_KP_7;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_8")) return keymap.VTERM_KEY_KP_8;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_9")) return keymap.VTERM_KEY_KP_9;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_DOT")) return keymap.VTERM_KEY_KP_DECIMAL;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_ADD")) return keymap.VTERM_KEY_KP_ADD;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_SUBTRACT")) return keymap.VTERM_KEY_KP_SUBTRACT;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_MULTIPLY")) return keymap.VTERM_KEY_KP_MULTIPLY;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_DIVIDE")) return keymap.VTERM_KEY_KP_DIVIDE;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_ENTER")) return keymap.VTERM_KEY_KP_ENTER;
    return null;
}

/// Convert host modifier bits into input modifier flags.
pub fn parseModifierBits(mods: i32) keymap.Modifier {
    var out: keymap.Modifier = keymap.VTERM_MOD_NONE;
    if ((mods & 0x01) != 0) out |= keymap.VTERM_MOD_CTRL;
    if ((mods & 0x02) != 0) out |= keymap.VTERM_MOD_ALT;
    if ((mods & 0x04) != 0) out |= keymap.VTERM_MOD_SHIFT;
    return out;
}
