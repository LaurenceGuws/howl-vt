const std = @import("std");
const ffi = @import("ffi");

const c = @cImport({
    @cInclude("howl_vt.h");
});

comptime {
    std.debug.assert(@sizeOf(ffi.FfiBytesResult) == @sizeOf(c.HowlVtBytesResult));
    std.debug.assert(@sizeOf(ffi.FfiFeedResult) == @sizeOf(c.HowlVtFeedResult));
    std.debug.assert(@sizeOf(ffi.FfiVisibleInfo) == @sizeOf(c.HowlVtVisibleInfo));
    std.debug.assert(@sizeOf(ffi.FfiVisibleInfoResult) == @sizeOf(c.HowlVtVisibleInfoResult));
    std.debug.assert(@alignOf(ffi.FfiVisibleInfo) == @alignOf(c.HowlVtVisibleInfo));
    std.debug.assert(@alignOf(ffi.FfiVisibleInfoResult) == @alignOf(c.HowlVtVisibleInfoResult));
    std.debug.assert(@sizeOf(c.HowlVtVisibleInfo) == 48);
    std.debug.assert(@alignOf(c.HowlVtVisibleInfo) == 8);
    std.debug.assert(@sizeOf(c.HowlVtVisibleInfoResult) == 56);
    std.debug.assert(@alignOf(c.HowlVtVisibleInfoResult) == 8);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "rows") == 0);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "cols") == 4);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "history_count") == 8);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "scrollback_offset") == 16);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "is_alternate_screen") == 24);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "reserved0") == 25);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "reserved1") == 26);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "snapshot_seq") == 32);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfo, "dirty_generation") == 40);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfoResult, "status") == 0);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfoResult, "reserved0") == 4);
    std.debug.assert(@offsetOf(c.HowlVtVisibleInfoResult, "info") == 8);
    std.debug.assert(@sizeOf(ffi.FfiRuntimeObligationResult) == @sizeOf(c.HowlVtRuntimeObligationResult));
    std.debug.assert(@sizeOf(ffi.FfiRuntimeProgressResult) == @sizeOf(c.HowlVtRuntimeProgressResult));
    std.debug.assert(@sizeOf(ffi.FfiSelectionResult) == @sizeOf(c.HowlVtSelectionResult));
    std.debug.assert(@sizeOf(ffi.FfiRowSelection) == @sizeOf(c.HowlVtRenderStateRowSelection));
    std.debug.assert(@sizeOf(ffi.FfiRowHighlight) == @sizeOf(c.HowlVtRenderStateRowHighlight));
    std.debug.assert(@sizeOf(ffi.FfiRenderStateColor) == @sizeOf(c.HowlVtColor));
    std.debug.assert(@sizeOf(ffi.FfiRenderStateRgb8) == @sizeOf(c.HowlVtRgb8));
    std.debug.assert(@sizeOf(ffi.FfiRenderStateCellFlags) == @sizeOf(c.HowlVtRenderStateCellFlags));
    std.debug.assert(@sizeOf(ffi.FfiRenderStateCellAttrs) == @sizeOf(c.HowlVtRenderStateCellAttrs));
    std.debug.assert(@sizeOf(ffi.FfiRenderStateCell) == @sizeOf(c.HowlVtRenderStateCell));
    std.debug.assert(@alignOf(ffi.FfiRenderStateCellFlags) == @alignOf(c.HowlVtRenderStateCellFlags));
    std.debug.assert(@alignOf(ffi.FfiRenderStateCellAttrs) == @alignOf(c.HowlVtRenderStateCellAttrs));
    std.debug.assert(@alignOf(ffi.FfiRenderStateCell) == @alignOf(c.HowlVtRenderStateCell));
    std.debug.assert(@sizeOf(c.HowlVtRenderStateCellFlags) == 4);
    std.debug.assert(@sizeOf(c.HowlVtRenderStateCellAttrs) == 10);
    std.debug.assert(@sizeOf(c.HowlVtRenderStateCell) == 68);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellFlags, "continuation") == 0);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellFlags, "reserved0") == 1);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellFlags, "reserved1") == 2);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellFlags, "reserved2") == 3);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "bold") == 0);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "dim") == 1);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "italic") == 2);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "underline") == 3);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "underline_color_set") == 4);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "blink") == 5);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "inverse") == 6);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "invisible") == 7);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "strikethrough") == 8);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCellAttrs, "reserved0") == 9);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "codepoint") == 0);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "combining_len") == 4);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved0") == 5);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved1") == 6);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved2") == 7);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "combining") == 8);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "flags") == 20);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "fg_color") == 24);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "bg_color") == 32);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "underline_color") == 40);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "underline_style") == 48);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved3") == 49);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved4") == 50);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved5") == 51);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "attrs") == 52);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "reserved6") == 62);
    std.debug.assert(@offsetOf(c.HowlVtRenderStateCell, "link_id") == 64);
    std.debug.assert(@sizeOf(ffi.FfiColors) == @sizeOf(c.HowlVtRenderStateColors));

    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.ok) == c.HOWL_VT_CALL_OK);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.missing_handle) == c.HOWL_VT_CALL_MISSING_HANDLE);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.invalid_argument) == c.HOWL_VT_CALL_INVALID_ARGUMENT);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.failed) == c.HOWL_VT_CALL_FAILED);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.short_buffer) == c.HOWL_VT_CALL_SHORT_BUFFER);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.limit_reached) == c.HOWL_VT_CALL_LIMIT_REACHED);
    std.debug.assert(@intFromEnum(ffi.HowlVtCallStatus.no_value) == c.HOWL_VT_CALL_NO_VALUE);

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
    std.debug.assert(@intFromEnum(ffi.FfiRowData.selection) == c.HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION);
    std.debug.assert(@intFromEnum(ffi.FfiRowData.highlight_count) == c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT);
    std.debug.assert(@intFromEnum(ffi.FfiRowData.highlight) == c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT);
    std.debug.assert(@intFromEnum(ffi.FfiRowData.dirty_col_start) == c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START);
    std.debug.assert(@intFromEnum(ffi.FfiRowData.dirty_col_end) == c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END);
    std.debug.assert(@intFromEnum(ffi.FfiRowOption.dirty) == c.HOWL_VT_RENDER_STATE_ROW_OPTION_DIRTY);
    std.debug.assert(@intFromEnum(ffi.FfiRowCellsData.invalid) == c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_INVALID);
    std.debug.assert(@intFromEnum(ffi.FfiRowCellsData.cell) == c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL);
    std.debug.assert(@intFromEnum(ffi.FfiRowCellsData.selected) == c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED);
    std.debug.assert(@intFromEnum(ffi.FfiRowCellsData.highlighted) == c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED);

    const CopyVisibleHyperlinkNoSnapshot = *const fn (c.HowlVtHandle, u16, u16, [*c]u8, usize) callconv(.c) c.HowlVtBytesResult;
    const copy_visible_hyperlink_no_snapshot: CopyVisibleHyperlinkNoSnapshot = c.howl_vt_terminal_copy_visible_hyperlink;
    _ = copy_visible_hyperlink_no_snapshot;
}

