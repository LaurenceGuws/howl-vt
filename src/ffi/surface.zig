const std = @import("std");
const screen = @import("../screen.zig");
const screen_set = @import("../screen_set.zig");
const terminal = @import("../terminal.zig");
const host_state = @import("../host/state.zig");
const selection_projection = @import("../selection/projection.zig");
const terminal_selection = @import("../selection.zig");
const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const selection_ffi = @import("selection.zig");
const status = @import("status.zig");

pub const FfiColor = extern struct {
    kind: u8 = 0,
    value: u32 = 0,
};

pub const FfiRgb8 = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

pub const FfiRenderColorState = extern struct {
    foreground: FfiRgb8 = .{},
    background: FfiRgb8 = .{},
    cursor: FfiRgb8 = .{},
    palette: [256]FfiRgb8 = [_]FfiRgb8{.{}} ** 256,
};

pub const FfiSurfaceCellFlags = extern struct {
    continuation: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u8 = 0,
    reserved2: u8 = 0,
};

pub const FfiSurfaceCellAttrs = extern struct {
    bold: u8 = 0,
    dim: u8 = 0,
    italic: u8 = 0,
    underline: u8 = 0,
    underline_color_set: u8 = 0,
    blink: u8 = 0,
    inverse: u8 = 0,
    invisible: u8 = 0,
    strikethrough: u8 = 0,
    selected: u8 = 0,
};

pub const FfiSurfaceCell = extern struct {
    codepoint: u32 = 0,
    combining_len: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u8 = 0,
    reserved2: u8 = 0,
    combining: [3]u32 = [_]u32{0} ** 3,
    flags: FfiSurfaceCellFlags = .{},
    fg_color: FfiColor = .{},
    bg_color: FfiColor = .{},
    underline_color: FfiColor = .{},
    underline_style: u8 = 0,
    reserved3: u8 = 0,
    reserved4: u8 = 0,
    reserved5: u8 = 0,
    attrs: FfiSurfaceCellAttrs = .{},
    link_id: u32 = 0,
};

pub const FfiSurfaceCellSpan = extern struct {
    ptr: [*c]const FfiSurfaceCell,
    // The shipped C ABI owns architecture-sized span lengths at this boundary.
    len: usize,
};

pub const FfiCursor = extern struct {
    row: u16,
    col: u16,
    visible: u8,
    shape: u8,
    blink: u8,
};

pub const FfiSurface = extern struct {
    surface_cells: FfiSurfaceCellSpan,
    cols: u16,
    rows: u16,
    scroll_row: u64,
    is_alternate_screen: u8,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    dirty_rows: bytes.FfiByteSpan,
    dirty_cols_start: bytes.FfiU16Span,
    dirty_cols_end: bytes.FfiU16Span,
    cursor: FfiCursor,
    colors: FfiRenderColorState = .{},
    selection: selection_ffi.FfiSelection = .{},
};

pub const FfiVisibleMeta = extern struct {
    rows: u16 = 0,
    cols: u16 = 0,
    history_count: u64 = 0,
    is_alternate_screen: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    snapshot_seq: u64 = 0,
    dirty_generation: u64 = 0,
};

pub const FfiVisibleMetaResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    meta: FfiVisibleMeta = .{},
};

pub const FfiSurfaceResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    history_count: u64 = 0,
    scrollback_offset: u64 = 0,
    snapshot_seq: u64 = 0,
    dirty_generation: u64 = 0,
    source: FfiSurface = .{
        .surface_cells = .{ .ptr = null, .len = 0 },
        .cols = 0,
        .rows = 0,
        .scroll_row = 0,
        .is_alternate_screen = 0,
        .dirty_rows = .{ .ptr = null, .len = 0 },
        .dirty_cols_start = .{ .ptr = null, .len = 0 },
        .dirty_cols_end = .{ .ptr = null, .len = 0 },
        .cursor = .{ .row = 0, .col = 0, .visible = 0, .shape = 0, .blink = 0 },
        .colors = .{},
        .selection = .{},
    },
};

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

fn surfaceCellCount(rows: u16, cols: u16) u32 {
    return @as(u32, rows) * @as(u32, cols);
}

fn colorOut(value: screen.Screen.Color) FfiColor {
    return switch (value.kind) {
        .default => .{ .kind = 0, .value = 0 },
        .indexed => .{ .kind = 1, .value = value.value },
        .rgb => .{ .kind = 2, .value = value.value },
    };
}

fn rgbOut(value: screen.Screen.Rgb) FfiRgb8 {
    return .{ .r = value.r, .g = value.g, .b = value.b };
}

fn renderColorStateOut(value: anytype) FfiRenderColorState {
    var out = FfiRenderColorState{
        .foreground = rgbOut(value.foreground),
        .background = rgbOut(value.background),
        .cursor = rgbOut(value.cursor orelse value.foreground),
    };
    for (value.palette, 0..) |color, idx| out.palette[idx] = rgbOut(color);
    return out;
}

