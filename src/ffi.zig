//! Responsibility: implement the howl-vt native ABI surface.
//! Ownership: VT terminal handles, host-facing runtime state, visible cells, and input vocabulary.
//! Reason: keep hosts on a C ABI seam instead of Zig owner imports.

const std = @import("std");
const grid = @import("grid.zig");
const input = @import("input.zig");
const terminal = @import("terminal.zig");

pub const VtHandle = usize;

pub const HowlVtCallStatus = enum(c_int) {
    ok = 0,
    missing_handle = -1,
    invalid_argument = -2,
    failed = -3,
    short_buffer = -4,
};

pub const FfiColor = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 0,
};

pub const FfiCell = extern struct {
    codepoint: u32 = 0,
    fg: FfiColor = .{},
    bg: FfiColor = .{},
    underline_color: FfiColor = .{},
    link_id: u32 = 0,
    continuation: u8 = 0,
    bold: u8 = 0,
    blink: u8 = 0,
    blink_fast: u8 = 0,
    reverse: u8 = 0,
    underline: u8 = 0,
    underline_style: u8 = 0,
    reserved0: u8 = 0,
};

pub const FfiBytesResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    written: u64 = 0,
    needed: u64 = 0,
};

pub const FfiApplyResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    applied: u64 = 0,
    remaining_events: u64 = 0,
    state_changed: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    title_written: u64 = 0,
    title_needed: u64 = 0,
};

pub const FfiVisibleView = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    rows: u16 = 0,
    cols: u16 = 0,
    cursor_row: u16 = 0,
    cursor_col: u16 = 0,
    cursor_visible: u8 = 0,
    cursor_shape: u8 = 0,
    is_alternate_screen: u8 = 0,
    reserved0: u8 = 0,
    history_count: u64 = 0,
    scrollback_offset: u64 = 0,
    start: u64 = 0,
    cell_count: u64 = 0,
};

const key_min: u32 = input.key_enter;
const key_max: u32 = input.key_f12;
const mod_mask: u32 = input.mod_shift | input.mod_alt | input.mod_ctrl;

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

fn vtFromHandle(handle: VtHandle) ?*terminal.Terminal {
    if (handle == 0) return null;
    return @ptrFromInt(handle);
}

fn bytesIn(ptr: ?[*]const u8, len: usize) ?[]const u8 {
    if (ptr == null) {
        if (len != 0) return null;
        return &.{};
    }
    return ptr.?[0..len];
}

fn bytesOut(ptr: ?[*]u8, len: usize) ?[]u8 {
    if (ptr == null) {
        if (len != 0) return null;
        return &.{};
    }
    return ptr.?[0..len];
}

fn colorOut(value: grid.Grid.Color) FfiColor {
    return .{ .r = value.r, .g = value.g, .b = value.b, .a = value.a };
}

fn cellOut(value: grid.Grid.Cell) FfiCell {
    return .{
        .codepoint = value.codepoint,
        .fg = colorOut(value.attrs.fg),
        .bg = colorOut(value.attrs.bg),
        .underline_color = colorOut(value.attrs.underline_color),
        .link_id = value.attrs.link_id,
        .continuation = boolByte(grid.Grid.isCellContinuation(value)),
        .bold = boolByte(value.attrs.bold),
        .blink = boolByte(value.attrs.blink),
        .blink_fast = boolByte(value.attrs.blink_fast),
        .reverse = boolByte(value.attrs.reverse),
        .underline = boolByte(value.attrs.underline),
        .underline_style = @intFromEnum(value.attrs.underline_style),
    };
}

fn cursorShapeByte(shape: grid.Grid.CursorShape) u8 {
    return @intFromEnum(shape);
}

fn mouseKindIn(kind: u8) ?input.MouseEventKind {
    return switch (kind) {
        @intFromEnum(input.mouse_press) => .press,
        @intFromEnum(input.mouse_release) => .release,
        @intFromEnum(input.mouse_move) => .move,
        @intFromEnum(input.mouse_wheel) => .wheel,
        else => null,
    };
}