test "vt abi visible info query is non-surface metadata" {
    const missing = ffi.terminalQueryVisibleInfo(null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, missing.status);
    try std.testing.expectEqual(@as(u32, 0), missing.info.rows);

    const vt = ffi.terminalInit(2, 4, 8);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcd".ptr, 4).status);
    const result = ffi.terminalQueryVisibleInfo(vt);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, result.status);
    try std.testing.expectEqual(@as(u32, 2), result.info.rows);
    try std.testing.expectEqual(@as(u32, 4), result.info.cols);
    try std.testing.expectEqual(@as(u64, 0), result.info.scrollback_offset);
    try std.testing.expect(result.info.snapshot_seq != 0);
    try std.testing.expect(result.info.dirty_generation != 0);
}

test "vt abi visible hyperlink copies current visible cell without stale snapshot argument" {
    var out: [64]u8 = undefined;

    const missing = ffi.terminalCopyVisibleHyperlink(null, 0, 0, &out, out.len);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, missing.status);

    const vt = ffi.terminalInit(1, 8, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);

    const invalid = ffi.terminalCopyVisibleHyperlink(vt, 0, 0, null, 1);
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, invalid.status);

    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcd".ptr, 4).status);
    const no_link = ffi.terminalCopyVisibleHyperlink(vt, 0, 0, &out, out.len);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, no_link.status);
    try std.testing.expectEqual(@as(u64, 0), no_link.written);
    try std.testing.expectEqual(@as(u64, 0), no_link.needed);

    const out_of_range = ffi.terminalCopyVisibleHyperlink(vt, 9, 9, &out, out.len);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, out_of_range.status);
    try std.testing.expectEqual(@as(u64, 0), out_of_range.written);
    try std.testing.expectEqual(@as(u64, 0), out_of_range.needed);

    const linked = "\x1b[2K\r\x1b]8;;https://example.com\x07link\x1b]8;;\x07";
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, linked.ptr, linked.len).status);
    const copied = ffi.terminalCopyVisibleHyperlink(vt, 0, 0, &out, out.len);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, copied.status);
    try std.testing.expectEqual(@as(u64, "https://example.com".len), copied.written);
    try std.testing.expectEqual(@as(u64, "https://example.com".len), copied.needed);
    try std.testing.expectEqualStrings("https://example.com", out[0..copied.written]);

    var short: [4]u8 = undefined;
    const short_result = ffi.terminalCopyVisibleHyperlink(vt, 0, 0, &short, short.len);
    try std.testing.expectEqual(c.HOWL_VT_CALL_SHORT_BUFFER, short_result.status);
    try std.testing.expectEqual(@as(u64, 0), short_result.written);
    try std.testing.expectEqual(@as(u64, "https://example.com".len), short_result.needed);
}

