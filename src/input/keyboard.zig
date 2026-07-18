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
pub const key_none: Key = 0;
/// Enter/return key.
pub const key_enter: Key = 1;
/// Tab key.
pub const key_tab: Key = 2;
/// Backspace key.
pub const key_backspace: Key = 3;
/// Escape key.
pub const key_escape: Key = 4;
/// Arrow up key.
pub const key_up: Key = 5;
/// Arrow down key.
pub const key_down: Key = 6;
/// Arrow left key.
pub const key_left: Key = 7;
/// Arrow right key.
pub const key_right: Key = 8;
/// Insert key.
pub const key_insert: Key = 9;
/// Delete key.
pub const key_delete: Key = 10;
/// Home key.
pub const key_home: Key = 11;
/// End key.
pub const key_end: Key = 12;
/// Page up key.
pub const key_pageup: Key = 13;
/// Page down key.
pub const key_pagedown: Key = 14;
/// Left Shift key.
pub const key_left_shift: Key = 15;
/// Right Shift key.
pub const key_right_shift: Key = 16;
/// Left Control key.
pub const key_left_ctrl: Key = 17;
/// Right Control key.
pub const key_right_ctrl: Key = 18;
/// Left Alt key.
pub const key_left_alt: Key = 19;
/// Right Alt key.
pub const key_right_alt: Key = 20;
/// Left Super key.
pub const key_left_super: Key = 21;
/// Right Super key.
pub const key_right_super: Key = 22;
/// Function key F1.
pub const key_f1: Key = 23;
/// Function key F2.
pub const key_f2: Key = 24;
/// Function key F3.
pub const key_f3: Key = 25;
/// Function key F4.
pub const key_f4: Key = 26;
/// Function key F5.
pub const key_f5: Key = 27;
/// Function key F6.
pub const key_f6: Key = 28;
/// Function key F7.
pub const key_f7: Key = 29;
/// Function key F8.
pub const key_f8: Key = 30;
/// Function key F9.
pub const key_f9: Key = 31;
/// Function key F10.
pub const key_f10: Key = 32;
/// Function key F11.
pub const key_f11: Key = 33;
/// Function key F12.
pub const key_f12: Key = 34;
pub const key_kp_0: Key = 35;
pub const key_kp_1: Key = 36;
pub const key_kp_2: Key = 37;
pub const key_kp_3: Key = 38;
pub const key_kp_4: Key = 39;
pub const key_kp_5: Key = 40;
pub const key_kp_6: Key = 41;
pub const key_kp_7: Key = 42;
pub const key_kp_8: Key = 43;
pub const key_kp_9: Key = 44;
pub const key_kp_decimal: Key = 45;
pub const key_kp_add: Key = 46;
pub const key_kp_subtract: Key = 47;
pub const key_kp_multiply: Key = 48;
pub const key_kp_divide: Key = 49;
pub const key_kp_enter: Key = 50;

/// No modifiers.
pub const mod_none: Modifier = 0;
/// Shift modifier bit.
pub const mod_shift: Modifier = 1;
/// Alt modifier bit.
pub const mod_alt: Modifier = 2;
/// Control modifier bit.
pub const mod_ctrl: Modifier = 4;

const max_encoded_len: usize = 32;

/// Encode one host key for the active terminal keyboard modes.
pub fn encodeKey(
    buf: []u8,
    key: Key,
    mod: Modifier,
    application_cursor_keys: bool,
    application_keypad: bool,
    modify_other_keys: i8,
    format_other_keys: u16,
    kitty_keyboard_flags: u32,
) []const u8 {
    std.debug.assert(validModifier(mod));
    if (kitty_keyboard_flags != 0) {
        if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
    }
    if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
    const shift_active = (mod & mod_shift) != 0;

    if (encodeControlKey(buf, key, shift_active)) |encoded| return encoded;
    if (encodeCursorKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeHomeEndKey(buf, key, mod)) |encoded| return encoded;
    if (encodeTildeKey(buf, key, mod)) |encoded| return encoded;
    if (encodeFunctionKey(buf, key, mod)) |encoded| return encoded;
    return encodeTextKey(buf, key, mod, modify_other_keys, format_other_keys);
}

