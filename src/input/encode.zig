const std = @import("std");
const locator = @import("../control/locator.zig");
const input = @import("../input.zig");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");

const LocatorNs = locator;

pub fn key(vt: anytype, key_value: input.Key, mod: input.Modifier) []const u8 {
    if (vt.modes.keyboard_action_mode) {
        return vt.encode.buf[0..0];
    }
    const encoded = keyboard.encodeKey(
        vt.encode.buf[0..],
        key_value,
        mod,
        vt.modes.application_cursor_keys,
        vt.modes.application_keypad,
        vt.modes.modify_other_keys,
        vt.modes.key_format[4],
        kittyKeyboardFlags(vt),
    );
    std.debug.assert(encoded.len <= vt.encode.buf.len);
    if (vt.modes.newline_mode and key_value == input.key_enter and std.mem.eql(u8, encoded, "\r")) {
        vt.encode.buf[0] = '\r';
        vt.encode.buf[1] = '\n';
        return vt.encode.buf[0..2];
    }
    return encoded;
}

pub fn mouseEvent(vt: anytype, event: input.MouseEvent) []const u8 {
    LocatorNs.handleMouseEvent(&vt.host.locator, vt.allocator, &vt.host.pending_output, vt.encode.buf[0..], event);
    const encoded = mouse.encodeMouse(vt.encode.buf[0..], event, vt.modes.mouse_tracking, vt.modes.mouse_protocol);
    std.debug.assert(encoded.len <= vt.encode.buf.len);
    return encoded;
}

pub fn focusIn(vt: anytype) []const u8 {
    return fixed(vt, if (vt.modes.focus_reporting) "\x1b[I" else "");
}

pub fn focusOut(vt: anytype) []const u8 {
    return fixed(vt, if (vt.modes.focus_reporting) "\x1b[O" else "");
}

pub fn paste(vt: anytype, allocator: std.mem.Allocator, text: []const u8) !input.Encoded {
    const start = pasteStart(vt);
    const end = pasteEnd(vt);
    if (start.len == 0 and end.len == 0) return .{ .bytes = text };

    const out = try allocator.alloc(u8, start.len + text.len + end.len);
    std.debug.assert(out.len == start.len + text.len + end.len);
    @memcpy(out[0..start.len], start);
    @memcpy(out[start.len .. start.len + text.len], text);
    @memcpy(out[start.len + text.len ..], end);
    return .{ .allocator = allocator, .bytes = out };
}

pub fn pasteStart(vt: anytype) []const u8 {
    return fixed(vt, if (vt.modes.bracketed_paste) "\x1b[200~" else "");
}

pub fn pasteEnd(vt: anytype) []const u8 {
    return fixed(vt, if (vt.modes.bracketed_paste) "\x1b[201~" else "");
}

pub fn kittyKeyboardFlags(vt: anytype) u32 {
    return vt.kitty.activeScreenConst(vt.screen_state.alt_active).keyboard.flags;
}

pub fn keyFormatOption(vt: anytype, resource: u8) u16 {
    return if (isKeyFormatResource(resource)) vt.modes.key_format[resource] else 0;
}

pub fn isApplicationKeypad(vt: anytype) bool {
    return vt.modes.application_keypad;
}

pub fn modifyOtherKeys(vt: anytype) i8 {
    return vt.modes.modify_other_keys;
}

fn fixed(vt: anytype, encoded: []const u8) []const u8 {
    @memcpy(vt.encode.buf[0..encoded.len], encoded);
    std.debug.assert(encoded.len <= vt.encode.buf.len);
    return vt.encode.buf[0..encoded.len];
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}
