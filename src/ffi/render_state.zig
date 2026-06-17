const std = @import("std");
const render_state = @import("../render_state.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub const FfiRenderState = opaque {};
pub const FfiRenderStateHandle = ?*FfiRenderState;
pub const FfiRowIterator = opaque {};
pub const FfiRowIteratorHandle = ?*FfiRowIterator;
pub const FfiRowCells = opaque {};
pub const FfiRowCellsHandle = ?*FfiRowCells;

const RenderStateBox = struct { state: render_state.RenderState };
const RowIteratorBox = struct { state: ?*render_state.RenderState = null, row: u16 = 0, has_row: bool = false };
const RowCellsBox = struct { row: ?*const render_state.RenderState.Row = null, col: u16 = 0, has_cell: bool = false };

pub const FfiDirty = enum(c_int) { false = 0, partial = 1, full = 2 };
pub const FfiCursorVisualStyle = enum(c_int) { bar = 0, block = 1, underline = 2, block_hollow = 3 };
pub const FfiData = enum(c_int) {
    invalid = 0,
    cols = 1,
    rows = 2,
    dirty = 3,
    row_iterator = 4,
    color_background = 5,
    color_foreground = 6,
    color_cursor = 7,
    color_cursor_has_value = 8,
    color_palette = 9,
    cursor_visual_style = 10,
    cursor_visible = 11,
    cursor_blinking = 12,
    cursor_viewport_has_value = 13,
    cursor_viewport_x = 14,
    cursor_viewport_y = 15,
    cursor_viewport_wide_tail = 16,
    snapshot_seq = 17,
    dirty_generation = 18,
    history_count = 19,
    scrollback_offset = 20,
    scroll_row = 21,
    is_alternate_screen = 22,
};
pub const FfiOption = enum(c_int) { dirty = 0 };
pub const FfiRowData = enum(c_int) { invalid = 0, dirty = 1, cells = 2, selection = 3, highlight_count = 4, highlight = 5 };
pub const FfiRowOption = enum(c_int) { dirty = 0 };
pub const FfiRowCellsData = enum(c_int) { invalid = 0, cell = 1, selected = 2, highlighted = 3 };

pub const FfiRowSelection = extern struct { size: usize = @sizeOf(FfiRowSelection), start_col: u16 = 0, end_col: u16 = 0 };
pub const FfiRowHighlight = extern struct { size: usize = @sizeOf(FfiRowHighlight), tag: u8 = 0, reserved0: u8 = 0, index: u16 = 0, start_col: u16 = 0, end_col: u16 = 0 };
pub const FfiRenderStateColor = extern struct { kind: u8 = 0, value: u32 = 0 };
pub const FfiRenderStateRgb8 = extern struct { r: u8 = 0, g: u8 = 0, b: u8 = 0 };
pub const FfiRenderStateCellFlags = extern struct { continuation: u8 = 0, reserved0: u8 = 0, reserved1: u8 = 0, reserved2: u8 = 0 };
pub const FfiRenderStateCellAttrs = extern struct {
    bold: u8 = 0,
    dim: u8 = 0,
    italic: u8 = 0,
    underline: u8 = 0,
    underline_color_set: u8 = 0,
    blink: u8 = 0,
    inverse: u8 = 0,
    invisible: u8 = 0,
    strikethrough: u8 = 0,
    reserved0: u8 = 0,
};
pub const FfiRenderStateCell = extern struct {
    codepoint: u32 = 0,
    combining_len: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u8 = 0,
    reserved2: u8 = 0,
    combining: [3]u32 = [_]u32{0} ** 3,
    flags: FfiRenderStateCellFlags = .{},
    fg_color: FfiRenderStateColor = .{},
    bg_color: FfiRenderStateColor = .{},
    underline_color: FfiRenderStateColor = .{},
    underline_style: u8 = 0,
    reserved3: u8 = 0,
    reserved4: u8 = 0,
    reserved5: u8 = 0,
    attrs: FfiRenderStateCellAttrs = .{},
    reserved6: u16 = 0,
    link_id: u32 = 0,
};
pub const FfiColors = extern struct {
    size: usize = @sizeOf(FfiColors),
    background: FfiRenderStateRgb8 = .{},
    foreground: FfiRenderStateRgb8 = .{},
    cursor: FfiRenderStateRgb8 = .{},
    cursor_has_value: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    palette: [256]FfiRenderStateRgb8 = [_]FfiRenderStateRgb8{.{}} ** 256,
};

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

fn rgbOut(value: render_state.RenderState.Rgb8) FfiRenderStateRgb8 {
    return .{ .r = value.r, .g = value.g, .b = value.b };
}

fn colorOut(value: render_state.RenderState.Color) FfiRenderStateColor {
    return .{ .kind = @intFromEnum(value.kind), .value = value.value };
}

fn cellOut(value: render_state.RenderState.Cell) FfiRenderStateCell {
    return .{
        .codepoint = value.codepoint,
        .combining_len = value.combining_len,
        .combining = value.combining,
        .flags = .{ .continuation = boolByte(value.continuation) },
        .fg_color = colorOut(value.fg_color),
        .bg_color = colorOut(value.bg_color),
        .underline_color = colorOut(value.underline_color),
        .underline_style = @intFromEnum(value.underline_style),
        .attrs = .{
            .bold = boolByte(value.bold),
            .dim = boolByte(value.dim),
            .italic = boolByte(value.italic),
            .underline = boolByte(value.underline),
            .underline_color_set = boolByte(value.underline_color.kind != .default),
            .blink = boolByte(value.blink),
            .inverse = boolByte(value.inverse),
            .invisible = boolByte(value.invisible),
            .strikethrough = boolByte(value.strikethrough),
        },
        .link_id = value.link_id,
    };
}

fn renderStateFromHandle(state: FfiRenderStateHandle) ?*RenderStateBox {
    const owned = state orelse return null;
    return @ptrCast(@alignCast(owned));
}

fn rowIteratorFromHandle(iterator: FfiRowIteratorHandle) ?*RowIteratorBox {
    const owned = iterator orelse return null;
    return @ptrCast(@alignCast(owned));
}

fn rowCellsFromHandle(cells: FfiRowCellsHandle) ?*RowCellsBox {
    const owned = cells orelse return null;
    return @ptrCast(@alignCast(owned));
}

fn dirtyOut(value: render_state.RenderState.Dirty) FfiDirty {
    return switch (value) {
        .false => .false,
        .partial => .partial,
        .full => .full,
    };
}

fn cursorVisualStyleOut(value: render_state.RenderState.CursorVisualStyle) FfiCursorVisualStyle {
    return switch (value) {
        .bar => .bar,
        .block => .block,
        .underline => .underline,
        .block_hollow => .block_hollow,
    };
}

fn dirtyIn(value: c_int) ?render_state.RenderState.Dirty {
    return switch (value) {
        0 => .false,
        1 => .partial,
        2 => .full,
        else => null,
    };
}

fn dataIn(value: c_int) ?FfiData {
    return switch (value) {
        1 => .cols,
        2 => .rows,
        3 => .dirty,
        4 => .row_iterator,
        5 => .color_background,
        6 => .color_foreground,
        7 => .color_cursor,
        8 => .color_cursor_has_value,
        9 => .color_palette,
        10 => .cursor_visual_style,
        11 => .cursor_visible,
        12 => .cursor_blinking,
        13 => .cursor_viewport_has_value,
        14 => .cursor_viewport_x,
        15 => .cursor_viewport_y,
        16 => .cursor_viewport_wide_tail,
        17 => .snapshot_seq,
        18 => .dirty_generation,
        19 => .history_count,
        20 => .scrollback_offset,
        21 => .scroll_row,
        22 => .is_alternate_screen,
        else => null,
    };
}

fn optionIn(value: c_int) ?FfiOption {
    return switch (value) {
        0 => .dirty,
        else => null,
    };
}

fn rowDataIn(value: c_int) ?FfiRowData {
    return switch (value) {
        1 => .dirty,
        2 => .cells,
        3 => .selection,
        4 => .highlight_count,
        5 => .highlight,
        else => null,
    };
}

fn rowOptionIn(value: c_int) ?FfiRowOption {
    return switch (value) {
        0 => .dirty,
        else => null,
    };
}

fn rowCellsDataIn(value: c_int) ?FfiRowCellsData {
    return switch (value) {
        1 => .cell,
        2 => .selected,
        3 => .highlighted,
        else => null,
    };
}

fn underlineStyleIn(value: u8) ?render_state.RenderState.UnderlineStyle {
    return switch (value) {
        0 => .straight,
        1 => .double,
        2 => .curly,
        3 => .dotted,
        4 => .dashed,
        else => null,
    };
}

fn writeOut(comptime Value: type, out: ?*anyopaque, value: Value) i32 {
    const target: *Value = @ptrCast(@alignCast(out orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument)));
    target.* = value;
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

fn rowSelectionOut(out: ?*anyopaque, selection: ?render_state.RenderState.SelectionRange) i32 {
    const target: *FfiRowSelection = @ptrCast(@alignCast(out orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument)));
    if (target.size < @sizeOf(FfiRowSelection)) return @intFromEnum(status.HowlVtCallStatus.short_buffer);
    const value = selection orelse return @intFromEnum(status.HowlVtCallStatus.no_value);
    const size = target.size;
    target.* = .{ .size = size, .start_col = value.start_col, .end_col = value.end_col };
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

fn rowHighlightOut(out: ?*anyopaque, row: *const render_state.RenderState.Row) i32 {
    const target: *FfiRowHighlight = @ptrCast(@alignCast(out orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument)));
    if (target.size < @sizeOf(FfiRowHighlight)) return @intFromEnum(status.HowlVtCallStatus.short_buffer);
    if (target.index >= row.highlight_count) return @intFromEnum(status.HowlVtCallStatus.no_value);
    const size = target.size;
    const requested_index = target.index;
    const value = row.highlights[requested_index];
    target.* = .{ .size = size, .tag = value.tag, .index = requested_index, .start_col = value.start_col, .end_col = value.end_col };
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

fn rowIteratorForState(state: *render_state.RenderState) FfiRowIteratorHandle {
    const iterator = std.heap.c_allocator.create(RowIteratorBox) catch return null;
    iterator.* = .{ .state = state };
    return @ptrCast(iterator);
}

pub fn renderStateInit(out_state: ?*FfiRenderStateHandle) callconv(.c) i32 {
    const target = out_state orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const owned = std.heap.c_allocator.create(RenderStateBox) catch return @intFromEnum(status.HowlVtCallStatus.failed);
    owned.* = .{ .state = render_state.RenderState.empty() };
    target.* = @ptrCast(owned);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateDeinit(state: FfiRenderStateHandle) callconv(.c) void {
    const owned = renderStateFromHandle(state) orelse return;
    owned.state.deinit(std.heap.c_allocator);
    std.heap.c_allocator.destroy(owned);
}

pub fn renderStateUpdate(state: FfiRenderStateHandle, vt_handle: handle.VtHandle, scrollback_offset: u64) callconv(.c) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const vt = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.state.update(std.heap.c_allocator, vt, scrollback_offset) catch return @intFromEnum(status.HowlVtCallStatus.failed);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateAck(state: FfiRenderStateHandle, vt_handle: handle.VtHandle) callconv(.c) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const vt = handle.vtFromHandle(vt_handle) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    return if (owned.state.ack(vt)) @intFromEnum(status.HowlVtCallStatus.ok) else @intFromEnum(status.HowlVtCallStatus.invalid_argument);
}

pub fn renderStateUpdateHighlightsForHyperlink(state: FfiRenderStateHandle, tag: u8, row: u16, col: u16, underline_style: u8) callconv(.c) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const style = underlineStyleIn(underline_style) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    owned.state.updateHighlightsForHyperlink(tag, row, col, style);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateGet(state: FfiRenderStateHandle, data: c_int, out: ?*anyopaque) callconv(.c) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const valid = dataIn(data) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    return switch (valid) {
        .invalid => unreachable,
        .cols => writeOut(u16, out, owned.state.cols),
        .rows => writeOut(u16, out, owned.state.rows),
        .dirty => writeOut(FfiDirty, out, dirtyOut(owned.state.dirty)),
        .row_iterator => blk: {
            const iterator = rowIteratorForState(&owned.state) orelse break :blk @intFromEnum(status.HowlVtCallStatus.failed);
            break :blk writeOut(FfiRowIteratorHandle, out, iterator);
        },
        .color_background => writeOut(FfiRenderStateRgb8, out, rgbOut(owned.state.colors.background)),
        .color_foreground => writeOut(FfiRenderStateRgb8, out, rgbOut(owned.state.colors.foreground)),
        .color_cursor => writeOut(FfiRenderStateRgb8, out, rgbOut(owned.state.colors.cursor orelse .{})),
        .color_cursor_has_value => writeOut(u8, out, boolByte(owned.state.colors.cursor != null)),
        .color_palette => return @intFromEnum(status.HowlVtCallStatus.invalid_argument),
        .cursor_visual_style => writeOut(FfiCursorVisualStyle, out, cursorVisualStyleOut(owned.state.cursor.visual_style)),
        .cursor_visible => writeOut(u8, out, boolByte(owned.state.cursor.visible)),
        .cursor_blinking => writeOut(u8, out, boolByte(owned.state.cursor.blinking)),
        .cursor_viewport_has_value => writeOut(u8, out, boolByte(owned.state.cursor.viewport != null)),
        .cursor_viewport_x => writeOut(u16, out, if (owned.state.cursor.viewport) |cursor| cursor.x else 0),
        .cursor_viewport_y => writeOut(u16, out, if (owned.state.cursor.viewport) |cursor| cursor.y else 0),
        .cursor_viewport_wide_tail => writeOut(u8, out, if (owned.state.cursor.viewport) |cursor| boolByte(cursor.wide_tail) else 0),
        .snapshot_seq => writeOut(u64, out, owned.state.snapshot_seq),
        .dirty_generation => writeOut(u64, out, owned.state.dirty_generation),
        .history_count => writeOut(u64, out, owned.state.history_count),
        .scrollback_offset => writeOut(u64, out, owned.state.scrollback_offset),
        .scroll_row => writeOut(u64, out, owned.state.scroll_row),
        .is_alternate_screen => writeOut(u8, out, boolByte(owned.state.is_alternate_screen)),
    };
}