fn encodeKeypadKey(buf: []u8, key: Key, application_keypad: bool) ?[]const u8 {
    const normal: ?u8 = switch (key) {
        key_kp_0 => '0',
        key_kp_1 => '1',
        key_kp_2 => '2',
        key_kp_3 => '3',
        key_kp_4 => '4',
        key_kp_5 => '5',
        key_kp_6 => '6',
        key_kp_7 => '7',
        key_kp_8 => '8',
        key_kp_9 => '9',
        key_kp_decimal => '.',
        key_kp_add => '+',
        key_kp_subtract => '-',
        key_kp_multiply => '*',
        key_kp_divide => '/',
        key_kp_enter => '\r',
        else => null,
    };
    const ch = normal orelse return null;
    if (!application_keypad) {
        std.debug.assert(buf.len >= 1);
        buf[0] = ch;
        return buf[0..1];
    }
    const final: u8 = switch (key) {
        key_kp_0 => 'p',
        key_kp_1 => 'q',
        key_kp_2 => 'r',
        key_kp_3 => 's',
        key_kp_4 => 't',
        key_kp_5 => 'u',
        key_kp_6 => 'v',
        key_kp_7 => 'w',
        key_kp_8 => 'x',
        key_kp_9 => 'y',
        key_kp_decimal => 'n',
        key_kp_add => 'k',
        key_kp_subtract => 'm',
        key_kp_multiply => 'j',
        key_kp_divide => 'o',
        key_kp_enter => 'M',
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
    if (mod == mod_none and modify_other_keys < 3) return null;
    std.debug.assert(validModifier(mod));
    if (format_other_keys == 1) return std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ key, @as(u8, 1) + mod }) catch null;
    return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ @as(u8, 1) + mod, key }) catch null;
}

fn encodeKittyKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    std.debug.assert(validModifier(mod));
    const modifier = @as(u8, 1) + mod;
    switch (key) {
        key_enter => return csiU(buf, 13, modifier),
        key_tab => return csiU(buf, 9, modifier),
        key_backspace => return csiU(buf, 127, modifier),
        key_escape => return csiU(buf, 27, modifier),
        key_up => return csiFinal(buf, 'A', modifier),
        key_down => return csiFinal(buf, 'B', modifier),
        key_right => return csiFinal(buf, 'C', modifier),
        key_left => return csiFinal(buf, 'D', modifier),
        key_home => return csiFinal(buf, 'H', modifier),
        key_end => return csiFinal(buf, 'F', modifier),
        key_f1 => return csiFinal(buf, 'P', modifier),
        key_f2 => return csiFinal(buf, 'Q', modifier),
        key_f3 => return csiTilde(buf, 13, modifier),
        key_f4 => return csiFinal(buf, 'S', modifier),
        key_insert => return csiTilde(buf, 2, modifier),
        key_delete => return csiTilde(buf, 3, modifier),
        key_pageup => return csiTilde(buf, 5, modifier),
        key_pagedown => return csiTilde(buf, 6, modifier),
        key_f5 => return csiTilde(buf, 15, modifier),
        key_f6 => return csiTilde(buf, 17, modifier),
        key_f7 => return csiTilde(buf, 18, modifier),
        key_f8 => return csiTilde(buf, 19, modifier),
        key_f9 => return csiTilde(buf, 20, modifier),
        key_f10 => return csiTilde(buf, 21, modifier),
        key_f11 => return csiTilde(buf, 23, modifier),
        key_f12 => return csiTilde(buf, 24, modifier),
        else => return null,
    }
}

fn encodeControlKey(buf: []u8, key: Key, shift_active: bool) ?[]const u8 {
    return switch (key) {
        key_enter => singleByte(buf, '\r'),
        key_tab => if (shift_active) fixed3(buf, '\x1b', '[', 'Z') else singleByte(buf, '\t'),
        key_backspace => singleByte(buf, '\x7f'),
        key_escape => singleByte(buf, '\x1b'),
        else => null,
    };
}

fn encodeCursorKey(buf: []u8, key: Key, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        key_up => 'A',
        key_down => 'B',
        key_right => 'C',
        key_left => 'D',
        else => return null,
    };
    return if (mod != mod_none)
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeHomeEndKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        key_home => 'H',
        key_end => 'F',
        else => return null,
    };
    return if (mod != mod_none)
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTildeKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const code: u8 = switch (key) {
        key_insert => 2,
        key_delete => 3,
        key_pageup => 5,
        key_pagedown => 6,
        key_f5 => 15,
        key_f6 => 17,
        key_f7 => 18,
        key_f8 => 19,
        key_f9 => 20,
        key_f10 => 21,
        key_f11 => 23,
        key_f12 => 24,
        else => return null,
    };
    return if (mod != mod_none)
        csiTildeModified(buf, code, mod)
    else
        csiTildePlain(buf, code);
}

fn encodeFunctionKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        key_f1 => 'P',
        key_f2 => 'Q',
        key_f3 => 'R',
        key_f4 => 'S',
        else => return null,
    };
    return if (mod != mod_none)
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
    return (mod & ~(mod_shift | mod_alt | mod_ctrl)) == 0;
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