test "vt abi render_state fixed cell layout has no embedded selected or highlighted facts" {
    var cell = c.HowlVtRenderStateCell{
        .codepoint = 0,
        .combining_len = 0,
        .reserved0 = 0,
        .reserved1 = 0,
        .reserved2 = 0,
        .combining = .{ 0, 0, 0 },
        .flags = .{ .continuation = 0, .reserved0 = 0, .reserved1 = 0, .reserved2 = 0 },
        .fg_color = .{ .kind = 0, .value = 0 },
        .bg_color = .{ .kind = 0, .value = 0 },
        .underline_color = .{ .kind = 0, .value = 0 },
        .underline_style = 0,
        .reserved3 = 0,
        .reserved4 = 0,
        .reserved5 = 0,
        .attrs = .{ .bold = 0, .dim = 0, .italic = 0, .underline = 0, .underline_color_set = 0, .blink = 0, .inverse = 0, .invisible = 0, .strikethrough = 0, .reserved0 = 0 },
        .reserved6 = 0,
        .link_id = 0,
    };
    cell.attrs.reserved0 = 7;
    try std.testing.expectEqual(@as(u8, 7), cell.attrs.reserved0);
}

test "vt abi render_state row cell reads copied facts through render-state cell" {
    const vt = ffi.terminalInit(1, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    const source = "\x1b]8;;https://example.com\x07\x1b[1;2;3;4;5;7;8;9;38;2;1;2;3;48;5;200;58;2;4;5;6mA\xcc\x81\x1b]8;;\x07";
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, source.ptr, source.len).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    const cells = try rowCells(iterator);
    defer ffi.renderStateRowCellsDeinit(cells);
    try std.testing.expectEqual(@as(u8, 1), ffi.renderStateRowCellsNext(cells));

    var cell: ffi.FfiRenderStateCell = .{};
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateRowCellsGet(cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL, null));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGet(cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL, &cell));
    try std.testing.expectEqual(@as(u32, 'A'), cell.codepoint);
    try std.testing.expectEqual(@as(u8, 1), cell.combining_len);
    try std.testing.expectEqual(@as(u32, 0x0301), cell.combining[0]);
    try std.testing.expectEqual(ffi.FfiRenderStateColor{ .kind = 2, .value = 0x010203 }, cell.fg_color);
    try std.testing.expectEqual(ffi.FfiRenderStateColor{ .kind = 1, .value = 200 }, cell.bg_color);
    try std.testing.expectEqual(ffi.FfiRenderStateColor{ .kind = 2, .value = 0x040506 }, cell.underline_color);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.bold);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.dim);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.italic);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.underline);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.underline_color_set);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.blink);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.inverse);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.invisible);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.strikethrough);
    try std.testing.expectEqual(@as(u8, 0), cell.attrs.reserved0);
    try std.testing.expectEqual(@as(u16, 0), cell.reserved6);
    try std.testing.expect(cell.link_id != 0);
}

