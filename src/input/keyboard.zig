const std = @import("std");

/// Named physical key whose terminal identity is distinct from Unicode text.
pub const NamedKey = enum {
    enter,
    tab,
    backspace,
    escape,
    up,
    down,
    left,
    right,
    insert,
    delete,
    home,
    end,
    page_up,
    page_down,
    left_shift,
    right_shift,
    left_control,
    right_control,
    left_alt,
    right_alt,
    left_super,
    right_super,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    keypad_0,
    keypad_1,
    keypad_2,
    keypad_3,
    keypad_4,
    keypad_5,
    keypad_6,
    keypad_7,
    keypad_8,
    keypad_9,
    keypad_decimal,
    keypad_add,
    keypad_subtract,
    keypad_multiply,
    keypad_divide,
    keypad_enter,
};

/// Valid Unicode scalar produced by one physical key event.
pub const UnicodeScalar = struct {
    value: u21,

    /// Validate one scalar before it enters terminal keyboard encoding.
    ///
    /// Surrogate halves and values outside Unicode's scalar range are rejected.
    pub fn init(value: u21) error{InvalidUnicodeScalar}!UnicodeScalar {
        if (!std.unicode.utf8ValidCodepoint(value)) return error.InvalidUnicodeScalar;
        return .{ .value = value };
    }
};

/// Physical key identity consumed by terminal keyboard protocols.
pub const Key = union(enum) {
    named: NamedKey,
    unicode: UnicodeScalar,

    /// Construct a Unicode key, rejecting non-scalar values.
    pub fn initUnicode(value: u21) error{InvalidUnicodeScalar}!Key {
        return .{ .unicode = try UnicodeScalar.init(value) };
    }
};

/// Complete modifier state accepted by terminal keyboard and mouse protocols.
///
/// The packed representation has no spare bits, so every value is valid.
pub const Modifier = packed struct(u3) {
    shift: bool = false,
    alt: bool = false,
    control: bool = false,

    fn protocolBits(self: Modifier) u3 {
        return @bitCast(self);
    }

    fn protocolParameter(self: Modifier) u8 {
        return 1 + @as(u8, self.protocolBits());
    }

    fn none(self: Modifier) bool {
        return self.protocolBits() == 0;
    }
};

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
    if (kitty_keyboard_flags != 0) {
        if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
    }
    return switch (key) {
        .named => |named| encodeNamedKey(buf, named, mod, application_cursor_keys, application_keypad),
        .unicode => |scalar| encodeTextKey(buf, scalar.value, mod, modify_other_keys, format_other_keys),
    };
}

fn encodeNamedKey(buf: []u8, key: NamedKey, mod: Modifier, application_cursor_keys: bool, application_keypad: bool) []const u8 {
    if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
    if (encodeControlKey(buf, key, mod.shift)) |encoded| return encoded;
    if (encodeCursorKey(buf, key, mod, application_cursor_keys)) |encoded| return encoded;
    if (encodeHomeEndKey(buf, key, mod)) |encoded| return encoded;
    if (encodeTildeKey(buf, key, mod)) |encoded| return encoded;
    if (encodeFunctionKey(buf, key, mod)) |encoded| return encoded;
    return buf[0..0];
}

fn encodeKeypadKey(buf: []u8, key: NamedKey, application_keypad: bool) ?[]const u8 {
    const normal: ?u8 = switch (key) {
        .keypad_0 => '0',
        .keypad_1 => '1',
        .keypad_2 => '2',
        .keypad_3 => '3',
        .keypad_4 => '4',
        .keypad_5 => '5',
        .keypad_6 => '6',
        .keypad_7 => '7',
        .keypad_8 => '8',
        .keypad_9 => '9',
        .keypad_decimal => '.',
        .keypad_add => '+',
        .keypad_subtract => '-',
        .keypad_multiply => '*',
        .keypad_divide => '/',
        .keypad_enter => '\r',
        else => null,
    };
    const ch = normal orelse return null;
    if (!application_keypad) {
        std.debug.assert(buf.len >= 1);
        buf[0] = ch;
        return buf[0..1];
    }
    const final: u8 = switch (key) {
        .keypad_0 => 'p',
        .keypad_1 => 'q',
        .keypad_2 => 'r',
        .keypad_3 => 's',
        .keypad_4 => 't',
        .keypad_5 => 'u',
        .keypad_6 => 'v',
        .keypad_7 => 'w',
        .keypad_8 => 'x',
        .keypad_9 => 'y',
        .keypad_decimal => 'n',
        .keypad_add => 'k',
        .keypad_subtract => 'm',
        .keypad_multiply => 'j',
        .keypad_divide => 'o',
        .keypad_enter => 'M',
        else => return null,
    };
    std.debug.assert(buf.len >= 3);
    buf[0] = '\x1b';
    buf[1] = 'O';
    buf[2] = final;
    return buf[0..3];
}