fn mouseButtonIn(button: u8) ?input.MouseButton {
    return switch (button) {
        @intFromEnum(input.mouse_button_none) => .none,
        @intFromEnum(input.mouse_button_left) => .left,
        @intFromEnum(input.mouse_button_middle) => .middle,
        @intFromEnum(input.mouse_button_right) => .right,
        @intFromEnum(input.mouse_button_wheel_up) => .wheel_up,
        @intFromEnum(input.mouse_button_wheel_down) => .wheel_down,
        else => null,
    };
}

fn copyBytes(out: []u8, bytes: []const u8) FfiBytesResult {
    if (out.len < bytes.len) {
        return .{
            .status = @intFromEnum(HowlVtCallStatus.short_buffer),
            .needed = bytes.len,
        };
    }
    if (bytes.len != 0) @memcpy(out[0..bytes.len], bytes);
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .written = bytes.len,
        .needed = bytes.len,
    };
}

fn decodeClipboardBytes(raw: []const u8, out: []u8) FfiBytesResult {
    const sep = std.mem.indexOfScalar(u8, raw, ';') orelse return .{ .status = @intFromEnum(HowlVtCallStatus.failed) };
    const data = raw[sep + 1 ..];
    if (std.mem.eql(u8, data, "?")) return .{ .status = @intFromEnum(HowlVtCallStatus.failed) };
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(data) catch return .{ .status = @intFromEnum(HowlVtCallStatus.failed) };
    if (out.len < decoded_len) {
        return .{
            .status = @intFromEnum(HowlVtCallStatus.short_buffer),
            .needed = decoded_len,
        };
    }
    std.base64.standard.Decoder.decode(out[0..decoded_len], data) catch return .{ .status = @intFromEnum(HowlVtCallStatus.failed) };
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .written = decoded_len,
        .needed = decoded_len,
    };
}

pub fn modIsValid(mods: u32) callconv(.c) u8 {
    return if ((mods & ~mod_mask) == 0) 1 else 0;
}

pub fn modNone() callconv(.c) u32 {
    return input.mod_none;
}

pub fn modShift() callconv(.c) u32 {
    return input.mod_shift;
}

pub fn modAlt() callconv(.c) u32 {
    return input.mod_alt;
}

pub fn modCtrl() callconv(.c) u32 {
    return input.mod_ctrl;
}

pub fn keyEnter() callconv(.c) u32 {
    return input.key_enter;
}

pub fn keyTab() callconv(.c) u32 {
    return input.key_tab;
}

pub fn keyBackspace() callconv(.c) u32 {
    return input.key_backspace;
}

pub fn keyEscape() callconv(.c) u32 {
    return input.key_escape;
}

pub fn keyUp() callconv(.c) u32 {
    return input.key_up;
}

pub fn keyDown() callconv(.c) u32 {
    return input.key_down;
}

pub fn keyLeft() callconv(.c) u32 {
    return input.key_left;
}

pub fn keyRight() callconv(.c) u32 {
    return input.key_right;
}

pub fn keyInsert() callconv(.c) u32 {
    return input.key_insert;
}

pub fn keyDelete() callconv(.c) u32 {
    return input.key_delete;
}

pub fn keyHome() callconv(.c) u32 {
    return input.key_home;
}

pub fn keyEnd() callconv(.c) u32 {
    return input.key_end;
}

pub fn keyPageup() callconv(.c) u32 {
    return input.key_pageup;
}

pub fn keyPagedown() callconv(.c) u32 {
    return input.key_pagedown;
}

pub fn keyF1() callconv(.c) u32 {
    return input.key_f1;
}

pub fn keyF2() callconv(.c) u32 {
    return input.key_f2;
}

pub fn keyF3() callconv(.c) u32 {
    return input.key_f3;
}

pub fn keyF4() callconv(.c) u32 {
    return input.key_f4;
}

pub fn keyF5() callconv(.c) u32 {
    return input.key_f5;
}