pub fn renderStateGetMulti(state: FfiRenderStateHandle, count: usize, keys: ?[*]const c_int, values: ?[*]?*anyopaque, out_written: ?*usize) callconv(.c) i32 {
    const written = out_written orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    written.* = 0;
    if (count == 0) return @intFromEnum(status.HowlVtCallStatus.ok);
    const keys_slice = if (keys) |ptr| ptr[0..count] else return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const values_slice = if (values) |ptr| ptr[0..count] else return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const result = renderStateGet(state, keys_slice[index], values_slice[index]);
        if (result != @intFromEnum(status.HowlVtCallStatus.ok)) return result;
        written.* = index + 1;
    }
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateSet(state: FfiRenderStateHandle, option: c_int, value: ?*const anyopaque) callconv(.c) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const valid = optionIn(option) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    return switch (valid) {
        .dirty => blk: {
            const dirty_ptr: *const c_int = @ptrCast(@alignCast(value orelse break :blk @intFromEnum(status.HowlVtCallStatus.invalid_argument)));
            owned.state.dirty = dirtyIn(dirty_ptr.*) orelse break :blk @intFromEnum(status.HowlVtCallStatus.invalid_argument);
            break :blk @intFromEnum(status.HowlVtCallStatus.ok);
        },
    };
}

