//! Keyboard input values and escape encoding.

const std = @import("std");

/// Host physical-key identifier.
pub const PhysicalKey = u32;

/// Optional keyboard metadata attached to a key event.
pub const KeyboardAlternateMetadata = struct {
    physical_key: ?PhysicalKey = null,
    produced_text_utf8: ?[]const u8 = null,
    base_codepoint: ?u32 = null,
    shifted_codepoint: ?u32 = null,
    alternate_layout_codepoint: ?u32 = null,
    text_is_composed: bool = false,
};

/// Terminal key identifier type.
pub const Key = u32;
/// Terminal modifier bitset type.
pub const Modifier = u8;

/// No key.
pub const VTERM_KEY_NONE: Key = 0;
/// Enter/return key.
pub const VTERM_KEY_ENTER: Key = 1;
/// Tab key.
pub const VTERM_KEY_TAB: Key = 2;
/// Backspace key.
pub const VTERM_KEY_BACKSPACE: Key = 3;
/// Escape key.
pub const VTERM_KEY_ESCAPE: Key = 4;
/// Arrow up key.
pub const VTERM_KEY_UP: Key = 5;
/// Arrow down key.
pub const VTERM_KEY_DOWN: Key = 6;
/// Arrow left key.
pub const VTERM_KEY_LEFT: Key = 7;
/// Arrow right key.
pub const VTERM_KEY_RIGHT: Key = 8;
/// Insert key.
pub const VTERM_KEY_INS: Key = 9;
/// Delete key.
pub const VTERM_KEY_DEL: Key = 10;
/// Home key.
pub const VTERM_KEY_HOME: Key = 11;
/// End key.
pub const VTERM_KEY_END: Key = 12;
/// Page up key.
pub const VTERM_KEY_PAGEUP: Key = 13;
/// Page down key.
pub const VTERM_KEY_PAGEDOWN: Key = 14;
/// Left Shift key.
pub const VTERM_KEY_LEFT_SHIFT: Key = 15;
/// Right Shift key.
pub const VTERM_KEY_RIGHT_SHIFT: Key = 16;
/// Left Control key.
pub const VTERM_KEY_LEFT_CTRL: Key = 17;
/// Right Control key.
pub const VTERM_KEY_RIGHT_CTRL: Key = 18;
/// Left Alt key.
pub const VTERM_KEY_LEFT_ALT: Key = 19;
/// Right Alt key.
pub const VTERM_KEY_RIGHT_ALT: Key = 20;
/// Left Super key.
pub const VTERM_KEY_LEFT_SUPER: Key = 21;
/// Right Super key.
pub const VTERM_KEY_RIGHT_SUPER: Key = 22;
/// Function key F1.
pub const VTERM_KEY_F1: Key = 23;
/// Function key F2.
pub const VTERM_KEY_F2: Key = 24;
/// Function key F3.
pub const VTERM_KEY_F3: Key = 25;
/// Function key F4.
pub const VTERM_KEY_F4: Key = 26;
/// Function key F5.
pub const VTERM_KEY_F5: Key = 27;
/// Function key F6.
pub const VTERM_KEY_F6: Key = 28;
/// Function key F7.
pub const VTERM_KEY_F7: Key = 29;
/// Function key F8.
pub const VTERM_KEY_F8: Key = 30;
/// Function key F9.
pub const VTERM_KEY_F9: Key = 31;
/// Function key F10.
pub const VTERM_KEY_F10: Key = 32;
/// Function key F11.
pub const VTERM_KEY_F11: Key = 33;
/// Function key F12.
pub const VTERM_KEY_F12: Key = 34;
pub const VTERM_KEY_KP_0: Key = 35;
pub const VTERM_KEY_KP_1: Key = 36;
pub const VTERM_KEY_KP_2: Key = 37;
pub const VTERM_KEY_KP_3: Key = 38;
pub const VTERM_KEY_KP_4: Key = 39;
pub const VTERM_KEY_KP_5: Key = 40;
pub const VTERM_KEY_KP_6: Key = 41;
pub const VTERM_KEY_KP_7: Key = 42;
pub const VTERM_KEY_KP_8: Key = 43;
pub const VTERM_KEY_KP_9: Key = 44;
pub const VTERM_KEY_KP_DECIMAL: Key = 45;
pub const VTERM_KEY_KP_ADD: Key = 46;
pub const VTERM_KEY_KP_SUBTRACT: Key = 47;
pub const VTERM_KEY_KP_MULTIPLY: Key = 48;
pub const VTERM_KEY_KP_DIVIDE: Key = 49;
pub const VTERM_KEY_KP_ENTER: Key = 50;