fn cellOut(value: screen.Screen.Cell) FfiSurfaceCell {
    return .{
        .codepoint = value.codepoint,
        .combining_len = value.combining_len,
        .combining = value.combining,
        .flags = .{ .continuation = boolByte(screen.Screen.isCellContinuation(value)) },
        .fg_color = colorOut(value.attrs.fg),
        .bg_color = colorOut(value.attrs.bg),
        .underline_color = colorOut(value.attrs.underline_color),
        .underline_style = @intFromEnum(value.attrs.underline_style),
        .attrs = .{
            .bold = boolByte(value.attrs.bold),
            .dim = boolByte(value.attrs.dim),
            .italic = boolByte(value.attrs.italic),
            .underline = boolByte(value.attrs.underline),
            .underline_color_set = boolByte(value.attrs.underline_color.kind != .default),
            .blink = boolByte(value.attrs.blink or value.attrs.blink_fast),
            .inverse = boolByte(value.attrs.reverse),
            .invisible = boolByte(value.attrs.invisible),
            .strikethrough = boolByte(value.attrs.strikethrough),
            .selected = 0,
        },
        .link_id = value.attrs.link_id,
    };
}

fn surfaceResult(vt: *terminal.Terminal, view: screen_set.View, selected: ?terminal_selection.TerminalSelection, snapshot_seq: u64, dirty_generation: u64, cells_ptr: ?[*]FfiSurfaceCell, dirty_rows_ptr: ?[*]u8, cols_start_ptr: ?[*]u16, cols_end_ptr: ?[*]u16) FfiSurfaceResult {
    const colors = renderColorStateOut(host_state.terminalColorState(vt));
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .history_count = view.history_count,
        .scrollback_offset = view.scrollback_offset,
        .snapshot_seq = snapshot_seq,
        .dirty_generation = dirty_generation,
        .source = .{
            // VT keeps cell counts typed as u16/u32 until this shipped C ABI span-length seam.
            .surface_cells = .{ .ptr = cells_ptr, .len = @intCast(surfaceCellCount(view.rows, view.cols)) },
            .cols = view.cols,
            .rows = view.rows,
            .scroll_row = view.start,
            .is_alternate_screen = boolByte(view.is_alternate_screen),
            .dirty_rows = .{ .ptr = dirty_rows_ptr, .len = view.rows },
            .dirty_cols_start = .{ .ptr = cols_start_ptr, .len = view.rows },
            .dirty_cols_end = .{ .ptr = cols_end_ptr, .len = view.rows },
            .cursor = .{
                .row = view.cursor_row,
                .col = view.cursor_col,
                .visible = boolByte(view.cursor_visible),
                .shape = @intFromEnum(view.cursor_shape),
                .blink = boolByte(view.cursor_blink),
            },
            .colors = colors,
            .selection = selection_ffi.selectionOut(selected),
        },
    };
}

fn visibleMetaResult(meta: terminal.Terminal.VisibleMeta) FfiVisibleMetaResult {
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .meta = .{
            .rows = meta.rows,
            .cols = meta.cols,
            .history_count = meta.history_count,
            .is_alternate_screen = boolByte(meta.is_alternate_screen),
            .snapshot_seq = meta.snapshot_seq,
            .dirty_generation = meta.dirty_generation,
        },
    };
}

fn applySelectionRangesToSurfaceCells(view: screen_set.View, selected: ?terminal_selection.TerminalSelection, cells: []FfiSurfaceCell) void {
    const active = selected orelse return;
    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        const range = selection_projection.visibleRange(view, active, row) orelse continue;
        const base: usize = @as(usize, row) * @as(usize, view.cols);
        var col = range.start;
        while (col < range.end_exclusive) : (col += 1) {
            cells[base + col].attrs.selected = 1;
        }
    }
}

pub fn terminalAckSurface(vt_handle: handle.VtHandle, snapshot_seq: u64) callconv(.c) i32 {
    const owned = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    return if (owned.ackSurface(snapshot_seq))
        @intFromEnum(status.HowlVtCallStatus.ok)
    else
        @intFromEnum(status.HowlVtCallStatus.invalid_argument);
}

pub fn terminalQueryVisibleMeta(vt_handle: handle.VtHandle, scrollback_offset: u64) callconv(.c) FfiVisibleMetaResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    return visibleMetaResult(owned.visibleMeta(scrollback_offset));
}