pub fn renderStateColorsGet(state: FfiRenderStateHandle, out_colors: ?*FfiColors) callconv(.c) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const out = out_colors orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    if (out.size < @offsetOf(FfiColors, "background") + @sizeOf(FfiRenderStateRgb8)) return @intFromEnum(status.HowlVtCallStatus.short_buffer);
    const size = out.size;
    out.* = .{ .size = size };
    out.background = rgbOut(owned.state.colors.background);
    if (size >= @offsetOf(FfiColors, "foreground") + @sizeOf(FfiRenderStateRgb8)) out.foreground = rgbOut(owned.state.colors.foreground);
    if (size >= @offsetOf(FfiColors, "cursor") + @sizeOf(FfiRenderStateRgb8)) out.cursor = rgbOut(owned.state.colors.cursor orelse .{});
    if (size >= @offsetOf(FfiColors, "cursor_has_value") + @sizeOf(u8)) out.cursor_has_value = boolByte(owned.state.colors.cursor != null);
    if (size >= @offsetOf(FfiColors, "palette") + @sizeOf([256]FfiRenderStateRgb8)) {
        for (owned.state.colors.palette, 0..) |color, index| out.palette[index] = rgbOut(color);
    }
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateRowIteratorInit(out_iterator: ?*FfiRowIteratorHandle) callconv(.c) i32 {
    const target = out_iterator orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const iterator = std.heap.c_allocator.create(RowIteratorBox) catch return @intFromEnum(status.HowlVtCallStatus.failed);
    iterator.* = .{};
    target.* = @ptrCast(iterator);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateRowIteratorDeinit(iterator: FfiRowIteratorHandle) callconv(.c) void {
    const owned = rowIteratorFromHandle(iterator) orelse return;
    std.heap.c_allocator.destroy(owned);
}

pub fn renderStateRowIteratorNext(iterator: FfiRowIteratorHandle) callconv(.c) u8 {
    const owned = rowIteratorFromHandle(iterator) orelse return 0;
    const state = owned.state orelse return 0;
    if (owned.row < state.rowCount()) {
        owned.has_row = true;
        owned.row += 1;
        return 1;
    }
    owned.has_row = false;
    return 0;
}

fn currentRow(iterator: *RowIteratorBox) ?*render_state.RenderState.Row {
    if (!iterator.has_row) return null;
    const state = iterator.state orelse return null;
    std.debug.assert(iterator.row > 0);
    const index = iterator.row - 1;
    if (index >= state.rows_storage.items.len) return null;
    return &state.rows_storage.items[index];
}

pub fn renderStateRowGet(iterator: FfiRowIteratorHandle, data: c_int, out: ?*anyopaque) callconv(.c) i32 {
    const owned = rowIteratorFromHandle(iterator) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const valid = rowDataIn(data) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const row = currentRow(owned) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    return switch (valid) {
        .invalid => unreachable,
        .dirty => writeOut(u8, out, boolByte(row.dirty)),
        .cells => blk: {
            const cells = std.heap.c_allocator.create(RowCellsBox) catch break :blk @intFromEnum(status.HowlVtCallStatus.failed);
            cells.* = .{ .row = row };
            break :blk writeOut(FfiRowCellsHandle, out, @as(FfiRowCellsHandle, @ptrCast(cells)));
        },
        .selection => rowSelectionOut(out, row.selection),
        .highlight_count => writeOut(u16, out, row.highlight_count),
        .highlight => rowHighlightOut(out, row),
    };
}

pub fn renderStateRowGetMulti(iterator: FfiRowIteratorHandle, count: usize, keys: ?[*]const c_int, values: ?[*]?*anyopaque, out_written: ?*usize) callconv(.c) i32 {
    const written = out_written orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    written.* = 0;
    if (count == 0) return @intFromEnum(status.HowlVtCallStatus.ok);
    const keys_slice = if (keys) |ptr| ptr[0..count] else return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const values_slice = if (values) |ptr| ptr[0..count] else return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const result = renderStateRowGet(iterator, keys_slice[index], values_slice[index]);
        if (result != @intFromEnum(status.HowlVtCallStatus.ok)) return result;
        written.* = index + 1;
    }
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateRowSet(iterator: FfiRowIteratorHandle, option: c_int, value: ?*const anyopaque) callconv(.c) i32 {
    const owned = rowIteratorFromHandle(iterator) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const valid = rowOptionIn(option) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const row = currentRow(owned) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    return switch (valid) {
        .dirty => blk: {
            const dirty_ptr: *const u8 = @ptrCast(@alignCast(value orelse break :blk @intFromEnum(status.HowlVtCallStatus.invalid_argument)));
            row.dirty = dirty_ptr.* != 0;
            break :blk @intFromEnum(status.HowlVtCallStatus.ok);
        },
    };
}

pub fn renderStateRowCellsInit(out_cells: ?*FfiRowCellsHandle) callconv(.c) i32 {
    const target = out_cells orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const cells = std.heap.c_allocator.create(RowCellsBox) catch return @intFromEnum(status.HowlVtCallStatus.failed);
    cells.* = .{};
    target.* = @ptrCast(cells);
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn renderStateRowCellsDeinit(cells: FfiRowCellsHandle) callconv(.c) void {
    const owned = rowCellsFromHandle(cells) orelse return;
    std.heap.c_allocator.destroy(owned);
}

pub fn renderStateRowCellsNext(cells: FfiRowCellsHandle) callconv(.c) u8 {
    const owned = rowCellsFromHandle(cells) orelse return 0;
    const row = owned.row orelse return 0;
    if (owned.col < row.cells.len) {
        owned.has_cell = true;
        owned.col += 1;
        return 1;
    }
    owned.has_cell = false;
    return 0;
}

pub fn renderStateRowCellsSelect(cells: FfiRowCellsHandle, col: u16) callconv(.c) i32 {
    const owned = rowCellsFromHandle(cells) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const row = owned.row orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    if (col < row.cells.len) {
        owned.col = col + 1;
        owned.has_cell = true;
        return @intFromEnum(status.HowlVtCallStatus.ok);
    }
    return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
}

pub fn renderStateRowCellsGet(cells: FfiRowCellsHandle, data: c_int, out: ?*anyopaque) callconv(.c) i32 {
    const owned = rowCellsFromHandle(cells) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    const valid = rowCellsDataIn(data) orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const row = owned.row orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    if (!owned.has_cell) return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    std.debug.assert(owned.col > 0);
    const index = owned.col - 1;
    if (index >= row.cells.len) return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const cell = row.cells[index];
    return switch (valid) {
        .invalid => unreachable,
        .cell => writeOut(FfiRenderStateCell, out, cellOut(cell)),
        .selected => writeOut(u8, out, boolByte(if (row.selection) |selection| index >= selection.start_col and index < selection.end_col else false)),
        .highlighted => writeOut(u8, out, boolByte(cellHighlighted(row, index))),
    };
}

fn cellHighlighted(row: *const render_state.RenderState.Row, col: u16) bool {
    for (row.highlights[0..row.highlight_count]) |highlight| {
        if (col >= highlight.start_col and col < highlight.end_col) return true;
    }
    return false;
}

pub fn renderStateRowCellsGetMulti(cells: FfiRowCellsHandle, count: usize, keys: ?[*]const c_int, values: ?[*]?*anyopaque, out_written: ?*usize) callconv(.c) i32 {
    const written = out_written orelse return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    written.* = 0;
    if (count == 0) return @intFromEnum(status.HowlVtCallStatus.ok);
    const keys_slice = if (keys) |ptr| ptr[0..count] else return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    const values_slice = if (values) |ptr| ptr[0..count] else return @intFromEnum(status.HowlVtCallStatus.invalid_argument);
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const result = renderStateRowCellsGet(cells, keys_slice[index], values_slice[index]);
        if (result != @intFromEnum(status.HowlVtCallStatus.ok)) return result;
        written.* = index + 1;
    }
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

pub fn testRenderStateClearDirty(state: FfiRenderStateHandle) i32 {
    const owned = renderStateFromHandle(state) orelse return @intFromEnum(status.HowlVtCallStatus.missing_handle);
    owned.state.dirty = .false;
    for (owned.state.rows_storage.items) |*row| row.dirty = false;
    return @intFromEnum(status.HowlVtCallStatus.ok);
}

test "render_state ffi lifecycle null safety and missing handles" {
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), renderStateInit(null));
    renderStateDeinit(null);
    renderStateRowIteratorDeinit(null);
    renderStateRowCellsDeinit(null);
    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    try std.testing.expect(state != null);
    var dirty: c_int = @intFromEnum(FfiDirty.false);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.missing_handle)), renderStateGet(null, @intFromEnum(FfiData.dirty), &dirty));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.missing_handle)), renderStateSet(null, @intFromEnum(FfiOption.dirty), &dirty));
}

