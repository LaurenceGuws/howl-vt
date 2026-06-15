const std = @import("std");
const ffi = @import("ffi");

const c = @cImport({
    @cInclude("howl_vt.h");
});

comptime {
    std.debug.assert(@sizeOf(ffi.FfiBytesResult) == @sizeOf(c.HowlVtBytesResult));
    std.debug.assert(@sizeOf(ffi.FfiFeedResult) == @sizeOf(c.HowlVtFeedResult));
    std.debug.assert(@sizeOf(ffi.FfiVisibleMetaResult) == @sizeOf(c.HowlVtVisibleMetaResult));
    std.debug.assert(@sizeOf(ffi.FfiRuntimeObligationResult) == @sizeOf(c.HowlVtRuntimeObligationResult));
    std.debug.assert(@sizeOf(ffi.FfiRuntimeProgressResult) == @sizeOf(c.HowlVtRuntimeProgressResult));
    std.debug.assert(@sizeOf(ffi.FfiSelectionResult) == @sizeOf(c.HowlVtSelectionResult));

    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.ok) == c.HOWL_VT_CALL_OK);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.missing_handle) == c.HOWL_VT_CALL_MISSING_HANDLE);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.invalid_argument) == c.HOWL_VT_CALL_INVALID_ARGUMENT);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.failed) == c.HOWL_VT_CALL_FAILED);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.short_buffer) == c.HOWL_VT_CALL_SHORT_BUFFER);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.limit_reached) == c.HOWL_VT_CALL_LIMIT_REACHED);

    std.debug.assert(c.HOWL_VT_INPUT_ENCODE_MAX_BYTES == 64);
    std.debug.assert(c.HOWL_VT_TITLE_MAX_BYTES == 1024);
    std.debug.assert(c.HOWL_VT_CURSOR_SHAPE_BLOCK == 0);
    std.debug.assert(c.HOWL_VT_CURSOR_SHAPE_UNDERLINE == 1);
    std.debug.assert(c.HOWL_VT_CURSOR_SHAPE_BEAM == 2);
    std.debug.assert(c.HOWL_VT_CURSOR_SHAPE_NONE == 3);
}

test "vt abi null handles report missing-handle contract" {
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalResize(null, 24, 80));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalSetCellPixelSize(null, 8, 16));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalAckSurface(null, 1));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalStartSelection(null, 0, 0));

    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalFeed(null, null, 0).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalCopyTitle(null, null, 0).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalQueryVisibleMeta(null, 0).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalQuerySelection(null).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalQueryRuntimeObligation(null, 0).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalProgressRuntime(null, 0).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalEncodeKey(null, c.HOWL_VT_KEY_ENTER, 0, null, 0).status);
}

test "vt abi invalid arguments report invalid-argument contract" {
    const handle = ffi.terminalInit(24, 80, 16);
    defer ffi.terminalDeinit(handle);
    try std.testing.expect(handle != null);

    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.terminalSetCellPixelSize(handle, 0, 16));
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.terminalSetCellPixelSize(handle, 8, 0));
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.terminalCopyTitle(handle, null, 1).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.terminalEncodeKey(handle, c.HOWL_VT_KEY_ENTER, 0, null, 1).status);
}

test "vt abi lifecycle and visible-meta contract are exported" {
    const handle = ffi.terminalInitWithOptions(24, 80, 16, .{ .default_cursor_style = .{ .shape = 2, .blink = 0 } });
    defer ffi.terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const meta = ffi.terminalQueryVisibleMeta(handle, 0);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, meta.status);
    try std.testing.expectEqual(@as(u16, 24), meta.meta.rows);
    try std.testing.expectEqual(@as(u16, 80), meta.meta.cols);
    try std.testing.expectEqual(@as(u64, 1), meta.meta.snapshot_seq);

    const obligation = ffi.terminalQueryRuntimeObligation(handle, 1234);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, obligation.status);
    try std.testing.expectEqual(@as(u8, 0), obligation.obligation.pending_now);
}

test "vt abi input encoding contract honors shipped max scratch bound" {
    const handle = ffi.terminalInit(24, 80, 16);
    defer ffi.terminalDeinit(handle);
    try std.testing.expect(handle != null);

    var out: [c.HOWL_VT_INPUT_ENCODE_MAX_BYTES]u8 = undefined;
    const encoded = ffi.terminalEncodeKey(handle, c.HOWL_VT_KEY_ENTER, c.HOWL_VT_MOD_SHIFT, &out, out.len);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, encoded.status);
    try std.testing.expect(encoded.written <= out.len);
    try std.testing.expectEqual(encoded.written, encoded.needed);
}
