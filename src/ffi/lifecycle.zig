const std = @import("std");
const screen = @import("../screen.zig");
const terminal = @import("../terminal.zig");
const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub const FfiFeedResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    state_changed: u8 = 0,
    title_changed: u8 = 0,
    reserved0: u16 = 0,
};

pub const FfiCursorStyle = extern struct {
    shape: u8 = 0,
    blink: u8 = 1,
};

pub const FfiTerminalInitOptions = extern struct {
    default_cursor_style: FfiCursorStyle = .{},
};

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

fn cursorStyleIn(value: FfiCursorStyle) ?screen.Screen.CursorStyle {
    const shape: screen.Screen.CursorShape = switch (value.shape) {
        0 => .block,
        1 => .underline,
        2 => .bar,
        3 => .none,
        else => return null,
    };
    return .{ .shape = shape, .blink = value.blink != 0 };
}

pub fn terminalInit(rows: u16, cols: u16, history_capacity: u16) callconv(.c) handle.VtHandle {
    return terminalInitWithOptions(rows, cols, history_capacity, .{});
}

pub fn terminalInitWithOptions(rows: u16, cols: u16, history_capacity: u16, options: FfiTerminalInitOptions) callconv(.c) handle.VtHandle {
    const cursor_style = cursorStyleIn(options.default_cursor_style) orelse return null;
    const owned = std.heap.c_allocator.create(terminal.Terminal) catch return null;
    owned.* = terminal.Terminal.initWithCellsHistoryAndOptions(std.heap.c_allocator, rows, cols, history_capacity, .{
        .default_cursor_style = cursor_style,
    }) catch {
        std.heap.c_allocator.destroy(owned);
        return null;
    };
    return @ptrCast(owned);
}

pub fn terminalDeinit(vt_handle: handle.VtHandle) callconv(.c) void {
    const owned = handle.vtFromHandle(vt_handle) orelse return;
    owned.deinit();
    std.heap.c_allocator.destroy(owned);
}

pub fn terminalFeed(vt_handle: handle.VtHandle, ptr: ?[*]const u8, len: usize) callconv(.c) FfiFeedResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const source_bytes = bytes.bytesIn(ptr, len) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const summary = owned.feed(source_bytes) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.ConsequenceLimit, error.ParsedEventLimit, error.StringControlLimit => status.HowlVtCallStatus.limit_reached,
            error.OutOfMemory => status.HowlVtCallStatus.failed,
        }) };
    };
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .state_changed = boolByte(summary.state_changed),
        .title_changed = boolByte(summary.title_changed),
    };
}

pub fn terminalCopyTitle(vt_handle: handle.VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    return bytes.copyBytes(out, owned.host.current_title orelse &.{});
}

pub fn terminalResize(vt_handle: handle.VtHandle, rows: u16, cols: u16) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.resize(rows, cols) catch return @intFromEnum(status.HowlVtCallStatus.failed);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn terminalSetCellPixelSize(vt_handle: handle.VtHandle, width: u32, height: u32) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    if (width == 0 or height == 0) return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    owned.setCellPixelSize(width, height);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

test "vt ffi init options seed default cursor style and blink" {
    const vt_handle = terminalInitWithOptions(2, 4, 8, .{
        .default_cursor_style = .{ .shape = 2, .blink = 0 },
    });
    defer terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const owned = handle.vtFromHandle(vt_handle).?;
    try std.testing.expectEqual(screen.Screen.CursorShape.bar, owned.screen_state.activeConst().cursor.effective_shape);
    try std.testing.expectEqual(false, owned.screen_state.activeConst().cursor.blink_intent);
    try std.testing.expectEqual(screen.Screen.CursorShape.bar, owned.screen_state.alternate.cursor.effective_shape);
    try std.testing.expectEqual(false, owned.screen_state.alternate.cursor.blink_intent);

    const override = terminalFeed(vt_handle, "\x1b[3 q".ptr, 6);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), override.status);

    try std.testing.expectEqual(screen.Screen.CursorShape.underline, owned.screen_state.activeConst().cursor.effective_shape);
    try std.testing.expectEqual(true, owned.screen_state.activeConst().cursor.blink_intent);

    const blinking_block = terminalFeed(vt_handle, "\x1b[1 q".ptr, 6);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), blinking_block.status);

    try std.testing.expectEqual(screen.Screen.CursorShape.block, owned.screen_state.activeConst().cursor.effective_shape);
    try std.testing.expectEqual(true, owned.screen_state.activeConst().cursor.blink_intent);

    const reset = terminalFeed(vt_handle, "\x1bc".ptr, 2);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), reset.status);

    try std.testing.expectEqual(screen.Screen.CursorShape.bar, owned.screen_state.activeConst().cursor.effective_shape);
    try std.testing.expectEqual(false, owned.screen_state.activeConst().cursor.blink_intent);
}

test "vt ffi set cell pixel size validates and applies" {
    const vt_handle = terminalInit(3, 16, 4);
    defer terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), terminalSetCellPixelSize(vt_handle, 0, 10));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), terminalSetCellPixelSize(vt_handle, 10, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalSetCellPixelSize(vt_handle, 11, 19));

    const owned = handle.vtFromHandle(vt_handle).?;
    try std.testing.expectEqual(@as(u32, 11), owned.screen_state.primary.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), owned.screen_state.primary.cellPixelSize().?.height);
    try std.testing.expectEqual(@as(u32, 11), owned.screen_state.alternate.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), owned.screen_state.alternate.cellPixelSize().?.height);
}

test "vt ffi feed reports and copies title" {
    const vt_handle = terminalInit(2, 4, 8);
    defer terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const seq = "\x1b]0;My Title\x07";
    const fed = terminalFeed(vt_handle, seq.ptr, seq.len);
    try std.testing.expectEqual(@as(i32, 0), fed.status);
    try std.testing.expectEqual(@as(u8, 1), fed.title_changed);

    var title_buf: [32]u8 = undefined;
    const title = terminalCopyTitle(vt_handle, title_buf[0..].ptr, title_buf.len);
    try std.testing.expectEqual(@as(i32, 0), title.status);
    try std.testing.expectEqualStrings("My Title", title_buf[0..@intCast(title.written)]);
}
