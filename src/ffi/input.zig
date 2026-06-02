const std = @import("std");
const input_encode = @import("../input/encode.zig");
const input_keyboard = @import("../input/keyboard.zig");
const input_mouse = @import("../input/mouse.zig");
const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

fn mouseKindIn(kind: u8) ?input_mouse.MouseEventKind {
    return switch (kind) {
        @intFromEnum(input_mouse.mouse_press) => .press,
        @intFromEnum(input_mouse.mouse_release) => .release,
        @intFromEnum(input_mouse.mouse_move) => .move,
        @intFromEnum(input_mouse.mouse_wheel) => .wheel,
        else => null,
    };
}

fn mouseButtonIn(button: u8) ?input_mouse.MouseButton {
    return switch (button) {
        @intFromEnum(input_mouse.mouse_button_none) => .none,
        @intFromEnum(input_mouse.mouse_button_left) => .left,
        @intFromEnum(input_mouse.mouse_button_middle) => .middle,
        @intFromEnum(input_mouse.mouse_button_right) => .right,
        @intFromEnum(input_mouse.mouse_button_wheel_up) => .wheel_up,
        @intFromEnum(input_mouse.mouse_button_wheel_down) => .wheel_down,
        else => null,
    };
}

pub fn terminalEncodeKey(vt_handle: handle.VtHandle, key: u32, mods: u8, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    var scratch: input_encode.Scratch = .{};
    return bytes.copyBytes(out, input_encode.encodeKey(owned, &scratch, key, mods));
}

pub fn terminalEncodeFocus(vt_handle: handle.VtHandle, focused: u8, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    var scratch: input_encode.Scratch = .{};
    const encoded = if (focused != 0) input_encode.encodeFocusIn(owned, &scratch) else input_encode.encodeFocusOut(owned, &scratch);
    return bytes.copyBytes(out, encoded);
}

pub fn terminalEncodePasteStart(vt_handle: handle.VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    var scratch: input_encode.Scratch = .{};
    return bytes.copyBytes(out, input_encode.encodePasteStart(owned, &scratch));
}

pub fn terminalEncodePasteEnd(vt_handle: handle.VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    var scratch: input_encode.Scratch = .{};
    return bytes.copyBytes(out, input_encode.encodePasteEnd(owned, &scratch));
}

pub fn terminalEncodeMouse(
    vt_handle: handle.VtHandle,
    kind: u8,
    button: u8,
    row: i32,
    col: u16,
    pixel_x_valid: u8,
    pixel_x: u32,
    pixel_y_valid: u8,
    pixel_y: u32,
    mods: u8,
    buttons_down: u8,
    ptr: ?[*]u8,
    cap: usize,
) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const event_kind = mouseKindIn(kind) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const event_button = mouseButtonIn(button) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const event = input_mouse.MouseEvent{
        .kind = event_kind,
        .button = event_button,
        .row = row,
        .col = col,
        .pixel_x = if (pixel_x_valid != 0) pixel_x else null,
        .pixel_y = if (pixel_y_valid != 0) pixel_y else null,
        .mod = mods,
        .buttons_down = buttons_down,
    };
    var scratch: input_encode.Scratch = .{};
    return bytes.copyBytes(out, input_encode.encodeMouse(owned, &scratch, event));
}

pub fn terminalEncodePaste(vt_handle: handle.VtHandle, text_ptr: ?[*]const u8, text_len: usize, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const text = bytes.bytesIn(text_ptr, text_len) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    var scratch: input_encode.Scratch = .{};
    const start = input_encode.encodePasteStart(owned, &scratch);
    const end = input_encode.encodePasteEnd(owned, &scratch);
    const needed = start.len + text.len + end.len;
    if (out.len < needed) {
        return .{
            .status = @intFromEnum(status.HowlVtCallStatus.short_buffer),
            .needed = needed,
        };
    }
    if (start.len != 0) @memcpy(out[0..start.len], start);
    if (text.len != 0) @memcpy(out[start.len .. start.len + text.len], text);
    if (end.len != 0) @memcpy(out[start.len + text.len .. needed], end);
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .written = needed,
        .needed = needed,
    };
}

test "vt ffi encode key emits enter" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 8);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    var key_buf: [16]u8 = undefined;
    const key = terminalEncodeKey(vt_handle, input_keyboard.key_enter, input_keyboard.mod_none, key_buf[0..].ptr, key_buf.len);
    try std.testing.expectEqual(@as(i32, 0), key.status);
    try std.testing.expectEqualStrings("\r", key_buf[0..@intCast(key.written)]);
}