fn encodeModifyOtherKey(buf: []u8, codepoint: u21, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) ?[]const u8 {
    if (modify_other_keys < 2 and !(modify_other_keys == 1 and format_other_keys == 1)) return null;
    if (mod.none() and modify_other_keys < 3) return null;
    if (format_other_keys == 1) return std.fmt.bufPrint(buf, "\x1b[{d};{d}u", .{ codepoint, mod.protocolParameter() }) catch null;
    return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ mod.protocolParameter(), codepoint }) catch null;
}

fn encodeKittyKey(buf: []u8, key: Key, mod: Modifier) ?[]const u8 {
    const modifier = mod.protocolParameter();
    return switch (key) {
        .unicode => |scalar| csiU(buf, scalar.value, modifier),
        .named => |named| switch (named) {
            .enter => csiU(buf, 13, modifier),
            .tab => csiU(buf, 9, modifier),
            .backspace => csiU(buf, 127, modifier),
            .escape => csiU(buf, 27, modifier),
            .up => csiFinal(buf, 'A', modifier),
            .down => csiFinal(buf, 'B', modifier),
            .right => csiFinal(buf, 'C', modifier),
            .left => csiFinal(buf, 'D', modifier),
            .home => csiFinal(buf, 'H', modifier),
            .end => csiFinal(buf, 'F', modifier),
            .f1 => csiFinal(buf, 'P', modifier),
            .f2 => csiFinal(buf, 'Q', modifier),
            .f3 => csiTilde(buf, 13, modifier),
            .f4 => csiFinal(buf, 'S', modifier),
            .insert => csiTilde(buf, 2, modifier),
            .delete => csiTilde(buf, 3, modifier),
            .page_up => csiTilde(buf, 5, modifier),
            .page_down => csiTilde(buf, 6, modifier),
            .f5 => csiTilde(buf, 15, modifier),
            .f6 => csiTilde(buf, 17, modifier),
            .f7 => csiTilde(buf, 18, modifier),
            .f8 => csiTilde(buf, 19, modifier),
            .f9 => csiTilde(buf, 20, modifier),
            .f10 => csiTilde(buf, 21, modifier),
            .f11 => csiTilde(buf, 23, modifier),
            .f12 => csiTilde(buf, 24, modifier),
            else => null,
        },
    };
}

fn encodeControlKey(buf: []u8, key: NamedKey, shift_active: bool) ?[]const u8 {
    return switch (key) {
        .enter => singleByte(buf, '\r'),
        .tab => if (shift_active) fixed3(buf, '\x1b', '[', 'Z') else singleByte(buf, '\t'),
        .backspace => singleByte(buf, '\x7f'),
        .escape => singleByte(buf, '\x1b'),
        else => null,
    };
}

