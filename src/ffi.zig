const std = @import("std");
const screen = @import("screen.zig");
const input = @import("input.zig");
const host_state = @import("host/state.zig");
const screen_set = @import("screen_set.zig");
const terminal = @import("terminal.zig");

pub const HowlVtTerminal = opaque {};
pub const VtHandle = ?*HowlVtTerminal;

pub const HowlVtCallStatus = enum(c_int) {
    ok = 0,
    missing_handle = -1,
    invalid_argument = -2,
    failed = -3,
    short_buffer = -4,
    limit_reached = -5,
};

pub const FfiColor = extern struct {
    kind: u8 = 0,
    value: u32 = 0,
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
};

pub const FfiSurfaceCell = extern struct {
    codepoint: u32 = 0,
    flags: FfiSurfaceCellFlags = .{},
    fg_color: FfiColor = .{},
    bg_color: FfiColor = .{},
    underline_color: FfiColor = .{},
    underline_style: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u8 = 0,
    reserved2: u8 = 0,
    attrs: FfiSurfaceCellAttrs = .{},
    link_id: u32 = 0,
};

pub const FfiBytesResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    written: u64 = 0,
    needed: u64 = 0,
};

pub const FfiFeedResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    state_changed: u8 = 0,
    title_changed: u8 = 0,
    reserved0: u16 = 0,
};

pub const FfiSurfaceCellSpan = extern struct {
    ptr: [*c]const FfiSurfaceCell,
    len: usize,
};

pub const FfiByteSpan = extern struct {
    ptr: [*c]const u8,
    len: usize,
};

pub const FfiU16Span = extern struct {
    ptr: [*c]const u16,
    len: usize,
};

pub const FfiCursor = extern struct {
    row: u16,
    col: u16,
    visible: u8,
    shape: u8,
};

pub const FfiSurface = extern struct {
    surface_cells: FfiSurfaceCellSpan,
    cols: u16,
    rows: u16,
    scroll_row: u64,
    is_alternate_screen: u8,
    full_damage: u8,
    scroll_up_rows: u16,
    dirty_rows: FfiByteSpan,
    dirty_cols_start: FfiU16Span,
    dirty_cols_end: FfiU16Span,
    cursor: FfiCursor,
};

pub const FfiSurfaceResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    history_count: u64 = 0,
    scrollback_offset: u64 = 0,
    dirty_needed: u64 = 0,
    dirty_generation: u64 = 0,
    source: FfiSurface = .{
        .surface_cells = .{ .ptr = null, .len = 0 },
        .cols = 0,
        .rows = 0,
        .scroll_row = 0,
        .is_alternate_screen = 0,
        .full_damage = 0,
        .scroll_up_rows = 0,
        .dirty_rows = .{ .ptr = null, .len = 0 },
        .dirty_cols_start = .{ .ptr = null, .len = 0 },
        .dirty_cols_end = .{ .ptr = null, .len = 0 },
        .cursor = .{ .row = 0, .col = 0, .visible = 0, .shape = 0 },
    },
};

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

fn vtFromHandle(handle: VtHandle) ?*terminal.Terminal {
    const owned = handle orelse return null;
    return @ptrCast(@alignCast(owned));
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

fn colorOut(value: screen.Screen.Color) FfiColor {
    return .{ .kind = 2, .value = (@as(u32, value.r) << 16) | (@as(u32, value.g) << 8) | @as(u32, value.b) };
}

fn cellOut(value: screen.Screen.Cell) FfiSurfaceCell {
    return .{
        .codepoint = value.codepoint,
        .flags = .{ .continuation = boolByte(screen.Screen.isCellContinuation(value)) },
        .fg_color = colorOut(value.attrs.fg),
        .bg_color = colorOut(value.attrs.bg),
        .underline_color = colorOut(value.attrs.underline_color),
        .underline_style = @intFromEnum(value.attrs.underline_style),
        .attrs = .{
            .bold = boolByte(value.attrs.bold),
            .underline = boolByte(value.attrs.underline),
            .underline_color_set = boolByte(value.attrs.underline_color.a != 0),
            .blink = boolByte(value.attrs.blink or value.attrs.blink_fast),
            .inverse = boolByte(value.attrs.reverse),
        },
        .link_id = value.attrs.link_id,
    };
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

fn surfaceResult(
    view: screen_set.View,
    dirty_generation: u64,
    dirty_needed: u16,
    cells_ptr: ?[*]FfiSurfaceCell,
    dirty_rows_ptr: ?[*]u8,
    cols_start_ptr: ?[*]u16,
    cols_end_ptr: ?[*]u16,
    full_damage: u8,
    scroll_up_rows: u16,
) FfiSurfaceResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .history_count = view.history_count,
        .scrollback_offset = view.scrollback_offset,
        .dirty_needed = dirty_needed,
        .dirty_generation = dirty_generation,
        .source = .{
            .surface_cells = .{ .ptr = cells_ptr, .len = @intCast(@as(u32, view.rows) * view.cols) },
            .cols = view.cols,
            .rows = view.rows,
            .scroll_row = view.start,
            .is_alternate_screen = boolByte(view.is_alternate_screen),
            .full_damage = full_damage,
            .scroll_up_rows = scroll_up_rows,
            .dirty_rows = .{ .ptr = dirty_rows_ptr, .len = view.rows },
            .dirty_cols_start = .{ .ptr = cols_start_ptr, .len = @intCast(dirty_needed) },
            .dirty_cols_end = .{ .ptr = cols_end_ptr, .len = @intCast(dirty_needed) },
            .cursor = .{ .row = view.cursor_row, .col = view.cursor_col, .visible = boolByte(view.cursor_visible), .shape = @intFromEnum(view.cursor_shape) },
        },
    };
}