test "vt abi render_state row cell get_multi writes render-state cell and first failure" {
    const vt = ffi.terminalInit(1, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcd".ptr, 4).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    const cells = try rowCells(iterator);
    defer ffi.renderStateRowCellsDeinit(cells);
    try std.testing.expectEqual(@as(u8, 1), ffi.renderStateRowCellsNext(cells));

    var cell: ffi.FfiRenderStateCell = .{};
    var selected: u8 = 99;
    var written: usize = 99;
    var keys = [_]c_int{ c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED };
    var values = [_]?*anyopaque{ &cell, &selected };
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGetMulti(cells, keys.len, &keys, &values, &written));
    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(u32, 'a'), cell.codepoint);
    try std.testing.expectEqual(@as(u8, 0), selected);

    const invalid_data: c_int = 9999;
    keys = [_]c_int{ c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL, invalid_data };
    cell = .{};
    written = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateRowCellsGetMulti(cells, keys.len, &keys, &values, &written));
    try std.testing.expectEqual(@as(usize, 1), written);
    try std.testing.expectEqual(@as(u32, 'a'), cell.codepoint);
}

fn renderStateWithRows(vt: anytype) !ffi.FfiRenderStateHandle {
    var state: ffi.FfiRenderStateHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateInit(&state));
    errdefer ffi.renderStateDeinit(state);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdate(state, vt));
    return state;
}

test "vt abi render_state row selection no-value sized reject and selected cells" {
    const vt = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcd".ptr, 4).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalStartSelection(vt, 0, 1));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalUpdateSelection(vt, 0, 2));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFinishSelection(vt));

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);

    var short_selection = ffi.FfiRowSelection{ .size = @offsetOf(ffi.FfiRowSelection, "start_col") };
    try std.testing.expectEqual(c.HOWL_VT_CALL_SHORT_BUFFER, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION, &short_selection));
    var selection = ffi.FfiRowSelection{};
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION, &selection));
    try std.testing.expectEqual(@as(u16, 1), selection.start_col);
    try std.testing.expectEqual(@as(u16, 3), selection.end_col);

    const cells = try rowCells(iterator);
    defer ffi.renderStateRowCellsDeinit(cells);
    var selected: u8 = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsSelect(cells, 0));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGet(cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED, &selected));
    try std.testing.expectEqual(@as(u8, 0), selected);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsSelect(cells, 1));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGet(cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED, &selected));
    try std.testing.expectEqual(@as(u8, 1), selected);

    try std.testing.expectEqual(@as(u8, 1), ffi.renderStateRowIteratorNext(iterator));
    selection = .{};
    try std.testing.expectEqual(c.HOWL_VT_CALL_NO_VALUE, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION, &selection));
}

