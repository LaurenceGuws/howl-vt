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

pub const mod_none: Modifier = VTERM_MOD_NONE;
pub const mod_shift: Modifier = VTERM_MOD_SHIFT;
pub const mod_alt: Modifier = VTERM_MOD_ALT;
pub const mod_ctrl: Modifier = VTERM_MOD_CTRL;

pub const key_enter: Key = VTERM_KEY_ENTER;
pub const key_tab: Key = VTERM_KEY_TAB;
pub const key_backspace: Key = VTERM_KEY_BACKSPACE;
pub const key_escape: Key = VTERM_KEY_ESCAPE;
pub const key_up: Key = VTERM_KEY_UP;
pub const key_down: Key = VTERM_KEY_DOWN;
pub const key_left: Key = VTERM_KEY_LEFT;
pub const key_right: Key = VTERM_KEY_RIGHT;
pub const key_insert: Key = VTERM_KEY_INS;
pub const key_delete: Key = VTERM_KEY_DEL;
pub const key_home: Key = VTERM_KEY_HOME;
pub const key_end: Key = VTERM_KEY_END;
pub const key_pageup: Key = VTERM_KEY_PAGEUP;
pub const key_pagedown: Key = VTERM_KEY_PAGEDOWN;
pub const key_f1: Key = VTERM_KEY_F1;
pub const key_f2: Key = VTERM_KEY_F2;
pub const key_f3: Key = VTERM_KEY_F3;
pub const key_f4: Key = VTERM_KEY_F4;
pub const key_f5: Key = VTERM_KEY_F5;
pub const key_f6: Key = VTERM_KEY_F6;
pub const key_f7: Key = VTERM_KEY_F7;
pub const key_f8: Key = VTERM_KEY_F8;
pub const key_f9: Key = VTERM_KEY_F9;
pub const key_f10: Key = VTERM_KEY_F10;
pub const key_f11: Key = VTERM_KEY_F11;
pub const key_f12: Key = VTERM_KEY_F12;
pub const key_kp_0: Key = VTERM_KEY_KP_0;
pub const key_kp_1: Key = VTERM_KEY_KP_1;
pub const key_kp_2: Key = VTERM_KEY_KP_2;
pub const key_kp_3: Key = VTERM_KEY_KP_3;
pub const key_kp_4: Key = VTERM_KEY_KP_4;
pub const key_kp_5: Key = VTERM_KEY_KP_5;
pub const key_kp_6: Key = VTERM_KEY_KP_6;
pub const key_kp_7: Key = VTERM_KEY_KP_7;
pub const key_kp_8: Key = VTERM_KEY_KP_8;
pub const key_kp_9: Key = VTERM_KEY_KP_9;
pub const key_kp_decimal: Key = VTERM_KEY_KP_DECIMAL;
pub const key_kp_add: Key = VTERM_KEY_KP_ADD;
pub const key_kp_subtract: Key = VTERM_KEY_KP_SUBTRACT;
pub const key_kp_multiply: Key = VTERM_KEY_KP_MULTIPLY;
pub const key_kp_divide: Key = VTERM_KEY_KP_DIVIDE;
pub const key_kp_enter: Key = VTERM_KEY_KP_ENTER;

const max_encoded_len: usize = 32;

/// Encode one host key for the active terminal keyboard modes.
pub fn encodeKey(buf: []u8, key: Key, mod: Modifier, application_cursor_keys: bool, application_keypad: bool, modify_other_keys: i8, format_other_keys: u16, kitty_keyboard_flags: u32) []const u8 {
    std.debug.assert(validModifier(mod));
    if (kitty_keyboard_flags != 0) {
        if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
    }
    if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
    const shift_active = (mod & VTERM_MOD_SHIFT) != 0;

    if (encodeControlKey(buf, key, shift_active)) |encoded| return encoded;
    if (encodeCursorKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeHomeEndKey(buf, key, mod)) |encoded| return encoded;
    if (encodeTildeKey(buf, key, mod)) |encoded| return encoded;
    if (encodeFunctionKey(buf, key, mod)) |encoded| return encoded;
    return encodeTextKey(buf, key, mod, modify_other_keys, format_other_keys);
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
        std.debug.assert(buf.len >= 1);
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
    std.debug.assert(buf.len >= 3);
    buf[0] = '\x1b';
    buf[1] = 'O';
    buf[2] = final;
    return buf[0..3];
}

fn encodeModifyOtherKey(buf: []u8, key: Key, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) ?[]const u8 {
    if (modify_other_keys < 2 and !(modify_other_keys == 1 and format_other_keys == 1)) return null;
    if (mod == VTERM_MOD_NONE and modify_other_keys < 3) return null;
    std.debug.assert(validModifier(mod));
    if (format_other_keys == 1) return std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ key, @as(u8, 1) + mod }) catch null;
    return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ @as(u8, 1) + mod, key }) catch null;
}

fn encodeKittyKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    std.debug.assert(validModifier(mod));
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