test "render_state ffi invalid enum status" {
    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    var out: u16 = 0;
    const invalid_data: c_int = 9999;
    const invalid_dirty: c_int = 9999;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), renderStateGet(state, invalid_data, &out));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), renderStateSet(state, @intFromEnum(FfiOption.dirty), &invalid_dirty));
}

test "render_state ffi dirty get set" {
    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    var dirty: c_int = @intFromEnum(FfiDirty.full);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateSet(state, @intFromEnum(FfiOption.dirty), &dirty));
    dirty = @intFromEnum(FfiDirty.false);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.dirty), &dirty));
    try std.testing.expectEqual(@as(c_int, @intFromEnum(FfiDirty.full)), dirty);
}

test "render_state ffi get multi reports first failure" {
    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    var cols: u16 = 99;
    var rows: u16 = 99;
    var written: usize = 99;
    var keys = [_]c_int{ @intFromEnum(FfiData.cols), @intFromEnum(FfiData.rows) };
    var values = [_]?*anyopaque{ &cols, &rows };
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGetMulti(state, keys.len, &keys, &values, &written));
    try std.testing.expectEqual(@as(usize, 2), written);
    try std.testing.expectEqual(@as(u16, 0), cols);
    try std.testing.expectEqual(@as(u16, 0), rows);
    const invalid_data: c_int = 9999;
    keys = [_]c_int{ @intFromEnum(FfiData.cols), invalid_data };
    cols = 99;
    written = 99;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.invalid_argument)), renderStateGetMulti(state, keys.len, &keys, &values, &written));
    try std.testing.expectEqual(@as(usize, 1), written);
    try std.testing.expectEqual(@as(u16, 0), cols);
}