pub fn keyF6() callconv(.c) u32 {
    return input.key_f6;
}

pub fn keyF7() callconv(.c) u32 {
    return input.key_f7;
}

pub fn keyF8() callconv(.c) u32 {
    return input.key_f8;
}

pub fn keyF9() callconv(.c) u32 {
    return input.key_f9;
}

pub fn keyF10() callconv(.c) u32 {
    return input.key_f10;
}

pub fn keyF11() callconv(.c) u32 {
    return input.key_f11;
}

pub fn keyF12() callconv(.c) u32 {
    return input.key_f12;
}

pub fn keyIsValid(key: u32) callconv(.c) u8 {
    if (key < key_min) return 0;
    if (key > key_max) return 0;
    return 1;
}

pub fn mouseButtonNone() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_none);
}

pub fn mouseButtonLeft() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_left);
}

pub fn mouseButtonMiddle() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_middle);
}

pub fn mouseButtonRight() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_right);
}

pub fn mouseButtonWheelUp() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_wheel_up);
}

pub fn mouseButtonWheelDown() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_wheel_down);
}

pub fn mousePress() callconv(.c) u8 {
    return @intFromEnum(input.mouse_press);
}

pub fn mouseRelease() callconv(.c) u8 {
    return @intFromEnum(input.mouse_release);
}

pub fn mouseMove() callconv(.c) u8 {
    return @intFromEnum(input.mouse_move);
}

pub fn mouseWheel() callconv(.c) u8 {
    return @intFromEnum(input.mouse_wheel);
}

pub fn mouseButtonIsValid(button: u8) callconv(.c) u8 {
    return switch (button) {
        @intFromEnum(input.mouse_button_none),
        @intFromEnum(input.mouse_button_left),
        @intFromEnum(input.mouse_button_middle),
        @intFromEnum(input.mouse_button_right),
        @intFromEnum(input.mouse_button_wheel_up),
        @intFromEnum(input.mouse_button_wheel_down),
        => 1,
        else => 0,
    };
}

pub fn mouseEventKindIsValid(kind: u8) callconv(.c) u8 {
    return switch (kind) {
        @intFromEnum(input.mouse_press),
        @intFromEnum(input.mouse_release),
        @intFromEnum(input.mouse_move),
        @intFromEnum(input.mouse_wheel),
        => 1,
        else => 0,
    };
}

pub fn terminalInit(rows: u16, cols: u16, history_capacity: u16) callconv(.c) VtHandle {
    const owned = std.heap.c_allocator.create(terminal.Terminal) catch return 0;
    owned.* = terminal.Terminal.initWithCellsAndHistory(std.heap.c_allocator, rows, cols, history_capacity) catch {
        std.heap.c_allocator.destroy(owned);
        return 0;
    };
    return @intFromPtr(owned);
}

pub fn terminalDeinit(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    owned.deinit();
    std.heap.c_allocator.destroy(owned);
}

pub fn terminalFeed(handle: VtHandle, ptr: ?[*]const u8, len: usize) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    const bytes = bytesIn(ptr, len) orelse return @intFromEnum(HowlVtCallStatus.invalid_argument);
    owned.feedSlice(bytes);
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalQueuedEventCount(handle: VtHandle) callconv(.c) u64 {
    const owned = vtFromHandle(handle) orelse return 0;
    return owned.queuedEventCount();
}

pub fn terminalApply(handle: VtHandle, max_events: usize, title_ptr: ?[*]u8, title_cap: usize) callconv(.c) FfiApplyResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const title_out = bytesOut(title_ptr, title_cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const result = owned.applyLimit(max_events);
    const remaining = owned.queuedEventCount();
    if (result.latest_title) |title| {
        if (title_out.len < title.len) {
            return .{
                .status = @intFromEnum(HowlVtCallStatus.short_buffer),
                .applied = result.applied,
                .remaining_events = remaining,
                .state_changed = boolByte(result.applied != 0),
                .title_needed = title.len,
            };
        }
        if (title.len != 0) @memcpy(title_out[0..title.len], title);
        return .{
            .status = @intFromEnum(HowlVtCallStatus.ok),
            .applied = result.applied,
            .remaining_events = remaining,
            .state_changed = boolByte(result.applied != 0),
            .title_written = title.len,
            .title_needed = title.len,
        };
    }
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .applied = result.applied,
        .remaining_events = remaining,
        .state_changed = boolByte(result.applied != 0),
    };
}