pub fn terminalCopySurface(
    vt_handle: handle.VtHandle,
    scrollback_offset: u64,
    cells_ptr: ?[*]FfiSurfaceCell,
    cells_cap: usize,
    dirty_rows_ptr: ?[*]u8,
    dirty_rows_cap: usize,
    cols_start_ptr: ?[*]u16,
    cols_start_cap: usize,
    cols_end_ptr: ?[*]u16,
    cols_end_cap: usize,
) callconv(.c) FfiSurfaceResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const publication = owned.surfaceSnapshot(scrollback_offset);
    const snapshot = publication.snapshot;
    const view = snapshot.view;
    const cell_count = surfaceCellCount(view.rows, view.cols);
    // The shipped VT ABI still accepts architecture-sized destination capacities.
    // Validate those seam values against typed VT counts before exposing writable slices.
    var result = surfaceResult(owned, view, snapshot.selection, publication.snapshot_seq, publication.dirty_generation, cells_ptr, dirty_rows_ptr, cols_start_ptr, cols_end_ptr);

    if (cells_cap < cell_count or dirty_rows_cap < view.rows or cols_start_cap < view.rows or cols_end_cap < view.rows) {
        result.status = @intFromEnum(status.HowlVtCallStatus.short_buffer);
        return result;
    }

    const cells_out = if (cells_ptr) |ptr| ptr[0..cells_cap] else {
        result.status = @intFromEnum(status.HowlVtCallStatus.invalid_argument);
        return result;
    };
    const dirty_rows_out = if (dirty_rows_ptr) |ptr| ptr[0..dirty_rows_cap] else {
        result.status = @intFromEnum(status.HowlVtCallStatus.invalid_argument);
        return result;
    };
    const cols_start = if (cols_start_ptr) |ptr| ptr[0..cols_start_cap] else {
        result.status = @intFromEnum(status.HowlVtCallStatus.invalid_argument);
        return result;
    };
    const cols_end = if (cols_end_ptr) |ptr| ptr[0..cols_end_cap] else {
        result.status = @intFromEnum(status.HowlVtCallStatus.invalid_argument);
        return result;
    };

    screen_set.copyViewCells(view, cells_out, cellOut);
    applySelectionRangesToSurfaceCells(view, snapshot.selection, cells_out[0..@intCast(cell_count)]);
    screen_set.copyDirtyRows(dirty_rows_out[0..view.rows], cols_start[0..view.rows], cols_end[0..view.rows], snapshot.dirty);

    return result;
}

pub fn terminalCopySurfaceHyperlink(vt_handle: handle.VtHandle, scrollback_offset: u64, snapshot_seq: u64, row: u16, col: u16, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const uri = owned.visibleCellHyperlinkUri(scrollback_offset, snapshot_seq, row, col) catch {
        return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    } orelse &.{};
    return bytes.copyBytes(out, uri);
}

test "vt ffi surface reports metadata on short buffer" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 8);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const fed = lifecycle.terminalFeed(vt_handle, "abc".ptr, 3);
    try std.testing.expectEqual(@as(i32, 0), fed.status);
    try std.testing.expectEqual(@as(u8, 1), fed.state_changed);

    var cells: [8]FfiSurfaceCell = undefined;
    const source = terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, null, 0, null, 0, null, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.short_buffer)), source.status);
    try std.testing.expectEqual(@as(u16, 2), source.source.rows);
    try std.testing.expectEqual(@as(u16, 4), source.source.cols);
}

test "vt ffi exports style attrs and resets" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(1, 2, 0);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const source_bytes = "\x1b[1;2;3;8;9mA\x1b[22;23;28;29mB";
    const fed = lifecycle.terminalFeed(vt_handle, source_bytes.ptr, source_bytes.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), fed.status);

    var cells: [2]FfiSurfaceCell = undefined;
    var dirty_rows: [1]u8 = undefined;
    var cols_start: [1]u16 = undefined;
    var cols_end: [1]u16 = undefined;
    const surface = terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), surface.status);

    try std.testing.expectEqual(@as(u32, 'A'), cells[0].codepoint);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.bold);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.dim);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.italic);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.invisible);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.strikethrough);

    try std.testing.expectEqual(@as(u32, 'B'), cells[1].codepoint);
    try std.testing.expectEqual(@as(u8, 0), cells[1].attrs.bold);
    try std.testing.expectEqual(@as(u8, 0), cells[1].attrs.dim);
    try std.testing.expectEqual(@as(u8, 0), cells[1].attrs.italic);
    try std.testing.expectEqual(@as(u8, 0), cells[1].attrs.invisible);
    try std.testing.expectEqual(@as(u8, 0), cells[1].attrs.strikethrough);
}

test "vt ffi query visible meta reports explicit surface metadata" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 2, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const fed = lifecycle.terminalFeed(vt_handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, 0), fed.status);

    const meta = terminalQueryVisibleMeta(vt_handle, std.math.maxInt(u64));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(@as(u16, 2), meta.meta.rows);
    try std.testing.expectEqual(@as(u16, 2), meta.meta.cols);
    try std.testing.expectEqual(@as(u64, 1), meta.meta.history_count);
    try std.testing.expectEqual(@as(u8, 0), meta.meta.is_alternate_screen);
    try std.testing.expect(meta.meta.snapshot_seq != 0);
    try std.testing.expect(meta.meta.dirty_generation != 0);
}