test "render_state ffi colors reject undersized struct" {
    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    var colors = FfiColors{ .size = @offsetOf(FfiColors, "background") };
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.short_buffer)), renderStateColorsGet(state, &colors));
}

test "render_state ffi row iterator empty before update" {
    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    var iterator: FfiRowIteratorHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.row_iterator), @ptrCast(&iterator)));
    defer renderStateRowIteratorDeinit(iterator);
    try std.testing.expect(iterator != null);
    try std.testing.expectEqual(@as(u8, 0), renderStateRowIteratorNext(iterator));
}

test "render_state ffi update exposes row and cell iteration" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 8);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), lifecycle.terminalFeed(vt_handle, "abcd".ptr, 4).status);

    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateUpdate(state, vt_handle, 0));

    var rows: u16 = 0;
    var cols: u16 = 0;
    var dirty: c_int = 0;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.rows), &rows));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.cols), &cols));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.dirty), &dirty));
    try std.testing.expectEqual(@as(u16, 2), rows);
    try std.testing.expectEqual(@as(u16, 4), cols);
    try std.testing.expectEqual(@as(c_int, @intFromEnum(FfiDirty.full)), dirty);

    var iterator: FfiRowIteratorHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.row_iterator), @ptrCast(&iterator)));
    defer renderStateRowIteratorDeinit(iterator);

    var row_count: u16 = 0;
    var cell_count: u16 = 0;
    while (renderStateRowIteratorNext(iterator) != 0) : (row_count += 1) {
        var cells: FfiRowCellsHandle = null;
        try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator, @intFromEnum(FfiRowData.cells), @ptrCast(&cells)));
        defer renderStateRowCellsDeinit(cells);
        while (renderStateRowCellsNext(cells) != 0) : (cell_count += 1) {
            var cell: FfiRenderStateCell = .{};
            try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(cells, @intFromEnum(FfiRowCellsData.cell), &cell));
            if (cell_count == 0) try std.testing.expectEqual(@as(u32, 'a'), cell.codepoint);
            if (cell_count == 3) try std.testing.expectEqual(@as(u32, 'd'), cell.codepoint);
        }
    }
    try std.testing.expectEqual(rows, row_count);
    try std.testing.expectEqual(@as(u16, rows * cols), cell_count);
}

