//! Responsibility: expose stable host-input encoding and token parsing facade.
//! Ownership: input codec boundary.
//! Reason: keep vt_core insulated from input owner splits.

const std = @import("std");
const keymap = @import("keymap.zig");
const mouse = @import("mouse.zig");
const mouse_encode = @import("mouse_encode.zig");
const tokens = @import("tokens.zig");

/// Stable facade for host input conversion.
pub const InputCodec = struct {
    /// Encode one host key for the active terminal keyboard modes.
    pub fn encodeKey(buf: []u8, key: keymap.Key, mod: keymap.Modifier, application_cursor_keys: bool, application_keypad: bool, modify_other_keys: i8, kitty_keyboard_flags: u32) []const u8 {
        if (kitty_keyboard_flags != 0) {
            if (encodeKittyKey(buf, key, mod)) |encoded| return encoded;
        }
        if (encodeKeypadKey(buf, key, application_keypad)) |encoded| return encoded;
        var len: usize = 0;
        const shift_active = (mod & keymap.VTERM_MOD_SHIFT) != 0;

        switch (key) {
            keymap.VTERM_KEY_ENTER => {
                buf[0] = '\r';
                len = 1;
            },
            keymap.VTERM_KEY_TAB => {
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
            keymap.VTERM_KEY_BACKSPACE => {
                buf[0] = '\x7f';
                len = 1;
            },
            keymap.VTERM_KEY_ESCAPE => {
                buf[0] = '\x1b';
                len = 1;
            },
            keymap.VTERM_KEY_UP => {
                buf[0] = '\x1b';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_DOWN => {
                buf[0] = '\x1b';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_RIGHT => {
                buf[0] = '\x1b';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_LEFT => {
                buf[0] = '\x1b';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_HOME => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_END => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_INS => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_DEL => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '3';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_PAGEUP => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '5';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_PAGEDOWN => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '6';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[3] = ';';
                    buf[4] = '0' + (1 + mod);
                    buf[5] = '~';
                    len = 6;
                } else {
                    buf[3] = '~';
                    len = 4;
                }
            },
            keymap.VTERM_KEY_F1 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F2 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F3 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F4 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                if (mod != keymap.VTERM_MOD_NONE) {
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
            keymap.VTERM_KEY_F5 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '5';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F6 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '7';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F7 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '8';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F8 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '1';
                buf[3] = '9';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F9 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '0';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F10 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '1';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F11 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '3';
                if (mod != keymap.VTERM_MOD_NONE) {
                    buf[4] = ';';
                    buf[5] = '0' + (1 + mod);
                    buf[6] = '~';
                    len = 7;
                } else {
                    buf[4] = '~';
                    len = 5;
                }
            },
            keymap.VTERM_KEY_F12 => {
                buf[0] = '\x1b';
                buf[1] = '[';
                buf[2] = '2';
                buf[3] = '4';
                if (mod != keymap.VTERM_MOD_NONE) {
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
                    if (encodeModifyOtherKey(buf, key, mod, modify_other_keys)) |encoded| return encoded;
                    buf[0] = @intCast(key);
                    len = 1;
                } else if (key > 127) {
                    len = std.unicode.utf8Encode(@intCast(key), buf[0..]) catch 0;
                }
            },
        }

        return buf[0..len];
    }

    fn encodeKeypadKey(buf: []u8, key: keymap.Key, application_keypad: bool) ?[]const u8 {
        const normal: ?u8 = switch (key) {
            keymap.VTERM_KEY_KP_0 => '0',
            keymap.VTERM_KEY_KP_1 => '1',
            keymap.VTERM_KEY_KP_2 => '2',
            keymap.VTERM_KEY_KP_3 => '3',
            keymap.VTERM_KEY_KP_4 => '4',
            keymap.VTERM_KEY_KP_5 => '5',
            keymap.VTERM_KEY_KP_6 => '6',
            keymap.VTERM_KEY_KP_7 => '7',
            keymap.VTERM_KEY_KP_8 => '8',
            keymap.VTERM_KEY_KP_9 => '9',
            keymap.VTERM_KEY_KP_DECIMAL => '.',
            keymap.VTERM_KEY_KP_ADD => '+',
            keymap.VTERM_KEY_KP_SUBTRACT => '-',
            keymap.VTERM_KEY_KP_MULTIPLY => '*',
            keymap.VTERM_KEY_KP_DIVIDE => '/',
            keymap.VTERM_KEY_KP_ENTER => '\r',
            else => null,
        };
        const ch = normal orelse return null;
        if (!application_keypad) {
            buf[0] = ch;
            return buf[0..1];
        }
        const final: u8 = switch (key) {
            keymap.VTERM_KEY_KP_0 => 'p',
            keymap.VTERM_KEY_KP_1 => 'q',
            keymap.VTERM_KEY_KP_2 => 'r',
            keymap.VTERM_KEY_KP_3 => 's',
            keymap.VTERM_KEY_KP_4 => 't',
            keymap.VTERM_KEY_KP_5 => 'u',
            keymap.VTERM_KEY_KP_6 => 'v',
            keymap.VTERM_KEY_KP_7 => 'w',
            keymap.VTERM_KEY_KP_8 => 'x',
            keymap.VTERM_KEY_KP_9 => 'y',
            keymap.VTERM_KEY_KP_DECIMAL => 'n',
            keymap.VTERM_KEY_KP_ADD => 'k',
            keymap.VTERM_KEY_KP_SUBTRACT => 'm',
            keymap.VTERM_KEY_KP_MULTIPLY => 'j',
            keymap.VTERM_KEY_KP_DIVIDE => 'o',
            keymap.VTERM_KEY_KP_ENTER => 'M',
            else => return null,
        };
        buf[0] = '\x1b';
        buf[1] = 'O';
        buf[2] = final;
        return buf[0..3];
    }

    fn encodeModifyOtherKey(buf: []u8, key: keymap.Key, mod: keymap.Modifier, modify_other_keys: i8) ?[]const u8 {
        if (modify_other_keys < 2) return null;
        if (mod == keymap.VTERM_MOD_NONE and modify_other_keys < 3) return null;
        return std.fmt.bufPrint(buf, "\x1b[27;{d};{d}~", .{ @as(u8, 1) + mod, key }) catch null;
    }

    fn encodeKittyKey(buf: []u8, key: keymap.Key, mod: keymap.Modifier) ?[]const u8 {
        const modifier = @as(u8, 1) + mod;
        switch (key) {
            keymap.VTERM_KEY_ENTER => return csiU(buf, 13, modifier),
            keymap.VTERM_KEY_TAB => return csiU(buf, 9, modifier),
            keymap.VTERM_KEY_BACKSPACE => return csiU(buf, 127, modifier),
            keymap.VTERM_KEY_ESCAPE => return csiU(buf, 27, modifier),
            keymap.VTERM_KEY_UP => return csiFinal(buf, 'A', modifier),
            keymap.VTERM_KEY_DOWN => return csiFinal(buf, 'B', modifier),
            keymap.VTERM_KEY_RIGHT => return csiFinal(buf, 'C', modifier),
            keymap.VTERM_KEY_LEFT => return csiFinal(buf, 'D', modifier),
            keymap.VTERM_KEY_HOME => return csiFinal(buf, 'H', modifier),
            keymap.VTERM_KEY_END => return csiFinal(buf, 'F', modifier),
            keymap.VTERM_KEY_F1 => return csiFinal(buf, 'P', modifier),
            keymap.VTERM_KEY_F2 => return csiFinal(buf, 'Q', modifier),
            keymap.VTERM_KEY_F3 => return csiTilde(buf, 13, modifier),
            keymap.VTERM_KEY_F4 => return csiFinal(buf, 'S', modifier),
            keymap.VTERM_KEY_INS => return csiTilde(buf, 2, modifier),
            keymap.VTERM_KEY_DEL => return csiTilde(buf, 3, modifier),
            keymap.VTERM_KEY_PAGEUP => return csiTilde(buf, 5, modifier),
            keymap.VTERM_KEY_PAGEDOWN => return csiTilde(buf, 6, modifier),
            keymap.VTERM_KEY_F5 => return csiTilde(buf, 15, modifier),
            keymap.VTERM_KEY_F6 => return csiTilde(buf, 17, modifier),
            keymap.VTERM_KEY_F7 => return csiTilde(buf, 18, modifier),
            keymap.VTERM_KEY_F8 => return csiTilde(buf, 19, modifier),
            keymap.VTERM_KEY_F9 => return csiTilde(buf, 20, modifier),
            keymap.VTERM_KEY_F10 => return csiTilde(buf, 21, modifier),
            keymap.VTERM_KEY_F11 => return csiTilde(buf, 23, modifier),
            keymap.VTERM_KEY_F12 => return csiTilde(buf, 24, modifier),
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

    /// Encode one host mouse event through the mouse encoding owner.
    pub fn encodeMouse(buf: []u8, event: mouse.MouseEvent, tracking: mouse.MouseTrackingMode, protocol: mouse.MouseProtocol) []const u8 {
        return mouse_encode.encodeMouse(buf, event, tracking, protocol);
    }

    /// Parse a host key token through the token owner.
    pub fn parseKeyToken(name: []const u8) ?keymap.Key {
        return tokens.parseKeyToken(name);
    }

    /// Parse host modifier bits through the token owner.
    pub fn parseModifierBits(mods: i32) keymap.Modifier {
        return tokens.parseModifierBits(mods);
    }
};
