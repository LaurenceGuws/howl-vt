const std = @import("std");
const keyboard = @import("keyboard.zig");

/// Convert a host key token into a terminal key.
pub fn parseKeyToken(name: []const u8) ?keyboard.Key {
    if (std.mem.eql(u8, name, "KEYCODE_ENTER")) return keyboard.VTERM_KEY_ENTER;
    if (std.mem.eql(u8, name, "KEYCODE_TAB")) return keyboard.VTERM_KEY_TAB;
    if (std.mem.eql(u8, name, "KEYCODE_DEL")) return keyboard.VTERM_KEY_BACKSPACE;
    if (std.mem.eql(u8, name, "KEYCODE_ESCAPE")) return keyboard.VTERM_KEY_ESCAPE;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_UP")) return keyboard.VTERM_KEY_UP;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_DOWN")) return keyboard.VTERM_KEY_DOWN;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_LEFT")) return keyboard.VTERM_KEY_LEFT;
    if (std.mem.eql(u8, name, "KEYCODE_DPAD_RIGHT")) return keyboard.VTERM_KEY_RIGHT;
    if (std.mem.eql(u8, name, "KEYCODE_INSERT")) return keyboard.VTERM_KEY_INS;
    if (std.mem.eql(u8, name, "KEYCODE_FORWARD_DEL")) return keyboard.VTERM_KEY_DEL;
    if (std.mem.eql(u8, name, "KEYCODE_MOVE_HOME")) return keyboard.VTERM_KEY_HOME;
    if (std.mem.eql(u8, name, "KEYCODE_MOVE_END")) return keyboard.VTERM_KEY_END;
    if (std.mem.eql(u8, name, "KEYCODE_PAGE_UP")) return keyboard.VTERM_KEY_PAGEUP;
    if (std.mem.eql(u8, name, "KEYCODE_PAGE_DOWN")) return keyboard.VTERM_KEY_PAGEDOWN;
    if (std.mem.eql(u8, name, "KEYCODE_F1")) return keyboard.VTERM_KEY_F1;
    if (std.mem.eql(u8, name, "KEYCODE_F2")) return keyboard.VTERM_KEY_F2;
    if (std.mem.eql(u8, name, "KEYCODE_F3")) return keyboard.VTERM_KEY_F3;
    if (std.mem.eql(u8, name, "KEYCODE_F4")) return keyboard.VTERM_KEY_F4;
    if (std.mem.eql(u8, name, "KEYCODE_F5")) return keyboard.VTERM_KEY_F5;
    if (std.mem.eql(u8, name, "KEYCODE_F6")) return keyboard.VTERM_KEY_F6;
    if (std.mem.eql(u8, name, "KEYCODE_F7")) return keyboard.VTERM_KEY_F7;
    if (std.mem.eql(u8, name, "KEYCODE_F8")) return keyboard.VTERM_KEY_F8;
    if (std.mem.eql(u8, name, "KEYCODE_F9")) return keyboard.VTERM_KEY_F9;
    if (std.mem.eql(u8, name, "KEYCODE_F10")) return keyboard.VTERM_KEY_F10;
    if (std.mem.eql(u8, name, "KEYCODE_F11")) return keyboard.VTERM_KEY_F11;
    if (std.mem.eql(u8, name, "KEYCODE_F12")) return keyboard.VTERM_KEY_F12;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_0")) return keyboard.VTERM_KEY_KP_0;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_1")) return keyboard.VTERM_KEY_KP_1;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_2")) return keyboard.VTERM_KEY_KP_2;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_3")) return keyboard.VTERM_KEY_KP_3;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_4")) return keyboard.VTERM_KEY_KP_4;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_5")) return keyboard.VTERM_KEY_KP_5;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_6")) return keyboard.VTERM_KEY_KP_6;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_7")) return keyboard.VTERM_KEY_KP_7;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_8")) return keyboard.VTERM_KEY_KP_8;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_9")) return keyboard.VTERM_KEY_KP_9;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_DOT")) return keyboard.VTERM_KEY_KP_DECIMAL;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_ADD")) return keyboard.VTERM_KEY_KP_ADD;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_SUBTRACT")) return keyboard.VTERM_KEY_KP_SUBTRACT;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_MULTIPLY")) return keyboard.VTERM_KEY_KP_MULTIPLY;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_DIVIDE")) return keyboard.VTERM_KEY_KP_DIVIDE;
    if (std.mem.eql(u8, name, "KEYCODE_NUMPAD_ENTER")) return keyboard.VTERM_KEY_KP_ENTER;
    return null;
}

/// Convert host modifier bits into input modifier flags.
pub fn parseModifierBits(mods: i32) keyboard.Modifier {
    var out: keyboard.Modifier = keyboard.VTERM_MOD_NONE;
    if ((mods & 0x01) != 0) out |= keyboard.VTERM_MOD_CTRL;
    if ((mods & 0x02) != 0) out |= keyboard.VTERM_MOD_ALT;
    if ((mods & 0x04) != 0) out |= keyboard.VTERM_MOD_SHIFT;
    return out;
}