test "vt ffi surface copy carries render color state" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 2, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const source_bytes = "\x1b]4;1;#010203\x1b\\\x1b]10;#040506\x1b\\\x1b]11;#070809\x1b\\\x1b]12;#0a0b0c\x1b\\";
    try std.testing.expectEqual(@as(i32, 0), lifecycle.terminalFeed(vt_handle, source_bytes.ptr, source_bytes.len).status);

    var cells: [4]FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    const surface = terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);

    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), surface.status);
    try std.testing.expectEqual(FfiRgb8{ .r = 4, .g = 5, .b = 6 }, surface.source.colors.foreground);
    try std.testing.expectEqual(FfiRgb8{ .r = 7, .g = 8, .b = 9 }, surface.source.colors.background);
    try std.testing.expectEqual(FfiRgb8{ .r = 10, .g = 11, .b = 12 }, surface.source.colors.cursor);
    try std.testing.expectEqual(FfiRgb8{ .r = 1, .g = 2, .b = 3 }, surface.source.colors.palette[1]);
}

test "vt ffi surface copy preserves semantic cell color identity" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(1, 3, 0);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const source_bytes = "\x1b[31;44mA\x1b[38;2;1;2;3;48;5;200mB\x1b[39;49mC";
    try std.testing.expectEqual(@as(i32, 0), lifecycle.terminalFeed(vt_handle, source_bytes.ptr, source_bytes.len).status);

    var cells: [3]FfiSurfaceCell = undefined;
    var dirty_rows: [1]u8 = undefined;
    var cols_start: [1]u16 = undefined;
    var cols_end: [1]u16 = undefined;
    const surface = terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);

    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), surface.status);
    try std.testing.expectEqual(FfiColor{ .kind = 1, .value = 1 }, cells[0].fg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 1, .value = 4 }, cells[0].bg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 2, .value = 0x010203 }, cells[1].fg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 1, .value = 200 }, cells[1].bg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 0, .value = 0 }, cells[2].fg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 0, .value = 0 }, cells[2].bg_color);
}

test "vt ffi copy surface clamps oversized scrollback offset" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 2, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const fed = lifecycle.terminalFeed(vt_handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, 0), fed.status);

    const meta = terminalQueryVisibleMeta(vt_handle, std.math.maxInt(u64));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(meta.meta.history_count, @as(u64, 1));
}

test "vt ffi copies visible cell hyperlink for matching snapshot" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(1, 8, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const seq = "\x1b]8;;https://example.com\x07abc\x1b]8;;\x07";
    const fed = lifecycle.terminalFeed(vt_handle, seq.ptr, seq.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), fed.status);

    const meta = terminalQueryVisibleMeta(vt_handle, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), meta.status);

    var out: [32]u8 = undefined;
    const uri = terminalCopySurfaceHyperlink(vt_handle, 0, meta.meta.snapshot_seq, 0, 1, out[0..].ptr, out.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), uri.status);
    try std.testing.expectEqualStrings("https://example.com", out[0..@intCast(uri.written)]);
}

test "vt ffi rejects visible cell hyperlink lookup for stale snapshot" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(1, 8, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const first_seq = "\x1b]8;;https://example.com\x07a\x1b]8;;\x07";
    const first_feed = lifecycle.terminalFeed(vt_handle, first_seq.ptr, first_seq.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), first_feed.status);
    const first_meta = terminalQueryVisibleMeta(vt_handle, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), first_meta.status);

    const second_feed = lifecycle.terminalFeed(vt_handle, "b".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), second_feed.status);

    var out: [32]u8 = undefined;
    const uri = terminalCopySurfaceHyperlink(vt_handle, 0, first_meta.meta.snapshot_seq, 0, 0, out[0..].ptr, out.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), uri.status);
}

test "vt ffi surface selection follows viewport and hugs visible content" {
    const lifecycle = @import("lifecycle.zig");
    const selection = @import("selection.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 8);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const fed = lifecycle.terminalFeed(vt_handle, "aa\r\nbb\r\ncc".ptr, 10);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), fed.status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection.terminalStartSelection(vt_handle, 0, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection.terminalUpdateSelection(vt_handle, 1, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection.terminalFinishSelection(vt_handle));

    var cells: [8]FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;

    const live = terminalCopySurface(vt_handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), live.status);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[1].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[2].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[3].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[4].attrs.selected);

    const scrolled = terminalCopySurface(vt_handle, 1, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), scrolled.status);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[1].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[2].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[3].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[4].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[5].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[6].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[7].attrs.selected);
}