test "render_state ffi cells expose full copied surface facts" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(1, 4, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);
    const source = "\x1b]8;;https://example.com\x07\x1b[1;2;3;4;5;7;8;9;38;2;1;2;3;48;5;200;58;2;4;5;6mA\xcc\x81\x1b]8;;\x07";
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), lifecycle.terminalFeed(vt_handle, source.ptr, source.len).status);

    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateUpdate(state, vt_handle, 0));

    var iterator: FfiRowIteratorHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.row_iterator), @ptrCast(&iterator)));
    defer renderStateRowIteratorDeinit(iterator);
    try std.testing.expectEqual(@as(u8, 1), renderStateRowIteratorNext(iterator));

    var cells: FfiRowCellsHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator, @intFromEnum(FfiRowData.cells), @ptrCast(&cells)));
    defer renderStateRowCellsDeinit(cells);
    try std.testing.expectEqual(@as(u8, 1), renderStateRowCellsNext(cells));

    var cell: FfiRenderStateCell = .{};
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(cells, @intFromEnum(FfiRowCellsData.cell), &cell));
    try std.testing.expectEqual(@as(u32, 'A'), cell.codepoint);
    try std.testing.expectEqual(@as(u8, 1), cell.combining_len);
    try std.testing.expectEqual(@as(u32, 0x0301), cell.combining[0]);
    try std.testing.expectEqual(FfiRenderStateColor{ .kind = 2, .value = 0x010203 }, cell.fg_color);
    try std.testing.expectEqual(FfiRenderStateColor{ .kind = 1, .value = 200 }, cell.bg_color);
    try std.testing.expectEqual(FfiRenderStateColor{ .kind = 2, .value = 0x040506 }, cell.underline_color);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.bold);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.dim);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.italic);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.underline);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.underline_color_set);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.blink);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.inverse);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.invisible);
    try std.testing.expectEqual(@as(u8, 1), cell.attrs.strikethrough);
    try std.testing.expect(cell.link_id != 0);
}