/// No modifiers.
pub const VTERM_MOD_NONE: Modifier = 0;
/// Shift modifier bit.
pub const VTERM_MOD_SHIFT: Modifier = 1;
/// Alt modifier bit.
pub const VTERM_MOD_ALT: Modifier = 2;
/// Control modifier bit.
pub const VTERM_MOD_CTRL: Modifier = 4;
/// Encode one host key for the active terminal keyboard modes.
pub fn encodeKey(buf: []u8, key: Key, mod: Modifier, application_cursor_keys: bool, application_keypad: bool, modify_other_keys: i8, format_other_keys: u16, kitty_keyboard_flags: u32) []const u8 {
    if (kitty_keyboard_flags != 0) {
        if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
    }
    if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
    var len: usize = 0;
    const shift_active = (mod & VTERM_MOD_SHIFT) != 0;

    switch (key) {
        VTERM_KEY_ENTER => {
            buf[0] = '\r';
            len = 1;
        },
        VTERM_KEY_TAB => {
            if (shift_active) {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = 'Z';
                len = 3;
            } else {
                buf[0] = '\t';
                len = 1;
            }
        },
        VTERM_KEY_BACKSPACE => {
            buf[0] = '\x7f';
            len = 1;
        },
        VTERM_KEY_ESCAPE => {
            buf[0] = '\x1b';
            len = 1;
        },
        VTERM_KEY_UP => {
            buf[0] = '\x1b';
            if (mod != VTERM_MOD_NONE) {
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'A';
                len = 6;
            } else if (application_cursor_keys) {
                buf[1] = 'O';
                buf[2] = 'A';
                len = 3;
            } else {
                buf[1] = '[';
                buf[2] = 'A';
                len = 3;
            }
        },
        VTERM_KEY_DOWN => {
            buf[0] = '\x1b';
            if (mod != VTERM_MOD_NONE) {
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'B';
                len = 6;
            } else if (application_cursor_keys) {
                buf[1] = 'O';
                buf[2] = 'B';
                len = 3;
            } else {
                buf[1] = '[';
                buf[2] = 'B';
                len = 3;
            }
        },
        VTERM_KEY_RIGHT => {
            buf[0] = '\x1b';
            if (mod != VTERM_MOD_NONE) {
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'C';
                len = 6;
            } else if (application_cursor_keys) {
                buf[1] = 'O';
                buf[2] = 'C';
                len = 3;
            } else {
                buf[1] = '[';
                buf[2] = 'C';
                len = 3;
            }
        },
        VTERM_KEY_LEFT => {
            buf[0] = '\x1b';
            if (mod != VTERM_MOD_NONE) {
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'D';
                len = 6;
            } else if (application_cursor_keys) {
                buf[1] = 'O';
                buf[2] = 'D';
                len = 3;
            } else {
                buf[1] = '[';
                buf[2] = 'D';
                len = 3;
            }
        },
        VTERM_KEY_HOME => {
            buf[0] = '\x1b';
            buf[1] = '[';
            if (mod != VTERM_MOD_NONE) {
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'H';
                len = 6;
            } else {
                buf[2] = 'H';
                len = 3;
            }
        },
        VTERM_KEY_END => {
            buf[0] = '\x1b';
            buf[1] = '[';
            if (mod != VTERM_MOD_NONE) {
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'F';
                len = 6;
            } else {
                buf[2] = 'F';
                len = 3;
            }
        },
        VTERM_KEY_INS => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '2';
            if (mod != VTERM_MOD_NONE) {
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = '~';
                len = 6;
            } else {
                buf[3] = '~';
                len = 4;
            }
        },
        VTERM_KEY_DEL => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '3';
            if (mod != VTERM_MOD_NONE) {
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = '~';
                len = 6;
            } else {
                buf[3] = '~';
                len = 4;
            }
        },
        VTERM_KEY_PAGEUP => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '5';
            if (mod != VTERM_MOD_NONE) {
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = '~';
                len = 6;
            } else {
                buf[3] = '~';
                len = 4;
            }
        },
        VTERM_KEY_PAGEDOWN => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '6';
            if (mod != VTERM_MOD_NONE) {
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = '~';
                len = 6;
            } else {
                buf[3] = '~';
                len = 4;
            }
        },
        VTERM_KEY_F1 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            if (mod != VTERM_MOD_NONE) {
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'P';
                len = 6;
            } else {
                buf[2] = 'P';
                len = 3;
            }
        },
        VTERM_KEY_F2 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            if (mod != VTERM_MOD_NONE) {
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'Q';
                len = 6;
            } else {
                buf[2] = 'Q';
                len = 3;
            }
        },
        VTERM_KEY_F3 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            if (mod != VTERM_MOD_NONE) {
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'R';
                len = 6;
            } else {
                buf[2] = 'R';
                len = 3;
            }
        },
        VTERM_KEY_F4 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            if (mod != VTERM_MOD_NONE) {
                buf[2] = '1';
                buf[3] = ';';
                buf[4] = '0' + (1 + mod);
                buf[5] = 'S';
                len = 6;
            } else {
                buf[2] = 'S';
                len = 3;
            }
        },
        VTERM_KEY_F5 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '1';
            buf[3] = '5';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F6 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '1';
            buf[3] = '7';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F7 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '1';
            buf[3] = '8';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F8 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '1';
            buf[3] = '9';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F9 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '2';
            buf[3] = '0';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F10 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '2';
            buf[3] = '1';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F11 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '2';
            buf[3] = '3';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        VTERM_KEY_F12 => {
            buf[0] = '\x1b';
            buf[1] = '[';
            buf[2] = '2';
            buf[3] = '4';
            if (mod != VTERM_MOD_NONE) {
                buf[4] = ';';
                buf[5] = '0' + (1 + mod);
                buf[6] = '~';
                len = 7;
            } else {
                buf[4] = '~';
                len = 5;
            }
        },
        else => {
            if (key > 31 and key < 127) {
                if (encodeModifyOtherKey(buf, key, mod, modify_other_keys, format_other_keys)) |encoded| return encoded;
                buf[0] = @intCast(key);
                len = 1;
            } else if (key > 127) {
                len = std.unicode.utf8Encode(@intCast(key), buf[0..]) catch 0;
            }
        },
    }

    return buf[0..len];
}