test "vt abi render_state hover highlights ranges cells and dirty rows" {
    const vt = ffi.terminalInit(2, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    const source = "\x1b]8;;https://example.com\x07abcdef\x1b]8;;\x07";
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, source.ptr, source.len).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));

    const iterator_before = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator_before);
    var count: u16 = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_before, c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT, &count));
    try std.testing.expectEqual(@as(u16, 0), count);

    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 1, 4));
    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_FALSE;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL), dirty);

    const iterator_after = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator_after);
    var row_dirty: u8 = 0;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &row_dirty));
    try std.testing.expectEqual(@as(u8, 1), row_dirty);
    var dirty_col_start: u16 = 99;
    var dirty_col_end: u16 = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START, &dirty_col_start));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END, &dirty_col_end));
    try std.testing.expectEqual(@as(u16, 0), dirty_col_start);
    try std.testing.expectEqual(@as(u16, 3), dirty_col_end);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT, &count));
    try std.testing.expectEqual(@as(u16, 1), count);
    var highlight = ffi.FfiRowHighlight{ .index = 0 };
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT, &highlight));
    try std.testing.expectEqual(@as(u8, 1), highlight.tag);
    try std.testing.expectEqual(@as(u16, 0), highlight.start_col);
    try std.testing.expectEqual(@as(u16, 4), highlight.end_col);
    const first_row_cells = try rowCells(iterator_after);
    defer ffi.renderStateRowCellsDeinit(first_row_cells);
    var highlighted: u8 = 0;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsSelect(first_row_cells, 3));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGet(first_row_cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED, &highlighted));
    try std.testing.expectEqual(@as(u8, 1), highlighted);

    try std.testing.expectEqual(@as(u8, 1), ffi.renderStateRowIteratorNext(iterator_after));
    row_dirty = 0;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &row_dirty));
    try std.testing.expectEqual(@as(u8, 1), row_dirty);
    dirty_col_start = 99;
    dirty_col_end = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START, &dirty_col_start));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END, &dirty_col_end));
    try std.testing.expectEqual(@as(u16, 0), dirty_col_start);
    try std.testing.expectEqual(@as(u16, 1), dirty_col_end);
    highlight = .{ .index = 0 };
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator_after, c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT, &highlight));
    try std.testing.expectEqual(@as(u8, 1), highlight.tag);
    try std.testing.expectEqual(@as(u16, 0), highlight.start_col);
    try std.testing.expectEqual(@as(u16, 2), highlight.end_col);
    const second_row_cells = try rowCells(iterator_after);
    defer ffi.renderStateRowCellsDeinit(second_row_cells);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsSelect(second_row_cells, 1));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGet(second_row_cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED, &highlighted));
    try std.testing.expectEqual(@as(u8, 1), highlighted);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsSelect(second_row_cells, 2));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowCellsGet(second_row_cells, c.HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED, &highlighted));
    try std.testing.expectEqual(@as(u8, 0), highlighted);
}

test "vt abi render_state moved hover unions old and new dirty column bounds" {
    const vt = ffi.terminalInit(1, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    const source = "\x1b]8;;https://one.example\x07ab\x1b]8;;\x07\x1b]8;;https://two.example\x07cd\x1b]8;;\x07";
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, source.ptr, source.len).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 0, 0));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 2, 0));

    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    try expectCurrentRowDirtyCols(iterator, true, 0, 3);
}

test "vt abi render_state clearing hover to no-link dirties old highlight columns" {
    const vt = ffi.terminalInit(1, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    const source = "\x1b]8;;https://one.example\x07ab\x1b]8;;\x07cd";
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, source.ptr, source.len).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 0, 0));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 3, 0));

    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_FALSE;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL), dirty);
    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    try expectCurrentRowDirtyCols(iterator, true, 0, 1);
}

test "vt abi render_state clearing hover to out-of-range row dirties old highlight columns" {
    const vt = ffi.terminalInit(1, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    const source = "\x1b]8;;https://one.example\x07ab\x1b]8;;\x07cd";
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, source.ptr, source.len).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 0, 0));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 99, 0, 0));

    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_FALSE;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL), dirty);
    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    try expectCurrentRowDirtyCols(iterator, true, 0, 1);
}

test "vt abi render_state dirty row exposes copied dirty column bounds" {
    const vt = ffi.terminalInit(1, 6, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcdef".ptr, 6).status);

    var state = try renderStateWithRows(vt);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateAck(state, vt));
    ffi.renderStateDeinit(state);

    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "\x1b[1;4HG".ptr, 7).status);
    state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);

    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    var row_dirty: u8 = 0;
    var dirty_col_start: u16 = 99;
    var dirty_col_end: u16 = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &row_dirty));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START, &dirty_col_start));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END, &dirty_col_end));
    try std.testing.expectEqual(@as(u8, 1), row_dirty);
    try std.testing.expectEqual(@as(u16, 3), dirty_col_start);
    try std.testing.expectEqual(@as(u16, 3), dirty_col_end);
}