fn encodeControlKey(buf: []u8, key: Key, shift_active: bool) ?[]const u8 {
    return switch (key) {
        VTERM_KEY_ENTER => singleByte(buf, '\r'),
        VTERM_KEY_TAB => if (shift_active) fixed3(buf, '\x1b', '[', 'Z') else singleByte(buf, '\t'),
        VTERM_KEY_BACKSPACE => singleByte(buf, '\x7f'),
        VTERM_KEY_ESCAPE => singleByte(buf, '\x1b'),
        else => null,
    };
}

fn encodeCursorKey(buf: []u8, key: Key, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        VTERM_KEY_UP => 'A',
        VTERM_KEY_DOWN => 'B',
        VTERM_KEY_RIGHT => 'C',
        VTERM_KEY_LEFT => 'D',
        else => return null,
    };
    return if (mod != VTERM_MOD_NONE)
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeHomeEndKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        VTERM_KEY_HOME => 'H',
        VTERM_KEY_END => 'F',
        else => return null,
    };
    return if (mod != VTERM_MOD_NONE)
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTildeKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const code: u8 = switch (key) {
        VTERM_KEY_INS => 2,
        VTERM_KEY_DEL => 3,
        VTERM_KEY_PAGEUP => 5,
        VTERM_KEY_PAGEDOWN => 6,
        VTERM_KEY_F5 => 15,
        VTERM_KEY_F6 => 17,
        VTERM_KEY_F7 => 18,
        VTERM_KEY_F8 => 19,
        VTERM_KEY_F9 => 20,
        VTERM_KEY_F10 => 21,
        VTERM_KEY_F11 => 23,
        VTERM_KEY_F12 => 24,
        else => return null,
    };
    return if (mod != VTERM_MOD_NONE)
        csiTildeModified(buf, code, mod)
    else
        csiTildePlain(buf, code);
}

fn encodeFunctionKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        VTERM_KEY_F1 => 'P',
        VTERM_KEY_F2 => 'Q',
        VTERM_KEY_F3 => 'R',
        VTERM_KEY_F4 => 'S',
        else => return null,
    };
    return if (mod != VTERM_MOD_NONE)
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTextKey(buf: []u8, key: Key, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) []const u8 {
    if (key > 31 and key < 127) {
        if (encodeModifyOtherKey(buf, key, mod, modify_other_keys, format_other_keys)) |encoded| return encoded;
        return singleByte(buf, @intCast(key)).?;
    }
    if (key > 127) {
        const len = std.unicode.utf8Encode(@intCast(key), buf[0..]) catch 0;
        std.debug.assert(len <= buf.len);
        return buf[0..len];
    }
    return buf[0..0];
}

fn singleByte(buf: []u8, byte: u8) ?[]const u8 {
    std.debug.assert(buf.len >= 1);
    buf[0] = byte;
    return buf[0..1];
}

fn fixed3(buf: []u8, a: u8, b: u8, c: u8) []const u8 {
    std.debug.assert(buf.len >= 3);
    buf[0] = a;
    buf[1] = b;
    buf[2] = c;
    return buf[0..3];
}

fn csi1ModifiedFinal(buf: []u8, final: u8, mod: Modifier) []const u8 {
    std.debug.assert(validModifier(mod));
    std.debug.assert(buf.len >= 6);
    buf[0] = '\x1b';
    buf[1] = '[';
    buf[2] = '1';
    buf[3] = ';';
    buf[4] = modifierParamDigit(mod);
    buf[5] = final;
    return buf[0..6];
}

fn csiTildePlain(buf: []u8, code: u8) []const u8 {
    std.debug.assert(buf.len >= 5);
    const tens = if (code >= 10) '0' + @divTrunc(code, 10) else null;
    buf[0] = '\x1b';
    buf[1] = '[';
    if (tens) |digit| {
        buf[2] = digit;
        buf[3] = '0' + @mod(code, 10);
        buf[4] = '~';
        return buf[0..5];
    }
    buf[2] = '0' + code;
    buf[3] = '~';
    return buf[0..4];
}

fn csiTildeModified(buf: []u8, code: u8, mod: Modifier) []const u8 {
    std.debug.assert(validModifier(mod));
    std.debug.assert(buf.len >= 7);
    const tens = if (code >= 10) '0' + @divTrunc(code, 10) else null;
    buf[0] = '\x1b';
    buf[1] = '[';
    if (tens) |digit| {
        buf[2] = digit;
        buf[3] = '0' + @mod(code, 10);
        buf[4] = ';';
        buf[5] = modifierParamDigit(mod);
        buf[6] = '~';
        return buf[0..7];
    }
    buf[2] = '0' + code;
    buf[3] = ';';
    buf[4] = modifierParamDigit(mod);
    buf[5] = '~';
    return buf[0..6];
}

fn modifierParamDigit(mod: Modifier) u8 {
    std.debug.assert(validModifier(mod));
    return '0' + (1 + mod);
}

fn validModifier(mod: Modifier) bool {
    return (mod & ~(VTERM_MOD_SHIFT | VTERM_MOD_ALT | VTERM_MOD_CTRL)) == 0;
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
