const std = @import("std");
const locator = @import("../locator.zig");
const encoded_owner = @import("encoded.zig");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");

const LocatorNs = locator;

/// Caller-owned fixed storage for nonallocating input encodings.
pub const Scratch = struct {
    buf: [64]u8 = undefined,
};

/// Exact failures while constructing an encoded paste result.
pub const PasteError = error{ LengthOverflow, OutOfMemory };

/// Encode one typed key from explicit terminal keyboard mode values.
///
/// The returned bytes borrow `scratch` and remain valid until its next use.
pub fn encodeKey(
    scratch: *Scratch,
    key_value: keyboard.Key,
    mod: keyboard.Modifier,
    keyboard_action_mode: bool,
    application_cursor_keys: bool,
    application_keypad: bool,
    modify_other_keys: i8,
    format_other_keys: u16,
    kitty_keyboard_flags: u32,
    newline_mode: bool,
) []const u8 {
    if (keyboard_action_mode) {
        return scratch.buf[0..0];
    }
    const encoded = keyboard.encodeKey(
        scratch.buf[0..],
        key_value,
        mod,
        application_cursor_keys,
        application_keypad,
        modify_other_keys,
        format_other_keys,
        kitty_keyboard_flags,
    );
    std.debug.assert(encoded.len <= scratch.buf.len);
    if (newline_mode and key_value == .named and key_value.named == .enter and std.mem.eql(u8, encoded, "\r")) {
        scratch.buf[0] = '\r';
        scratch.buf[1] = '\n';
        return scratch.buf[0..2];
    }
    return encoded;
}

/// Encode one mouse event and update locator host consequences.
///
/// Locator reports may append to `pending_output`; terminal mouse protocol
/// bytes borrow `scratch` until its next use.
pub fn encodeMouse(
    scratch: *Scratch,
    locator_state: *LocatorNs.Locator,
    allocator: std.mem.Allocator,
    pending_output: *std.ArrayList(u8),
    tracking: mouse.MouseTrackingMode,
    protocol: mouse.MouseProtocol,
    event: mouse.MouseEvent,
) []const u8 {
    LocatorNs.handleMouseEvent(locator_state, allocator, pending_output, scratch.buf[0..], event);
    const encoded = mouse.encodeMouse(scratch.buf[0..], event, tracking, protocol);
    std.debug.assert(encoded.len <= scratch.buf.len);
    return encoded;
}

/// Encode focus-in bytes, borrowing `scratch`.
pub fn encodeFocusIn(scratch: *Scratch, focus_reporting: bool) []const u8 {
    return fixed(scratch, if (focus_reporting) "\x1b[I" else "");
}

/// Encode focus-out bytes, borrowing `scratch`.
pub fn encodeFocusOut(scratch: *Scratch, focus_reporting: bool) []const u8 {
    return fixed(scratch, if (focus_reporting) "\x1b[O" else "");
}

/// Encode borrowed paste text for the active bracketed-paste mode.
///
/// Plain paste returns a borrowed view of `text` without allocating. Bracketed
/// paste allocates one caller-owned result containing the fixed CSI 200/201
/// pair. Encoded-length overflow is distinct from allocator exhaustion. The
/// caller must call `Encoded.deinit` once for either successful result.
pub fn encodePaste(bracketed_paste: bool, allocator: std.mem.Allocator, text: []const u8) PasteError!encoded_owner.Encoded {
    const start = if (bracketed_paste) "\x1b[200~" else "";
    const end = if (bracketed_paste) "\x1b[201~" else "";
    if (start.len == 0 and end.len == 0) return .{ .bytes = text };

    const encoded_len = try bracketedPasteLength(text.len);
    const out = try allocator.alloc(u8, encoded_len);
    std.debug.assert(out.len == encoded_len);
    @memcpy(out[0..start.len], start);
    @memcpy(out[start.len .. start.len + text.len], text);
    @memcpy(out[start.len + text.len ..], end);
    return .{ .allocator = allocator, .bytes = out };
}

fn bracketedPasteLength(text_len: usize) error{LengthOverflow}!usize {
    const with_start = std.math.add(usize, "\x1b[200~".len, text_len) catch return error.LengthOverflow;
    return std.math.add(usize, with_start, "\x1b[201~".len) catch return error.LengthOverflow;
}

/// Encode the bracketed-paste start marker, borrowing `scratch`.
pub fn encodePasteStart(scratch: *Scratch, bracketed_paste: bool) []const u8 {
    return fixed(scratch, if (bracketed_paste) "\x1b[200~" else "");
}

/// Encode the bracketed-paste end marker, borrowing `scratch`.
pub fn encodePasteEnd(scratch: *Scratch, bracketed_paste: bool) []const u8 {
    return fixed(scratch, if (bracketed_paste) "\x1b[201~" else "");
}

fn fixed(scratch: *Scratch, encoded: []const u8) []const u8 {
    @memcpy(scratch.buf[0..encoded.len], encoded);
    std.debug.assert(encoded.len <= scratch.buf.len);
    return scratch.buf[0..encoded.len];
}

test "bracketed paste length reports arithmetic overflow" {
    try std.testing.expectEqual(@as(usize, 15), try bracketedPasteLength(3));
    try std.testing.expectError(error.LengthOverflow, bracketedPasteLength(std.math.maxInt(usize)));
}