test "vt abi render_state full-screen dirty exposes full row column bounds" {
    const vt = ffi.terminalInit(2, 3, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcdef".ptr, 6).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_FALSE;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_FULL), dirty);

    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    try expectCurrentRowDirtyCols(iterator, true, 0, 2);
    try std.testing.expectEqual(@as(u8, 1), ffi.renderStateRowIteratorNext(iterator));
    try expectCurrentRowDirtyCols(iterator, true, 0, 2);
}

test "vt abi render_state scroll-exposed dirty row exposes full row column bounds" {
    const vt = ffi.terminalInit(2, 3, 8);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "aaa\r\nbbb".ptr, 8).status);

    var state = try renderStateWithRows(vt);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateAck(state, vt));
    ffi.renderStateDeinit(state);

    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "\r\nccc".ptr, 5).status);
    state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);

    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    _ = ffi.renderStateRowIteratorNext(iterator);
    try expectCurrentRowDirtyCols(iterator, true, 0, 2);
}

test "vt abi render_state public hover no-link and out-of-range leave highlights and dirty false" {
    const vt = ffi.terminalInit(1, 4, 4);
    defer ffi.terminalDeinit(vt);
    try std.testing.expect(vt != null);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.terminalFeed(vt, "abcd".ptr, 4).status);

    const state = try renderStateWithRows(vt);
    defer ffi.renderStateDeinit(state);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.testRenderStateClearDirty(state));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 0, 0));

    var dirty: c_int = c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_FALSE), dirty);
    const iterator = try firstRowIterator(state);
    defer ffi.renderStateRowIteratorDeinit(iterator);
    var row_dirty: u8 = 1;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &row_dirty));
    try std.testing.expectEqual(@as(u8, 0), row_dirty);
    var count: u16 = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT, &count));
    try std.testing.expectEqual(@as(u16, 0), count);

    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 99, 0, 0));

    dirty = c.HOWL_VT_RENDER_STATE_DIRTY_PARTIAL;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_DIRTY, &dirty));
    try std.testing.expectEqual(@as(c_int, c.HOWL_VT_RENDER_STATE_DIRTY_FALSE), dirty);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &row_dirty));
    try std.testing.expectEqual(@as(u8, 0), row_dirty);
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT, &count));
    try std.testing.expectEqual(@as(u16, 0), count);
}

fn firstRowIterator(state: ffi.FfiRenderStateHandle) !ffi.FfiRowIteratorHandle {
    var iterator: ffi.FfiRowIteratorHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateGet(state, c.HOWL_VT_RENDER_STATE_DATA_ROW_ITERATOR, @ptrCast(&iterator)));
    errdefer ffi.renderStateRowIteratorDeinit(iterator);
    try std.testing.expectEqual(@as(u8, 1), ffi.renderStateRowIteratorNext(iterator));
    return iterator;
}

fn rowCells(iterator: ffi.FfiRowIteratorHandle) !ffi.FfiRowCellsHandle {
    var cells: ffi.FfiRowCellsHandle = null;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_CELLS, @ptrCast(&cells)));
    return cells;
}

fn expectCurrentRowDirtyCols(iterator: ffi.FfiRowIteratorHandle, expected_dirty: bool, expected_start: u16, expected_end: u16) !void {
    var row_dirty: u8 = 0;
    var dirty_col_start: u16 = 99;
    var dirty_col_end: u16 = 99;
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY, &row_dirty));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START, &dirty_col_start));
    try std.testing.expectEqual(c.HOWL_VT_CALL_OK, ffi.renderStateRowGet(iterator, c.HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END, &dirty_col_end));
    try std.testing.expectEqual(@as(u8, if (expected_dirty) 1 else 0), row_dirty);
    try std.testing.expectEqual(expected_start, dirty_col_start);
    try std.testing.expectEqual(expected_end, dirty_col_end);
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
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.renderStateUpdateHighlightsForHyperlink(null, 1, 0, 0, 0));
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
    try std.testing.expectEqual(c.HOWL_VT_CALL_INVALID_ARGUMENT, ffi.renderStateUpdateHighlightsForHyperlink(state, 1, 0, 0, 5));
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
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalStartSelection(null, 0, 0));

    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalFeed(null, null, 0).status);
    try std.testing.expectEqual(c.HOWL_VT_CALL_MISSING_HANDLE, ffi.terminalCopyTitle(null, null, 0).status);
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

test "vt abi lifecycle and runtime contract are exported" {
    const handle = ffi.terminalInitWithOptions(24, 80, 16, .{ .default_cursor_style = .{ .shape = 2, .blink = 0 } });
    defer ffi.terminalDeinit(handle);
    try std.testing.expect(handle != null);

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