pub fn terminalResize(handle: VtHandle, rows: u16, cols: u16) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.resize(rows, cols) catch return @intFromEnum(HowlVtCallStatus.failed);
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalHistoryCount(handle: VtHandle) callconv(.c) u64 {
    const owned = vtFromHandle(handle) orelse return 0;
    return owned.historyCount();
}

pub fn terminalIsAlternateScreen(handle: VtHandle) callconv(.c) u8 {
    const owned = vtFromHandle(handle) orelse return 0;
    return boolByte(owned.isAlternateScreen());
}

pub fn terminalClearDirtyRows(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    owned.clearDirtyRows();
}

pub fn terminalCopyVisible(handle: VtHandle, scrollback_offset: usize, cells_ptr: ?[*]FfiCell, cells_cap: usize) callconv(.c) FfiVisibleView {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const view = owned.visibleView(.{ .scrollback_offset = scrollback_offset });
    const cell_count = @as(usize, view.rows) * @as(usize, view.cols);
    if (cells_cap < cell_count) {
        return .{
            .status = @intFromEnum(HowlVtCallStatus.short_buffer),
            .rows = view.rows,
            .cols = view.cols,
            .cursor_row = view.cursor_row,
            .cursor_col = view.cursor_col,
            .cursor_visible = boolByte(view.cursor_visible),
            .cursor_shape = cursorShapeByte(view.cursor_shape),
            .is_alternate_screen = boolByte(view.is_alternate_screen),
            .history_count = view.history_count,
            .scrollback_offset = view.scrollback_offset,
            .start = view.start,
            .cell_count = cell_count,
        };
    }
    const cells_out = if (cells_ptr) |ptr| ptr[0..cells_cap] else return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            const idx = @as(usize, row) * @as(usize, view.cols) + @as(usize, col);
            cells_out[idx] = cellOut(view.cellInfoAt(row, col));
        }
    }
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .rows = view.rows,
        .cols = view.cols,
        .cursor_row = view.cursor_row,
        .cursor_col = view.cursor_col,
        .cursor_visible = boolByte(view.cursor_visible),
        .cursor_shape = cursorShapeByte(view.cursor_shape),
        .is_alternate_screen = boolByte(view.is_alternate_screen),
        .history_count = view.history_count,
        .scrollback_offset = view.scrollback_offset,
        .start = view.start,
        .cell_count = cell_count,
    };
}

pub fn terminalCopyPendingOutput(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return copyBytes(out, owned.pendingOutput());
}

pub fn terminalClearPendingOutput(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    owned.clearPendingOutput();
}

pub fn terminalDrainPendingClipboard(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const raw = owned.pendingClipboardSet() orelse return .{ .status = @intFromEnum(HowlVtCallStatus.ok) };
    const result = decodeClipboardBytes(raw, out);
    if (result.status == @intFromEnum(HowlVtCallStatus.ok)) owned.clearPendingClipboardSet();
    return result;
}

pub fn terminalEncodeKey(handle: VtHandle, key: u32, mods: u8, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return copyBytes(out, owned.encodeKey(key, mods));
}

pub fn terminalEncodeFocus(handle: VtHandle, focused: u8, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const bytes = if (focused != 0) owned.encodeFocusIn() else owned.encodeFocusOut();
    return copyBytes(out, bytes);
}

pub fn terminalEncodeMouse(
    handle: VtHandle,
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
) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const event_kind = mouseKindIn(kind) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const event_button = mouseButtonIn(button) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const event = input.MouseEvent{
        .kind = event_kind,
        .button = event_button,
        .row = row,
        .col = col,
        .pixel_x = if (pixel_x_valid != 0) pixel_x else null,
        .pixel_y = if (pixel_y_valid != 0) pixel_y else null,
        .mod = mods,
        .buttons_down = buttons_down,
    };
    return copyBytes(out, owned.encodeMouse(event));
}