test "render_state ffi row selection and selected cell reads" {
    const lifecycle = @import("lifecycle.zig");
    const selection = @import("selection.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), lifecycle.terminalFeed(vt_handle, "abcd".ptr, 4).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection.terminalStartSelection(vt_handle, 0, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection.terminalUpdateSelection(vt_handle, 0, 2));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), selection.terminalFinishSelection(vt_handle));

    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateUpdate(state, vt_handle, 0));

    var iterator: FfiRowIteratorHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.row_iterator), @ptrCast(&iterator)));
    defer renderStateRowIteratorDeinit(iterator);
    try std.testing.expectEqual(@as(u8, 1), renderStateRowIteratorNext(iterator));

    var short_selection = FfiRowSelection{ .size = @offsetOf(FfiRowSelection, "start_col") };
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.short_buffer)), renderStateRowGet(iterator, @intFromEnum(FfiRowData.selection), &short_selection));
    var row_selection = FfiRowSelection{};
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator, @intFromEnum(FfiRowData.selection), &row_selection));
    try std.testing.expectEqual(@as(u16, 1), row_selection.start_col);
    try std.testing.expectEqual(@as(u16, 3), row_selection.end_col);

    var cells: FfiRowCellsHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator, @intFromEnum(FfiRowData.cells), @ptrCast(&cells)));
    defer renderStateRowCellsDeinit(cells);
    var selected: u8 = 99;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsSelect(cells, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(cells, @intFromEnum(FfiRowCellsData.selected), &selected));
    try std.testing.expectEqual(@as(u8, 0), selected);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsSelect(cells, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(cells, @intFromEnum(FfiRowCellsData.selected), &selected));
    try std.testing.expectEqual(@as(u8, 1), selected);

    try std.testing.expectEqual(@as(u8, 1), renderStateRowIteratorNext(iterator));
    row_selection = .{};
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.no_value)), renderStateRowGet(iterator, @intFromEnum(FfiRowData.selection), &row_selection));
}