fn encodeKeypadKey(buf: []u8, key: Key, application_keypad: bool) ?[]const u8 {
    const normal: ?u8 = switch (key) {
        VTERM_KEY_KP_0 => '0',
        VTERM_KEY_KP_1 => '1',
        VTERM_KEY_KP_2 => '2',
        VTERM_KEY_KP_3 => '3',
        VTERM_KEY_KP_4 => '4',
        VTERM_KEY_KP_5 => '5',
        VTERM_KEY_KP_6 => '6',
        VTERM_KEY_KP_7 => '7',
        VTERM_KEY_KP_8 => '8',
        VTERM_KEY_KP_9 => '9',
        VTERM_KEY_KP_DECIMAL => '.',
        VTERM_KEY_KP_ADD => '+',
        VTERM_KEY_KP_SUBTRACT => '-',
        VTERM_KEY_KP_MULTIPLY => '*',
        VTERM_KEY_KP_DIVIDE => '/',
        VTERM_KEY_KP_ENTER => '\r',
        else => null,
    };
    const ch = normal orelse return null;
    if (!application_keypad) {
        buf[0] = ch;
        return buf[0..1];
    }
    const final: u8 = switch (key) {
        VTERM_KEY_KP_0 => 'p',
        VTERM_KEY_KP_1 => 'q',
        VTERM_KEY_KP_2 => 'r',
        VTERM_KEY_KP_3 => 's',
        VTERM_KEY_KP_4 => 't',
        VTERM_KEY_KP_5 => 'u',
        VTERM_KEY_KP_6 => 'v',
        VTERM_KEY_KP_7 => 'w',
        VTERM_KEY_KP_8 => 'x',
        VTERM_KEY_KP_9 => 'y',
        VTERM_KEY_KP_DECIMAL => 'n',
        VTERM_KEY_KP_ADD => 'k',
        VTERM_KEY_KP_SUBTRACT => 'm',
        VTERM_KEY_KP_MULTIPLY => 'j',
        VTERM_KEY_KP_DIVIDE => 'o',
        VTERM_KEY_KP_ENTER => 'M',
        else => return null,
    };
    buf[0] = '\x1b';
    buf[1] = 'O';
    buf[2] = final;
    return buf[0..3];
}