pub fn terminalEncodePaste(handle: VtHandle, text_ptr: ?[*]const u8, text_len: usize, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const text = bytesIn(text_ptr, text_len) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const start = owned.encodePasteStart();
    const end = owned.encodePasteEnd();
    const needed = start.len + text.len + end.len;
    if (out.len < needed) {
        return .{
            .status = @intFromEnum(HowlVtCallStatus.short_buffer),
            .needed = needed,
        };
    }
    if (start.len != 0) @memcpy(out[0..start.len], start);
    if (text.len != 0) @memcpy(out[start.len .. start.len + text.len], text);
    if (end.len != 0) @memcpy(out[start.len + text.len .. needed], end);
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .written = needed,
        .needed = needed,
    };
}

test "vt ffi modifier and key vocabulary proves positive and negative space" {
    try std.testing.expectEqual(input.mod_none, modNone());
    try std.testing.expectEqual(input.mod_shift, modShift());
    try std.testing.expectEqual(input.mod_alt, modAlt());
    try std.testing.expectEqual(input.mod_ctrl, modCtrl());
    try std.testing.expectEqual(@as(u8, 1), modIsValid(input.mod_none));
    try std.testing.expectEqual(@as(u8, 1), modIsValid(input.mod_shift | input.mod_alt | input.mod_ctrl));
    try std.testing.expectEqual(@as(u8, 0), modIsValid(8));

    try std.testing.expectEqual(input.key_insert, keyInsert());
    try std.testing.expectEqual(input.key_delete, keyDelete());
    try std.testing.expectEqual(input.key_f12, keyF12());
    try std.testing.expectEqual(@as(u8, 1), keyIsValid(keyEnter()));
    try std.testing.expectEqual(@as(u8, 1), keyIsValid(keyF12()));
    try std.testing.expectEqual(@as(u8, 0), keyIsValid(0));
    try std.testing.expectEqual(@as(u8, 0), keyIsValid(keyF12() + 1));
}

test "vt ffi mouse vocabulary proves positive and negative space" {
    try std.testing.expectEqual(@intFromEnum(input.mouse_button_left), mouseButtonLeft());
    try std.testing.expectEqual(@intFromEnum(input.mouse_wheel), mouseWheel());
    try std.testing.expectEqual(@as(u8, 1), mouseButtonIsValid(mouseButtonWheelDown()));
    try std.testing.expectEqual(@as(u8, 0), mouseButtonIsValid(9));
    try std.testing.expectEqual(@as(u8, 1), mouseEventKindIsValid(mouseMove()));
    try std.testing.expectEqual(@as(u8, 0), mouseEventKindIsValid(9));
}

test "vt ffi runtime surface covers apply encode and visible copy" {
    const handle = terminalInit(2, 4, 8);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != 0);

    try std.testing.expectEqual(@as(i32, 0), terminalFeed(handle, "abc".ptr, 3));
    var title_buf: [32]u8 = undefined;
    const applied = terminalApply(handle, 16, title_buf[0..].ptr, title_buf.len);
    try std.testing.expectEqual(@as(i32, 0), applied.status);
    try std.testing.expect(applied.applied != 0);

    var key_buf: [16]u8 = undefined;
    const key = terminalEncodeKey(handle, input.key_enter, input.mod_none, key_buf[0..].ptr, key_buf.len);
    try std.testing.expectEqual(@as(i32, 0), key.status);
    try std.testing.expectEqualStrings("\r", key_buf[0..@intCast(key.written)]);

    var cells: [8]FfiCell = undefined;
    const view = terminalCopyVisible(handle, 0, cells[0..].ptr, cells.len);
    try std.testing.expectEqual(@as(i32, 0), view.status);
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 4), view.cols);
}