fn encodeCursorKey(buf: []u8, key: NamedKey, mod: Modifier, application_cursor_keys: bool) ?[]const u8 {
    const final: u8 = switch (key) {
        .up => 'A',
        .down => 'B',
        .right => 'C',
        .left => 'D',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else if (application_cursor_keys)
        fixed3(buf, '\x1b', 'O', final)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeHomeEndKey(buf: []u8, key: NamedKey, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        .home => 'H',
        .end => 'F',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTildeKey(buf: []u8, key: NamedKey, mod: Modifier) ?[]const u8 {
    const code: u8 = switch (key) {
        .insert => 2,
        .delete => 3,
        .page_up => 5,
        .page_down => 6,
        .f5 => 15,
        .f6 => 17,
        .f7 => 18,
        .f8 => 19,
        .f9 => 20,
        .f10 => 21,
        .f11 => 23,
        .f12 => 24,
        else => return null,
    };
    return if (!mod.none())
        csiTildeModified(buf, code, mod)
    else
        csiTildePlain(buf, code);
}

fn encodeFunctionKey(buf: []u8, key: NamedKey, mod: Modifier) ?[]const u8 {
    const final: u8 = switch (key) {
        .f1 => 'P',
        .f2 => 'Q',
        .f3 => 'R',
        .f4 => 'S',
        else => return null,
    };
    return if (!mod.none())
        csi1ModifiedFinal(buf, final, mod)
    else
        fixed3(buf, '\x1b', '[', final);
}

fn encodeTextKey(buf: []u8, codepoint: u21, mod: Modifier, modify_other_keys: i8, format_other_keys: u16) []const u8 {
    if (codepoint > 31 and codepoint < 127) {
        if (encodeModifyOtherKey(buf, codepoint, mod, modify_other_keys, format_other_keys)) |encoded| return encoded;
        return singleByte(buf, @intCast(codepoint)).?;
    }
    if (codepoint > 127) {
        const len = std.unicode.utf8Encode(codepoint, buf[0..]) catch unreachable;
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
    return '0' + mod.protocolParameter();
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

test "typed key identity separates old integer collisions" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};
    const unicode_soh = try Key.initUnicode(1);

    try std.testing.expectEqualStrings("\r", encodeKey(&buf, .{ .named = .enter }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("", encodeKey(&buf, unicode_soh, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[1u", encodeKey(&buf, unicode_soh, none, false, false, 0, 0, 1));
    try std.testing.expectError(error.InvalidUnicodeScalar, Key.initUnicode(0xD800));
}

test "named key classes retain exact legacy encodings" {
    var buf: [max_encoded_len]u8 = undefined;
    const none = Modifier{};

    try std.testing.expectEqualStrings("\t", encodeKey(&buf, .{ .named = .tab }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[H", encodeKey(&buf, .{ .named = .home }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[3~", encodeKey(&buf, .{ .named = .delete }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[P", encodeKey(&buf, .{ .named = .f1 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1b[24~", encodeKey(&buf, .{ .named = .f12 }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("+", encodeKey(&buf, .{ .named = .keypad_add }, none, false, false, 0, 0, 0));
    try std.testing.expectEqualStrings("\x1bOk", encodeKey(&buf, .{ .named = .keypad_add }, none, false, true, 0, 0, 0));
    try std.testing.expectEqualStrings("", encodeKey(&buf, .{ .named = .left_shift }, none, false, false, 0, 0, 0));
}

test "every modifier combination has one Kitty parameter" {
    var buf: [max_encoded_len]u8 = undefined;
    const scalar = try Key.initUnicode('a');
    const cases = [_]struct { modifier: Modifier, expected: []const u8 }{
        .{ .modifier = .{}, .expected = "\x1b[97u" },
        .{ .modifier = .{ .shift = true }, .expected = "\x1b[97;2u" },
        .{ .modifier = .{ .alt = true }, .expected = "\x1b[97;3u" },
        .{ .modifier = .{ .shift = true, .alt = true }, .expected = "\x1b[97;4u" },
        .{ .modifier = .{ .control = true }, .expected = "\x1b[97;5u" },
        .{ .modifier = .{ .shift = true, .control = true }, .expected = "\x1b[97;6u" },
        .{ .modifier = .{ .alt = true, .control = true }, .expected = "\x1b[97;7u" },
        .{ .modifier = .{ .shift = true, .alt = true, .control = true }, .expected = "\x1b[97;8u" },
    };
    for (cases) |case| {
        try std.testing.expectEqualStrings(case.expected, encodeKey(&buf, scalar, case.modifier, false, false, 0, 0, 1));
    }
}