fn copySurfaceCells(cells_out: []FfiSurfaceCell, view: screen_set.View) void {
    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            const idx = @as(usize, row) * @as(usize, view.cols) + @as(usize, col);
            cells_out[idx] = cellOut(view.cellInfoAt(row, col));
        }
    }
}

fn copyDirtyOutput(dirty_rows_out: []u8, cols_start: []u16, cols_end: []u16, dirty: ?screen.Screen.DirtyRows) void {
    @memset(dirty_rows_out, 0);
    if (dirty) |value| {
        @memcpy(cols_start, value.dirty_cols_start[@intCast(value.start_row)..@intCast(value.end_row + 1)]);
        @memcpy(cols_end, value.dirty_cols_end[@intCast(value.start_row)..@intCast(value.end_row + 1)]);
        var dirty_row = value.start_row;
        while (dirty_row <= value.end_row and dirty_row < dirty_rows_out.len) : (dirty_row += 1) {
            dirty_rows_out[dirty_row] = 1;
        }
    }
}

pub fn terminalInit(rows: u16, cols: u16, history_capacity: u16) callconv(.c) VtHandle {
    const owned = std.heap.c_allocator.create(terminal.Terminal) catch return null;
    owned.* = terminal.Terminal.initWithCellsAndHistory(std.heap.c_allocator, rows, cols, history_capacity) catch {
        std.heap.c_allocator.destroy(owned);
        return null;
    };
    return @ptrCast(owned);
}

pub fn terminalDeinit(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    owned.deinit();
    std.heap.c_allocator.destroy(owned);
}

pub fn terminalFeed(handle: VtHandle, ptr: ?[*]const u8, len: usize) callconv(.c) FfiFeedResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const bytes = bytesIn(ptr, len) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    if (bytes.len == 0) return .{ .status = @intFromEnum(HowlVtCallStatus.ok) };

    var stream = owned.vtStream();
    const summary = stream.nextSliceSummary(bytes) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.ParsedEventLimit, error.StringControlLimit => HowlVtCallStatus.limit_reached,
            error.OutOfMemory => HowlVtCallStatus.failed,
        }) };
    };
    if (summary.state_changed) owned.dirty_generation +%= 1;
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .state_changed = boolByte(summary.state_changed),
        .title_changed = boolByte(summary.latest_title != null),
    };
}

pub fn terminalCopyTitle(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return copyBytes(out, owned.host.current_title orelse &.{});
}

pub fn terminalResize(handle: VtHandle, rows: u16, cols: u16) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.screen_state.resize(owned.allocator, rows, cols) catch return @intFromEnum(HowlVtCallStatus.failed);
    owned.screen_state.activeSelection().clearIfInvalidatedByGrid(owned.screen_state.activeConst());
    owned.dirty_generation +%= 1;
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalAckSurface(handle: VtHandle, dirty_generation: u64) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    if (dirty_generation == 0) return @intFromEnum(HowlVtCallStatus.invalid_argument);
    if (owned.dirty_generation == dirty_generation) {
        screen_set.clearDirtyRows(&owned.screen_state);
    }
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalCopySurface(handle: VtHandle, scrollback_offset: u64, cells_ptr: ?[*]FfiSurfaceCell, cells_cap: usize, dirty_rows_ptr: ?[*]u8, dirty_rows_cap: usize, cols_start_ptr: ?[*]u16, cols_start_cap: usize, cols_end_ptr: ?[*]u16, cols_end_cap: usize, full_damage: u8, scroll_up_rows: u16) callconv(.c) FfiSurfaceResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const history_count: u32 = if (owned.screen_state.alt_active) 0 else owned.screen_state.activeConst().historyCount();
    const offset: u32 = @intCast(@min(scrollback_offset, @as(u64, history_count)));
    const view = screen_set.visibleView(&owned.screen_state, .{ .scrollback_offset = offset });
    const dirty = screen_set.peekDirtyRows(&owned.screen_state);
    const cell_count = @as(usize, view.rows) * @as(usize, view.cols);
    const dirty_needed: usize = if (dirty) |value| @as(usize, value.end_row) - @as(usize, value.start_row) + 1 else 0;
    var result = surfaceResult(view, owned.dirty_generation, @intCast(dirty_needed), cells_ptr, dirty_rows_ptr, cols_start_ptr, cols_end_ptr, full_damage, scroll_up_rows);

    if (cells_cap < cell_count or dirty_rows_cap < view.rows or cols_start_cap < dirty_needed or cols_end_cap < dirty_needed) {
        result.status = @intFromEnum(HowlVtCallStatus.short_buffer);
        return result;
    }

    const cells_out = if (cells_ptr) |ptr| ptr[0..cells_cap] else {
        result.status = @intFromEnum(HowlVtCallStatus.invalid_argument);
        return result;
    };
    const dirty_rows_out = if (dirty_rows_ptr) |ptr| ptr[0..dirty_rows_cap] else {
        result.status = @intFromEnum(HowlVtCallStatus.invalid_argument);
        return result;
    };
    var cols_start: []u16 = &.{};
    var cols_end: []u16 = &.{};
    if (dirty_needed != 0) {
        cols_start = if (cols_start_ptr) |ptr| ptr[0..cols_start_cap] else {
            result.status = @intFromEnum(HowlVtCallStatus.invalid_argument);
            return result;
        };
        cols_end = if (cols_end_ptr) |ptr| ptr[0..cols_end_cap] else {
            result.status = @intFromEnum(HowlVtCallStatus.invalid_argument);
            return result;
        };
    }

    copySurfaceCells(cells_out, view);
    copyDirtyOutput(dirty_rows_out[0..view.rows], cols_start, cols_end, dirty);

    return result;
}

