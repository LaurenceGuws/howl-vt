const std = @import("std");
const locator = @import("../locator.zig");
const encoded_owner = @import("encoded.zig");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");

const LocatorNs = locator;

pub const Scratch = struct {
    buf: [64]u8 = undefined,
};

pub fn encodeKey(vt: anytype, scratch: *Scratch, key_value: keyboard.Key, mod: keyboard.Modifier) []const u8 {
    if (vt.modes.keyboard_action_mode) {
        return scratch.buf[0..0];
    }
    const encoded = keyboard.encodeKey(
        scratch.buf[0..],
        key_value,
        mod,
        vt.modes.application_cursor_keys,
        vt.modes.application_keypad,
        vt.modes.modify_other_keys,
        vt.modes.key_format[4],
        kittyKeyboardFlags(vt),
    );
    std.debug.assert(encoded.len <= scratch.buf.len);
    if (vt.modes.newline_mode and key_value == .named and key_value.named == .enter and std.mem.eql(u8, encoded, "\r")) {
        scratch.buf[0] = '\r';
        scratch.buf[1] = '\n';
        return scratch.buf[0..2];
    }
    return encoded;
}

pub fn encodeMouse(vt: anytype, scratch: *Scratch, event: mouse.MouseEvent) []const u8 {
    LocatorNs.handleMouseEvent(&vt.host.locator, vt.allocator, &vt.host.pending_output, scratch.buf[0..], event);
    const encoded = mouse.encodeMouse(scratch.buf[0..], event, vt.modes.mouse_tracking, vt.modes.mouse_protocol);
    std.debug.assert(encoded.len <= scratch.buf.len);
    return encoded;
}

pub fn encodeFocusIn(vt: anytype, scratch: *Scratch) []const u8 {
    return fixed(scratch, if (vt.modes.focus_reporting) "\x1b[I" else "");
}

pub fn encodeFocusOut(vt: anytype, scratch: *Scratch) []const u8 {
    return fixed(scratch, if (vt.modes.focus_reporting) "\x1b[O" else "");
}

pub fn encodePaste(vt: anytype, allocator: std.mem.Allocator, text: []const u8) !encoded_owner.Encoded {
    const start = if (vt.modes.bracketed_paste) "\x1b[200~" else "";
    const end = if (vt.modes.bracketed_paste) "\x1b[201~" else "";
    if (start.len == 0 and end.len == 0) return .{ .bytes = text };

    const out = try allocator.alloc(u8, start.len + text.len + end.len);
    std.debug.assert(out.len == start.len + text.len + end.len);
    @memcpy(out[0..start.len], start);
    @memcpy(out[start.len .. start.len + text.len], text);
    @memcpy(out[start.len + text.len ..], end);
    return .{ .allocator = allocator, .bytes = out };
}

pub fn encodePasteStart(vt: anytype, scratch: *Scratch) []const u8 {
    return fixed(scratch, if (vt.modes.bracketed_paste) "\x1b[200~" else "");
}

pub fn encodePasteEnd(vt: anytype, scratch: *Scratch) []const u8 {
    return fixed(scratch, if (vt.modes.bracketed_paste) "\x1b[201~" else "");
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

pub fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

fn fixed(scratch: *Scratch, encoded: []const u8) []const u8 {
    @memcpy(scratch.buf[0..encoded.len], encoded);
    std.debug.assert(encoded.len <= scratch.buf.len);
    return scratch.buf[0..encoded.len];
}
