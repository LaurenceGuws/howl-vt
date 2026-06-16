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
    std.debug.assert(@sizeOf(ffi.FfiRowSelection) == @sizeOf(c.HowlVtRenderStateRowSelection));
    std.debug.assert(@sizeOf(ffi.FfiRowHighlight) == @sizeOf(c.HowlVtRenderStateRowHighlight));
    std.debug.assert(@sizeOf(ffi.FfiColors) == @sizeOf(c.HowlVtRenderStateColors));

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

    std.debug.assert(@intFromEnum(ffi.FfiDirty.false) == c.HOWL_VT_RENDER_STATE_DIRTY_FALSE);
    std.debug.assert(@intFromEnum(ffi.FfiDirty.partial) == c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL);
    std.debug.assert(@intFromEnum(ffi.FfiDirty.full) == c.HOWL_VT_RENDER_STATE_DIRTY_FULL);

    std.debug.assert(@intFromEnum(ffi.FfiData.invalid) == c.HOWL_VT_RENDER_STATE_DATA_INVALID);
    std.debug.assert(@intFromEnum(ffi.FfiData.cols) == c.HOWL_VT_RENDER_STATE_DATA_COLS);
    std.debug.assert(@intFromEnum(ffi.FfiData.rows) == c.HOWL_VT_RENDER_STATE_DATA_ROWS);
    std.debug.assert(@intFromEnum(ffi.FfiData.dirty) == c.HOWL_VT_RENDER_STATE_DATA_DIRTY);
    std.debug.assert(@intFromEnum(ffi.FfiData.row_iterator) == c.HOWL_VT_RENDER_STATE_DATA_ROW_ITERATOR);
    std.debug.assert(@intFromEnum(ffi.FfiOption.dirty) == c.HOWL_VT_RENDER_STATE_OPTION_DIRTY);
    std.debug.assert(@intFromEnum(ffi.FfiRowData.invalid) == c.HOWL_VT_RENDER_STATE_ROW_DATA_INVALID);
    std.debug.assert(@intFromEnum(ffi.FfiRowData.dirty) == c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY);
    std.debug.assert(@intFromEnum(ffi.FfiRowOption.dirty) == c.HOWL_VT_RENDER_STATE_ROW_OPTION_DIRTY);
    std.debug.assert(@intFromEnum(ffi.FfiRowCellsData.invalid) == c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_INVALID);
    std.debug.assert(@intFromEnum(ffi.FfiRowCellsData.cell) == c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL);
}

test "vt abi render_state lifecycle null safety" {
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateInit(null));
    ffi.renderStateDeinit(null);
    ffi.renderStateRowIteratorDeinit(null);
    ffi.renderStateRowCellsDeinit(null);

    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    try std.testing.expect(state != null);
    ffi.renderStateDeinit(state);
}

test "vt abi render_state missing handles report missing-handle" {
    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_FALSE;
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateGet(null, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateSet(null, c.HOWL_VT_RENDER_STATE_OPTION_DIRTY, &dirty));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateColorsGet(null, null));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateRowGet(null, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateRowSet(null, c.HOWL_VT_RENDER_STATE_ROW_OPTION_DIRTY, &dirty));
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateRowCellsGet(null, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED, &dirty));
}

test "vt abi render_state invalid enum status" {
    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    defer ffi.renderStateDeinit(state);

    var out: u16 = 0;
    const invalid_data: c_int = 9999;
    const invalid_dirty: c_int = 9999;
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateGet(state, invalid_data, &out));
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateSet(state, c.HOWL_VT_RENDER_STATE_OPTION_DIRTY, &invalid_dirty));
}

test "vt abi render_state dirty get set" {
    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    defer ffi.renderStateDeinit(state);

    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateSet(state, c.HOWL_VT_RENDER_STATE_OPTION_DIRTY, &dirty));
    dirty = c.HOWL_VT_RENDER_STATE_DIRTY_FALSE;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL), dirty);
}

test "vt abi render_state get_multi writes success and first failure" {
    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    defer ffi.renderStateDeinit(state);

    var cols: u16 = 99;
    var rows: u16 = 99;
    var written: usize = 99;
    var keys = [_]c_int{ c.HOWL_VT_RENDER_STATE_DATA_COLS, c.HOWL_VT_RENDER_STATE_DATA_ROWS };
    var values = [_]?*anyopaque{ &cols, &rows };
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGetMulti(state, keys.len, &keys, &values, &written));
    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(u16, 0), cols);
    try std.testing.expectEqual(@as(u16, 0), rows);

    const invalid_data: c_int = 9999;
    keys = [_]c_int{ c.HOWL_VT_RENDER_STATE_DATA_COLS, invalid_data };
    cols = 99;
    written = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateGetMulti(state, keys.len, &keys, &values, &written));
    try std.testing.expectEqual(@as(usize, 1), written);
    try std.testing.expectEqual(@as(u16, 0), cols);
}

test "vt abi render_state colors reject minimum undersized struct" {
    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    defer ffi.renderStateDeinit(state);

    var colors = ffi.FfiColors{ .size = @offsetOf(ffi.FfiColors, "background") };
    try std.testing.expectEqual(c.HOWL_VT_CALL_SHORT_BUFFER, ffi.renderStateColorsGet(state, &colors));
}

test "vt abi render_state row iterator empty before update" {
    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    defer ffi.renderStateDeinit(state);

    var iterator: ffi.FfiRowIteratorHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_ROW_ITERATOR, @ptrCast(&iterator)));
    defer ffi.renderStateRowIteratorDeinit(iterator);
    try std.testing.expect(iterator != null);
    try std.testing.expectEqual(@as(u8, 0), ffi.renderStateRowIteratorNext(iterator));
}

test "vt abi render_state row and cell handle deinit null safety" {
    var iterator: ffi.FfiRowIteratorHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowIteratorInit(&iterator));
    try std.testing.expect(iterator != null);
    ffi.renderStateRowIteratorDeinit(iterator);
    ffi.renderStateRowIteratorDeinit(null);

    var cells: ffi.FfiRowCellsHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsInit(&cells));
    try std.testing.expect(cells != null);
    ffi.renderStateRowCellsDeinit(cells);
    ffi.renderStateRowCellsDeinit(null);
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