pub fn terminalCopyPendingOutput(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return copyBytes(out, host_state.pendingOutput(owned));
}

pub fn terminalClearPendingOutput(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    host_state.clearPendingOutput(owned);
}

pub fn terminalDrainPendingClipboard(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const raw = host_state.pendingClipboardSet(owned) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.ok) };
    const result = decodeClipboardBytes(raw, out);
    if (result.status == @intFromEnum(HowlVtCallStatus.ok)) host_state.clearPendingClipboardSet(owned);
    return result;
}

pub fn terminalEncodeKey(handle: VtHandle, key: u32, mods: u8, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    var scratch: input.Scratch = .{};
    return copyBytes(out, input.encodeKey(owned, &scratch, key, mods));
}

pub fn terminalEncodeFocus(handle: VtHandle, focused: u8, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    var scratch: input.Scratch = .{};
    const bytes = if (focused != 0) input.encodeFocusIn(owned, &scratch) else input.encodeFocusOut(owned, &scratch);
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
    var scratch: input.Scratch = .{};
    return copyBytes(out, input.encodeMouse(owned, &scratch, event));
}

pub fn terminalEncodePaste(handle: VtHandle, text_ptr: ?[*]const u8, text_len: usize, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const text = bytesIn(text_ptr, text_len) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    var scratch: input.Scratch = .{};
    const start = input.encodePasteStart(owned, &scratch);
    const end = input.encodePasteEnd(owned, &scratch);
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

test "vt ffi runtime surface covers feed encode and surface" {
    const handle = terminalInit(2, 4, 8);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const fed = terminalFeed(handle, "abc".ptr, 3);
    try std.testing.expectEqual(@as(i32, 0), fed.status);
    try std.testing.expectEqual(@as(u8, 1), fed.state_changed);

    var key_buf: [16]u8 = undefined;
    const key = terminalEncodeKey(handle, input.key_enter, input.mod_none, key_buf[0..].ptr, key_buf.len);
    try std.testing.expectEqual(@as(i32, 0), key.status);
    try std.testing.expectEqualStrings("\r", key_buf[0..@intCast(key.written)]);

    var cells: [8]FfiSurfaceCell = undefined;
    const source = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, null, 0, null, 0, null, 0, 0, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.short_buffer)), source.status);
    try std.testing.expectEqual(@as(u16, 2), source.source.rows);
    try std.testing.expectEqual(@as(u16, 4), source.source.cols);
}

test "vt ffi copy surface clamps oversized scrollback offset" {
    const handle = terminalInit(2, 2, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const fed = terminalFeed(handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, 0), fed.status);

    const source = terminalCopySurface(handle, std.math.maxInt(u64), null, 0, null, 0, null, 0, null, 0, 0, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.short_buffer)), source.status);
    try std.testing.expectEqual(source.history_count, source.scrollback_offset);
}

test "vt ffi feed reports and copies title" {
    const handle = terminalInit(2, 4, 8);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const seq = "\x1b]0;My Title\x07";
    const fed = terminalFeed(handle, seq.ptr, seq.len);
    try std.testing.expectEqual(@as(i32, 0), fed.status);
    try std.testing.expectEqual(@as(u8, 1), fed.title_changed);

    var title_buf: [32]u8 = undefined;
    const title = terminalCopyTitle(handle, title_buf[0..].ptr, title_buf.len);
    try std.testing.expectEqual(@as(i32, 0), title.status);
    try std.testing.expectEqualStrings("My Title", title_buf[0..@intCast(title.written)]);
}
