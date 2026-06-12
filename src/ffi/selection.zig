const std = @import("std");
const terminal_selection = @import("../selection/state.zig");
const selection_projection = @import("../selection/projection.zig");
const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub const FfiSelectionPos = extern struct {
    row: i32 = 0,
    col: u16 = 0,
    reserved0: u16 = 0,
};

pub const FfiSelection = extern struct {
    active: u8 = 0,
    selecting: u8 = 0,
    reserved0: u16 = 0,
    start: FfiSelectionPos = .{},
    end: FfiSelectionPos = .{},
};

pub const FfiSelectionResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    selection: FfiSelection = .{},
};

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

pub fn selectionOut(value: ?terminal_selection.TerminalSelection) FfiSelection {
    const selected = value orelse return .{};
    return .{
        .active = boolByte(selected.active),
        .selecting = boolByte(selected.selecting),
        .start = .{ .row = selected.start.row, .col = selected.start.col },
        .end = .{ .row = selected.end.row, .col = selected.end.col },
    };
}

fn selectionResult(value: ?terminal_selection.TerminalSelection) FfiSelectionResult {
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .selection = selectionOut(value),
    };
}

pub fn terminalQuerySelection(vt_handle: handle.VtHandle) callconv(.c) FfiSelectionResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    return selectionResult(owned.selectionState());
}

pub fn terminalStartSelection(vt_handle: handle.VtHandle, row: i32, col: u16) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.startSelection(row, col);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn terminalUpdateSelection(vt_handle: handle.VtHandle, row: i32, col: u16) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.updateSelection(row, col);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn terminalFinishSelection(vt_handle: handle.VtHandle) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.finishSelection();
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn terminalClearSelection(vt_handle: handle.VtHandle) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.clearSelection();
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn terminalCopySelection(vt_handle: handle.VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const text = selection_projection.copyText(owned.allocator, &owned.screen_state, owned.selectionState()) catch return .{ .status = @intFromEnum(status.HowlVtCallStatus.failed) };
    defer if (text.len != 0) owned.allocator.free(text);
    return bytes.copyBytes(out, text);
}

test "vt ffi selection query and copy stay history-aware" {
    const lifecycle = @import("lifecycle.zig");
    const surface = @import("surface.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 8);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const fed = lifecycle.terminalFeed(vt_handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), fed.status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalStartSelection(vt_handle, 0, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalUpdateSelection(vt_handle, 1, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalFinishSelection(vt_handle));

    const selection_result = terminalQuerySelection(vt_handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection_result.status);
    try std.testing.expectEqual(@as(u8, 1), selection_result.selection.active);
    try std.testing.expectEqual(@as(i32, 0), selection_result.selection.start.row);
    try std.testing.expectEqual(@as(i32, 1), selection_result.selection.end.row);

    var text: [32]u8 = undefined;
    const copied = terminalCopySelection(vt_handle, text[0..].ptr, text.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), copied.status);
    try std.testing.expectEqualStrings("aa\nbb", text[0..@intCast(copied.written)]);

    var cells: [8]surface.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    const surface_result = surface.terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), surface_result.status);
    try std.testing.expectEqual(@as(u8, 1), surface_result.source.selection.active);
    try std.testing.expectEqual(@as(i32, 0), surface_result.source.selection.start.row);
    try std.testing.expectEqual(@as(i32, 1), surface_result.source.selection.end.row);
}

test "vt ffi alternate selection does not read primary history" {
    const lifecycle = @import("lifecycle.zig");
    const surface = @import("surface.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 8);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const primary_feed = lifecycle.terminalFeed(vt_handle, "aa\r\nbb\r\ncc".ptr, 10);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), primary_feed.status);

    const enter_alt = lifecycle.terminalFeed(vt_handle, "\x1b[?1049hzz".ptr, 10);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), enter_alt.status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalStartSelection(vt_handle, 0, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalUpdateSelection(vt_handle, 0, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), terminalFinishSelection(vt_handle));

    var text: [32]u8 = undefined;
    const copied = terminalCopySelection(vt_handle, text[0..].ptr, text.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), copied.status);
    try std.testing.expectEqualStrings("zz", text[0..@intCast(copied.written)]);

    var cells: [8]surface.FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    const surface_result = surface.terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), surface_result.status);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[1].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[2].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[3].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[4].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[5].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[6].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[7].attrs.selected);
}