fn encodeModifyOtherKey(buf: []u8, key: Key, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) ?[]const u8 {
    if (modify_other_keys < 2 and !(modify_other_keys == 1 and format_other_keys == 1)) return null;
    if (mod == VTERM_MOD_NONE and modify_other_keys < 3) return null;
    if (format_other_keys == 1) return std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ key, @as(u8, 1) + mod }) catch null;
    return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ @as(u8, 1) + mod, key }) catch null;
}

fn encodeKittyKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const modifier = @as(u8, 1) + mod;
    switch (key) {
        VTERM_KEY_ENTER => return csiU(buf, 13, modifier),
        VTERM_KEY_TAB => return csiU(buf, 9, modifier),
        VTERM_KEY_BACKSPACE => return csiU(buf, 127, modifier),
        VTERM_KEY_ESCAPE => return csiU(buf, 27, modifier),
        VTERM_KEY_UP => return csiFinal(buf, 'A', modifier),
        VTERM_KEY_DOWN => return csiFinal(buf, 'B', modifier),
        VTERM_KEY_RIGHT => return csiFinal(buf, 'C', modifier),
        VTERM_KEY_LEFT => return csiFinal(buf, 'D', modifier),
        VTERM_KEY_HOME => return csiFinal(buf, 'H', modifier),
        VTERM_KEY_END => return csiFinal(buf, 'F', modifier),
        VTERM_KEY_F1 => return csiFinal(buf, 'P', modifier),
        VTERM_KEY_F2 => return csiFinal(buf, 'Q', modifier),
        VTERM_KEY_F3 => return csiTilde(buf, 13, modifier),
        VTERM_KEY_F4 => return csiFinal(buf, 'S', modifier),
        VTERM_KEY_INS => return csiTilde(buf, 2, modifier),
        VTERM_KEY_DEL => return csiTilde(buf, 3, modifier),
        VTERM_KEY_PAGEUP => return csiTilde(buf, 5, modifier),
        VTERM_KEY_PAGEDOWN => return csiTilde(buf, 6, modifier),
        VTERM_KEY_F5 => return csiTilde(buf, 15, modifier),
        VTERM_KEY_F6 => return csiTilde(buf, 17, modifier),
        VTERM_KEY_F7 => return csiTilde(buf, 18, modifier),
        VTERM_KEY_F8 => return csiTilde(buf, 19, modifier),
        VTERM_KEY_F9 => return csiTilde(buf, 20, modifier),
        VTERM_KEY_F10 => return csiTilde(buf, 21, modifier),
        VTERM_KEY_F11 => return csiTilde(buf, 23, modifier),
        VTERM_KEY_F12 => return csiTilde(buf, 24, modifier),
        else => return null,
    }
}

fn csiU(buf: []u8, code: u32, modifier: u8) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{d}u", .{code}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ code, modifier }) catch "";
}

fn csiFinal(buf: []u8, final: u8, modifier: u8) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{c}", .{final}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[1;{d}{c}", .{ modifier, final }) catch "";
}

fn csiTilde(buf: []u8, code: u32, modifier: u8) []const u8 {
    return if (modifier == 1)
        std.fmt.bufPrint(buf, "\x1b[{d}~", .{code}) catch ""
    else
        std.fmt.bufPrint(buf, "\x1b[{d};{d}~", .{ code, modifier }) catch "";
}