test "render_state ffi highlight reads and highlighted cells" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(2, 4, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);
    const source = "\x1b]8;;https://example.com\x07abcdef\x1b]8;;\x07";
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), lifecycle.terminalFeed(vt_handle, source.ptr, source.len).status);

    var state: FfiRenderStateHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateInit(&state));
    defer renderStateDeinit(state);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateUpdate(state, vt_handle, 0));
    const owned = renderStateFromHandle(state).?;
    owned.state.dirty = .false;
    for (owned.state.rows_storage.items) |*row| row.dirty = false;

    var iterator_before: FfiRowIteratorHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.row_iterator), @ptrCast(&iterator_before)));
    defer renderStateRowIteratorDeinit(iterator_before);
    try std.testing.expectEqual(@as(u8, 1), renderStateRowIteratorNext(iterator_before));
    var count: u16 = 99;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator_before, @intFromEnum(FfiRowData.highlight_count), &count));
    try std.testing.expectEqual(@as(u16, 0), count);

    owned.state.updateHighlightsForHyperlink(1, 0, 1, .straight);
    try std.testing.expectEqual(render_state.RenderState.Dirty.partial, owned.state.dirty);

    var iterator_after: FfiRowIteratorHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateGet(state, @intFromEnum(FfiData.row_iterator), @ptrCast(&iterator_after)));
    defer renderStateRowIteratorDeinit(iterator_after);
    try std.testing.expectEqual(@as(u8, 1), renderStateRowIteratorNext(iterator_after));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator_after, @intFromEnum(FfiRowData.highlight_count), &count));
    try std.testing.expectEqual(@as(u16, 1), count);
    var highlight = FfiRowHighlight{ .index = 0 };
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator_after, @intFromEnum(FfiRowData.highlight), &highlight));
    try std.testing.expectEqual(@as(u8, 1), highlight.tag);
    try std.testing.expectEqual(@as(u16, 0), highlight.start_col);
    try std.testing.expectEqual(@as(u16, 4), highlight.end_col);

    var first_row_cells: FfiRowCellsHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator_after, @intFromEnum(FfiRowData.cells), @ptrCast(&first_row_cells)));
    defer renderStateRowCellsDeinit(first_row_cells);
    var highlighted: u8 = 99;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsSelect(first_row_cells, 3));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(first_row_cells, @intFromEnum(FfiRowCellsData.highlighted), &highlighted));
    try std.testing.expectEqual(@as(u8, 1), highlighted);

    try std.testing.expectEqual(@as(u8, 1), renderStateRowIteratorNext(iterator_after));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator_after, @intFromEnum(FfiRowData.highlight), &highlight));
    try std.testing.expectEqual(@as(u16, 0), highlight.start_col);
    try std.testing.expectEqual(@as(u16, 2), highlight.end_col);
    try std.testing.expect(owned.state.rows_storage.items[0].dirty);
    try std.testing.expect(owned.state.rows_storage.items[1].dirty);
    var second_row_cells: FfiRowCellsHandle = null;
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowGet(iterator_after, @intFromEnum(FfiRowData.cells), @ptrCast(&second_row_cells)));
    defer renderStateRowCellsDeinit(second_row_cells);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsSelect(second_row_cells, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(second_row_cells, @intFromEnum(FfiRowCellsData.highlighted), &highlighted));
    try std.testing.expectEqual(@as(u8, 1), highlighted);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsSelect(second_row_cells, 2));
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), renderStateRowCellsGet(second_row_cells, @intFromEnum(FfiRowCellsData.highlighted), &highlighted));
    try std.testing.expectEqual(@as(u8, 0), highlighted);
}
