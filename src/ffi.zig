const std = @import("std");
const screen = @import("screen.zig");
const input = @import("input.zig");
const selection = @import("selection.zig");
const host_state = @import("host/state.zig");
const kitty_types = @import("kitty/types.zig");
const screen_set = @import("screen_set.zig");
const terminal = @import("terminal.zig");

pub const HowlVtTerminal = opaque {};
pub const VtHandle = ?*HowlVtTerminal;

comptime {
    std.debug.assert(host_state.title_max_bytes == 1024);
    std.debug.assert(host_state.pending_output_max_bytes == 1024 * 1024);
    std.debug.assert(host_state.retained_payload_max_bytes == 1024 * 1024);
    std.debug.assert(@sizeOf(input.Scratch) == 64);
    std.debug.assert(@sizeOf(FfiRgb8) == 3);
    std.debug.assert(@sizeOf(FfiRenderColorState) == 777);
    std.debug.assert(@sizeOf(FfiGraphicsPlacement) == 104);
    std.debug.assert(@offsetOf(FfiGraphicsPlacement, "flags") == 88);
    std.debug.assert(@offsetOf(FfiGraphicsPlacement, "render_order_key") == 96);
}

pub const HowlVtCallStatus = enum(c_int) {
    ok = 0,
    missing_handle = -1,
    invalid_argument = -2,
    failed = -3,
    short_buffer = -4,
    limit_reached = -5,
};

pub const HOWL_VT_GRAPHICS_PLACEMENT_GENERATED_PLACEHOLDER: u32 = 1;

const kitty_placeholder_codepoint: u32 = 0x10EEEE;

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

pub const FfiRuntimeObligation = extern struct {
    pending_now: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    deadline_ns: u64 = 0,
};

pub const FfiRuntimeObligationResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    obligation: FfiRuntimeObligation = .{},
};

pub const FfiRuntimeProgressResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    state_changed: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    obligation: FfiRuntimeObligation = .{},
};

pub const FfiSurfaceCellSpan = extern struct {
    ptr: [*c]const FfiSurfaceCell,
    // The shipped C ABI owns architecture-sized span lengths at this boundary.
    len: usize,
};

pub const FfiByteSpan = extern struct {
    ptr: [*c]const u8,
    // The shipped C ABI owns architecture-sized span lengths at this boundary.
    len: usize,
};

pub const FfiU16Span = extern struct {
    ptr: [*c]const u16,
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

pub const FfiCursorStyle = extern struct {
    shape: u8 = 0,
    blink: u8 = 1,
};

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
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    selection: FfiSelection = .{},
};

pub const FfiTerminalInitOptions = extern struct {
    default_cursor_style: FfiCursorStyle = .{},
};

pub const FfiSurface = extern struct {
    surface_cells: FfiSurfaceCellSpan,
    cols: u16,
    rows: u16,
    scroll_row: u64,
    is_alternate_screen: u8,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    dirty_rows: FfiByteSpan,
    dirty_cols_start: FfiU16Span,
    dirty_cols_end: FfiU16Span,
    cursor: FfiCursor,
    colors: FfiRenderColorState = .{},
    selection: FfiSelection = .{},
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
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    meta: FfiVisibleMeta = .{},
};

pub const FfiGraphicsMeta = extern struct {
    image_count: u32 = 0,
    placement_count: u32 = 0,
    virtual_placement_count: u32 = 0,
    placeholder_run_count: u32 = 0,
    is_alternate_screen: u8 = 0,
    reserved0: u8 = 0,
    publication_seq: u64 = 0,
    dirty_generation: u64 = 0,
};

pub const FfiGraphicsMetaResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    meta: FfiGraphicsMeta = .{},
};

pub const FfiGraphicsRowAnchor = extern struct {
    kind: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    value: u32 = 0,
};

pub const FfiGraphicsImage = extern struct {
    image_id: u32 = 0,
    image_ref_id: u32 = 0,
    image_number: u32 = 0,
    format: u16 = 0,
    reserved0: u16 = 0,
    width: u32 = 0,
    height: u32 = 0,
    payload_len: u64 = 0,
};

pub const FfiGraphicsImageResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    image: FfiGraphicsImage = .{},
};

pub const FfiGraphicsPlacement = extern struct {
    image_id: u32 = 0,
    placement_id: u32 = 0,
    z_index: i32 = 0,
    anchor: FfiGraphicsRowAnchor = .{},
    anchor_col: u16 = 0,
    reserved0: u16 = 0,
    source_x: u32 = 0,
    source_y: u32 = 0,
    source_width: u32 = 0,
    source_height: u32 = 0,
    cell_x_offset: u32 = 0,
    cell_y_offset: u32 = 0,
    columns: u32 = 0,
    rows: u32 = 0,
    dest_left_cell_px: u32 = 0,
    dest_top_cell_px: u32 = 0,
    dest_right_cell_px: u32 = 0,
    dest_bottom_cell_px: u32 = 0,
    dest_grid_columns: u32 = 0,
    dest_grid_rows: u32 = 0,
    effective_columns: u32 = 0,
    effective_rows: u32 = 0,
    flags: u32 = 0,
    render_order_key: u64 = 0,
};

pub const FfiGraphicsPlacementResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    placement: FfiGraphicsPlacement = .{},
};

pub const FfiGraphicsVirtualPlacement = extern struct {
    image_id: u32 = 0,
    placement_id: u32 = 0,
    source_x: u32 = 0,
    source_y: u32 = 0,
    source_width: u32 = 0,
    source_height: u32 = 0,
    columns: u32 = 0,
    rows: u32 = 0,
};

pub const FfiGraphicsVirtualPlacementResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    placement: FfiGraphicsVirtualPlacement = .{},
};

pub const FfiGraphicsPlaceholderRun = extern struct {
    image_id: u32 = 0,
    placement_id: u32 = 0,
    virtual_placement_index: u32 = 0,
    run_order: u32 = 0,
    cell_row: u16 = 0,
    cell_col: u16 = 0,
    reserved0: u32 = 0,
    image_row: u32 = 0,
    image_col: u32 = 0,
    columns: u32 = 0,
};

pub const FfiGraphicsPlaceholderRunResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
    run: FfiGraphicsPlaceholderRun = .{},
};

pub const FfiSurfaceResult = extern struct {
    status: i32 = @intFromEnum(HowlVtCallStatus.failed),
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

fn vtFromHandle(handle: VtHandle) ?*terminal.Terminal {
    const owned = handle orelse return null;
    return @ptrCast(@alignCast(owned));
}

fn bytesIn(ptr: ?[*]const u8, len: usize) ?[]const u8 {
    // C callers provide architecture-sized byte counts; translate immediately to a Zig slice.
    if (ptr == null) {
        if (len != 0) return null;
        return &.{};
    }
    return ptr.?[0..len];
}

fn bytesOut(ptr: ?[*]u8, len: usize) ?[]u8 {
    // C callers provide architecture-sized buffer capacities; translate immediately to a Zig slice.
    if (ptr == null) {
        if (len != 0) return null;
        return &.{};
    }
    return ptr.?[0..len];
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
    var out = FfiSurfaceCell{
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
    if (value.codepoint == kitty_placeholder_codepoint and out.flags.continuation == 0) {
        out.codepoint = ' ';
        out.combining_len = 0;
        out.combining = [_]u32{0} ** 3;
        out.underline_color = .{};
        out.underline_style = 0;
        out.attrs.underline = 0;
        out.attrs.underline_color_set = 0;
        out.attrs.strikethrough = 0;
    }
    return out;
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

fn cursorStyleIn(value: FfiCursorStyle) ?screen.Screen.CursorStyle {
    const shape: screen.Screen.CursorShape = switch (value.shape) {
        0 => .block,
        1 => .underline,
        2 => .bar,
        else => return null,
    };
    return .{ .shape = shape, .blink = value.blink != 0 };
}

fn selectionOut(value: ?selection.TerminalSelection) FfiSelection {
    const selected = value orelse return .{};
    return .{
        .active = boolByte(selected.active),
        .selecting = boolByte(selected.selecting),
        .start = .{ .row = selected.start.row, .col = selected.start.col },
        .end = .{ .row = selected.end.row, .col = selected.end.col },
    };
}

fn selectionResult(value: ?selection.TerminalSelection) FfiSelectionResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .selection = selectionOut(value),
    };
}

fn surfaceResult(
    vt: *terminal.Terminal,
    view: screen_set.View,
    selected: ?selection.TerminalSelection,
    snapshot_seq: u64,
    dirty_generation: u64,
    cells_ptr: ?[*]FfiSurfaceCell,
    dirty_rows_ptr: ?[*]u8,
    cols_start_ptr: ?[*]u16,
    cols_end_ptr: ?[*]u16,
) FfiSurfaceResult {
    const colors = renderColorStateOut(host_state.terminalColorState(vt));
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
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
            .cursor = .{ .row = view.cursor_row, .col = view.cursor_col, .visible = boolByte(view.cursor_visible), .shape = @intFromEnum(view.cursor_shape), .blink = boolByte(view.cursor_blink) },
            .colors = colors,
            .selection = selectionOut(selected),
        },
    };
}

fn visibleMetaResult(meta: terminal.Terminal.VisibleMeta) FfiVisibleMetaResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
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

fn runtimeObligationOut(value: terminal.Terminal.RuntimeObligation) FfiRuntimeObligation {
    return .{
        .pending_now = boolByte(value.pending_now),
        .deadline_ns = value.deadline_ns,
    };
}

fn runtimeObligationResult(value: terminal.Terminal.RuntimeObligation) FfiRuntimeObligationResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .obligation = runtimeObligationOut(value),
    };
}

fn runtimeProgressResult(value: terminal.Terminal.RuntimeProgress) FfiRuntimeProgressResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .state_changed = boolByte(value.state_changed),
        .obligation = runtimeObligationOut(value.obligation),
    };
}

fn graphicsMetaResult(meta: terminal.Terminal.GraphicsMeta) FfiGraphicsMetaResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .meta = .{
            .image_count = meta.image_count,
            .placement_count = meta.placement_count,
            .virtual_placement_count = meta.virtual_placement_count,
            .placeholder_run_count = meta.placeholder_run_count,
            .is_alternate_screen = boolByte(meta.is_alternate_screen),
            .publication_seq = meta.publication_seq,
            .dirty_generation = meta.dirty_generation,
        },
    };
}

fn graphicsRowAnchorOut(value: kitty_types.Graphics.RowAnchor) FfiGraphicsRowAnchor {
    return switch (value) {
        .on_screen => |row| .{ .kind = 1, .value = row },
        .scrollback_above => |rows| .{ .kind = 2, .value = rows },
        .below_screen => |rows| .{ .kind = 3, .value = rows },
    };
}

fn graphicsImageResult(image: kitty_types.Graphics.Image) FfiGraphicsImageResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .image = .{
            .image_id = image.image_id,
            .image_ref_id = image.image_ref_id,
            .image_number = image.image_number,
            .format = image.format,
            .width = image.width,
            .height = image.height,
            .payload_len = @intCast(image.base64_payload.len),
        },
    };
}

fn graphicsPlacementResult(placement: kitty_types.Graphics.Placement) FfiGraphicsPlacementResult {
    return graphicsPlacementResultWithCell(placement, null);
}

fn graphicsPlacementResultWithCell(placement: kitty_types.Graphics.Placement, cell_pixel_size: ?screen.Screen.CellPixelSize) FfiGraphicsPlacementResult {
    const dest = placement.resolveDestGeometry(cell_pixel_size);
    std.debug.assert(placement.render_order_key != 0);
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .placement = .{
            .image_id = placement.image_id,
            .placement_id = placement.placement_id,
            .z_index = placement.z_index,
            .anchor = graphicsRowAnchorOut(placement.anchor_row),
            .anchor_col = placement.anchor_col,
            .source_x = placement.source_x,
            .source_y = placement.source_y,
            .source_width = placement.source_width,
            .source_height = placement.source_height,
            .cell_x_offset = placement.cell_x_offset,
            .cell_y_offset = placement.cell_y_offset,
            .columns = placement.columns,
            .rows = placement.rows,
            .dest_left_cell_px = if (dest) |value| value.left_px else 0,
            .dest_top_cell_px = if (dest) |value| value.top_px else 0,
            .dest_right_cell_px = if (dest) |value| value.right_px else 0,
            .dest_bottom_cell_px = if (dest) |value| value.bottom_px else 0,
            .dest_grid_columns = placement.effective_columns,
            .dest_grid_rows = placement.effective_rows,
            .effective_columns = placement.effective_columns,
            .effective_rows = placement.effective_rows,
            .flags = placement.flags,
            .render_order_key = placement.render_order_key,
        },
    };
}

fn graphicsVirtualPlacementResult(placement: kitty_types.Graphics.VirtualPlacement) FfiGraphicsVirtualPlacementResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .placement = .{
            .image_id = placement.image_id,
            .placement_id = placement.placement_id,
            .source_x = placement.source_x,
            .source_y = placement.source_y,
            .source_width = placement.source_width,
            .source_height = placement.source_height,
            .columns = placement.columns,
            .rows = placement.rows,
        },
    };
}

fn graphicsPlaceholderRunResult(run: kitty_types.Graphics.ResolvedPlaceholderRun) FfiGraphicsPlaceholderRunResult {
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .run = .{
            .image_id = run.image_id,
            .placement_id = run.placement_id,
            .virtual_placement_index = run.virtual_placement_index,
            .run_order = run.run_order,
            .cell_row = run.cell_row,
            .cell_col = run.cell_col,
            .image_row = run.image_row,
            .image_col = run.image_col,
            .columns = run.columns,
        },
    };
}

fn selectionRowSource(screen_state: *const screen_set.Set, row: i32) ?screen_set.RowSource {
    if (row < 0) {
        const depth_i64 = -(@as(i64, row) + 1);
        const depth: u32 = std.math.cast(u32, depth_i64) orelse return null;
        if (screen_state.alt_active) return null;
        if (depth >= screen_state.primary.historyCount()) return null;
        return .{ .history = depth };
    }
    const screen_row: u16 = std.math.cast(u16, row) orelse return null;
    if (screen_row >= screen_state.activeConst().rows) return null;
    return .{ .screen = screen_row };
}

fn selectionContentEndExclusive(screen_state: *const screen_set.Set, row: i32) u16 {
    const source = selectionRowSource(screen_state, row) orelse return 0;
    const active = screen_state.activeConst();
    var scan = active.cols;
    while (scan > 0) {
        const idx = scan - 1;
        const cell = switch (source) {
            .history => |recency| active.historyCellAt(recency, idx),
            .screen => |screen_row| active.cellInfoAt(screen_row, idx),
        };
        if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
        scan -= 1;
    }
    return if (active.cols > 0) 1 else 0;
}

fn visibleSelectionRow(view: screen_set.View, row: u16) i32 {
    return switch (view.rowSource(row)) {
        .history => |recency| -1 - @as(i32, @intCast(recency)),
        .screen => |screen_row| screen_row,
    };
}

fn visibleSelectionRange(view: screen_set.View, selected: selection.TerminalSelection, row: u16) ?struct { start: u16, end_exclusive: u16 } {
    const ordered = selection.ordered(selected);
    const selected_row = visibleSelectionRow(view, row);
    if (selected_row < ordered.start.row or selected_row > ordered.end.row) return null;

    const row_end = view.contentEndExclusive(row);
    if (row_end == 0) return null;

    const range_start: u16 = if (selected_row == ordered.start.row) ordered.start.col else 0;
    const unclamped_end: u32 = if (selected_row == ordered.end.row)
        @as(u32, ordered.end.col) + 1
    else
        row_end;
    const range_end: u16 = @intCast(@min(unclamped_end, row_end));
    if (range_start >= range_end) return null;
    return .{ .start = range_start, .end_exclusive = range_end };
}

fn applyVisibleSelection(view: screen_set.View, selected: ?selection.TerminalSelection, cells: []FfiSurfaceCell) void {
    const active = selected orelse return;
    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        const range = visibleSelectionRange(view, active, row) orelse continue;
        const base: usize = @as(usize, row) * @as(usize, view.cols);
        var col = range.start;
        while (col < range.end_exclusive) : (col += 1) {
            cells[base + col].attrs.selected = 1;
        }
    }
}

fn copySelectionText(owned: *terminal.Terminal) ![]const u8 {
    const selected = owned.selectionState() orelse return &.{};
    const ordered_selection = selection.ordered(selected);
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(owned.allocator);
    var row = ordered_selection.start.row;
    while (row <= ordered_selection.end.row) : (row += 1) {
        const source = selectionRowSource(&owned.screen_state, row) orelse break;
        const row_start = if (row == ordered_selection.start.row) ordered_selection.start.col else 0;
        const row_end = if (row == ordered_selection.end.row)
            @as(u16, @intCast(@min(@as(u32, ordered_selection.end.col) + 1, @as(u32, owned.screen_state.activeConst().cols))))
        else
            selectionContentEndExclusive(&owned.screen_state, row);
        if (row_end > row_start) {
            var col = row_start;
            while (col < row_end) : (col += 1) {
                const cell = switch (source) {
                    .history => |recency| owned.screen_state.primary.historyCellAt(recency, col),
                    .screen => |screen_row| owned.screen_state.activeConst().cellInfoAt(screen_row, col),
                };
                if (cell.codepoint == 0) continue;
                var utf8: [4]u8 = undefined;
                const len = try std.unicode.utf8Encode(@intCast(cell.codepoint), &utf8);
                try out.appendSlice(owned.allocator, utf8[0..len]);
            }
        }
        if (row != ordered_selection.end.row) try out.append(owned.allocator, '\n');
    }
    return out.toOwnedSlice(owned.allocator);
}

pub fn terminalInit(rows: u16, cols: u16, history_capacity: u16) callconv(.c) VtHandle {
    return terminalInitWithOptions(rows, cols, history_capacity, .{});
}

pub fn terminalInitWithOptions(rows: u16, cols: u16, history_capacity: u16, options: FfiTerminalInitOptions) callconv(.c) VtHandle {
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

pub fn terminalDeinit(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    owned.deinit();
    std.heap.c_allocator.destroy(owned);
}

pub fn terminalFeed(handle: VtHandle, ptr: ?[*]const u8, len: usize) callconv(.c) FfiFeedResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const bytes = bytesIn(ptr, len) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const summary = owned.feed(bytes) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.ConsequenceLimit, error.ParsedEventLimit, error.StringControlLimit => HowlVtCallStatus.limit_reached,
            error.OutOfMemory => HowlVtCallStatus.failed,
        }) };
    };
    return .{
        .status = @intFromEnum(HowlVtCallStatus.ok),
        .state_changed = boolByte(summary.state_changed),
        .title_changed = boolByte(summary.title_changed),
    };
}

pub fn terminalCopyTitle(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return copyBytes(out, owned.host.current_title orelse &.{});
}

pub fn terminalResize(handle: VtHandle, rows: u16, cols: u16) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.resize(rows, cols) catch return @intFromEnum(HowlVtCallStatus.failed);
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalSetCellPixelSize(handle: VtHandle, width: u32, height: u32) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    if (width == 0 or height == 0) return @intFromEnum(HowlVtCallStatus.invalid_argument);
    owned.setCellPixelSize(width, height);
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalAckSurface(handle: VtHandle, snapshot_seq: u64) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    return if (owned.ackSurface(snapshot_seq))
        @intFromEnum(HowlVtCallStatus.ok)
    else
        @intFromEnum(HowlVtCallStatus.invalid_argument);
}

pub fn terminalQueryVisibleMeta(handle: VtHandle, scrollback_offset: u64) callconv(.c) FfiVisibleMetaResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    return visibleMetaResult(owned.visibleMeta(scrollback_offset));
}

pub fn terminalQueryGraphicsMeta(handle: VtHandle) callconv(.c) FfiGraphicsMetaResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const meta = owned.graphicsMeta() catch return .{ .status = @intFromEnum(HowlVtCallStatus.failed) };
    return graphicsMetaResult(meta);
}

pub fn terminalQueryGraphicsImage(handle: VtHandle, publication_seq: u64, image_index: u32) callconv(.c) FfiGraphicsImageResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const image = owned.graphicsImage(publication_seq, image_index) catch {
        return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    } orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return graphicsImageResult(image);
}

pub fn terminalQueryGraphicsPlacement(handle: VtHandle, publication_seq: u64, placement_index: u32) callconv(.c) FfiGraphicsPlacementResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const placement = owned.graphicsPlacement(publication_seq, placement_index) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.InvalidArgument => HowlVtCallStatus.invalid_argument,
            error.OutOfMemory, error.ConsequenceLimit => HowlVtCallStatus.failed,
        }) };
    } orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return graphicsPlacementResultWithCell(placement, owned.screen_state.activeConst().cellPixelSize());
}

pub fn terminalQueryGraphicsVirtualPlacement(handle: VtHandle, publication_seq: u64, placement_index: u32) callconv(.c) FfiGraphicsVirtualPlacementResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const placement = owned.graphicsVirtualPlacement(publication_seq, placement_index) catch {
        return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    } orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return graphicsVirtualPlacementResult(placement);
}

pub fn terminalQueryGraphicsPlaceholderRun(handle: VtHandle, publication_seq: u64, run_index: u32) callconv(.c) FfiGraphicsPlaceholderRunResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const run = owned.graphicsPlaceholderRun(publication_seq, run_index) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.InvalidArgument => HowlVtCallStatus.invalid_argument,
            error.OutOfMemory, error.ConsequenceLimit => HowlVtCallStatus.failed,
        }) };
    } orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return graphicsPlaceholderRunResult(run);
}

pub fn terminalCopyGraphicsPayload(handle: VtHandle, publication_seq: u64, image_index: u32, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const image = owned.graphicsImage(publication_seq, image_index) catch {
        return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    } orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return copyBytes(out, image.base64_payload);
}

pub fn terminalCopySurface(handle: VtHandle, scrollback_offset: u64, cells_ptr: ?[*]FfiSurfaceCell, cells_cap: usize, dirty_rows_ptr: ?[*]u8, dirty_rows_cap: usize, cols_start_ptr: ?[*]u16, cols_start_cap: usize, cols_end_ptr: ?[*]u16, cols_end_cap: usize) callconv(.c) FfiSurfaceResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const publication = owned.surfaceSnapshot(scrollback_offset);
    const snapshot = publication.snapshot;
    const view = snapshot.view;
    const cell_count = surfaceCellCount(view.rows, view.cols);
    // The shipped VT ABI still accepts architecture-sized destination capacities.
    // Validate those seam values against typed VT counts before exposing writable slices.
    var result = surfaceResult(owned, view, snapshot.selection, publication.snapshot_seq, publication.dirty_generation, cells_ptr, dirty_rows_ptr, cols_start_ptr, cols_end_ptr);

    if (cells_cap < cell_count or dirty_rows_cap < view.rows or cols_start_cap < view.rows or cols_end_cap < view.rows) {
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
    const cols_start = if (cols_start_ptr) |ptr| ptr[0..cols_start_cap] else {
        result.status = @intFromEnum(HowlVtCallStatus.invalid_argument);
        return result;
    };
    const cols_end = if (cols_end_ptr) |ptr| ptr[0..cols_end_cap] else {
        result.status = @intFromEnum(HowlVtCallStatus.invalid_argument);
        return result;
    };

    screen_set.copyViewCells(view, cells_out, cellOut);
    applyVisibleSelection(view, snapshot.selection, cells_out[0..@intCast(cell_count)]);
    screen_set.copyDirtyRows(dirty_rows_out[0..view.rows], cols_start[0..view.rows], cols_end[0..view.rows], snapshot.dirty);

    return result;
}

pub fn terminalQuerySelection(handle: VtHandle) callconv(.c) FfiSelectionResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    return selectionResult(owned.selectionState());
}

pub fn terminalStartSelection(handle: VtHandle, row: i32, col: u16) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.startSelection(row, col);
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalUpdateSelection(handle: VtHandle, row: i32, col: u16) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.updateSelection(row, col);
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalFinishSelection(handle: VtHandle) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.finishSelection();
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalClearSelection(handle: VtHandle) callconv(.c) i32 {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    owned.clearSelection();
    return @intFromEnum(HowlVtCallStatus.ok);
}

pub fn terminalCopySelection(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const text = copySelectionText(owned) catch return .{ .status = @intFromEnum(HowlVtCallStatus.failed) };
    defer if (text.len != 0) owned.allocator.free(text);
    return copyBytes(out, text);
}

pub fn terminalCopySurfaceHyperlink(handle: VtHandle, scrollback_offset: u64, snapshot_seq: u64, row: u16, col: u16, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    const uri = owned.visibleCellHyperlinkUri(scrollback_offset, snapshot_seq, row, col) catch {
        return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    } orelse &.{};
    return copyBytes(out, uri);
}

pub fn terminalCopyPendingOutput(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return switch (host_state.copyPendingOutputInto(owned, out)) {
        .copied => |written| .{
            .status = @intFromEnum(HowlVtCallStatus.ok),
            .written = written,
            .needed = written,
        },
        .short => |needed| .{
            .status = @intFromEnum(HowlVtCallStatus.short_buffer),
            .needed = needed,
        },
    };
}

pub fn terminalClearPendingOutput(handle: VtHandle) callconv(.c) void {
    const owned = vtFromHandle(handle) orelse return;
    host_state.clearPendingOutput(owned);
}

pub fn terminalDrainPendingClipboard(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    return switch (host_state.drainPendingClipboardSetInto(owned, out)) {
        .none => .{ .status = @intFromEnum(HowlVtCallStatus.ok) },
        .copied => |written| .{
            .status = @intFromEnum(HowlVtCallStatus.ok),
            .written = written,
            .needed = written,
        },
        .short => |needed| .{
            .status = @intFromEnum(HowlVtCallStatus.short_buffer),
            .needed = needed,
        },
        .failed => .{ .status = @intFromEnum(HowlVtCallStatus.failed) },
    };
}

pub fn terminalQueryRuntimeObligation(handle: VtHandle, now_ns: u64) callconv(.c) FfiRuntimeObligationResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    return runtimeObligationResult(owned.runtimeObligation(now_ns));
}

pub fn terminalProgressRuntime(handle: VtHandle, now_ns: u64) callconv(.c) FfiRuntimeProgressResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const progress = owned.progressRuntime(now_ns) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.ConsequenceLimit => HowlVtCallStatus.limit_reached,
            error.OutOfMemory => HowlVtCallStatus.failed,
        }) };
    };
    return runtimeProgressResult(progress);
}

pub fn terminalNoteDrawnGraphics(handle: VtHandle, publication_seq: u64, ptr: ?[*]const u32, len: usize) callconv(.c) c_int {
    const owned = vtFromHandle(handle) orelse return @intFromEnum(HowlVtCallStatus.missing_handle);
    if (len > 0 and ptr == null) return @intFromEnum(HowlVtCallStatus.invalid_argument);
    const image_ref_ids = if (len == 0) &[_]u32{} else ptr.?[0..len];
    owned.noteDrawnGraphics(publication_seq, image_ref_ids) catch |err| {
        return @intFromEnum(switch (err) {
            error.InvalidArgument => HowlVtCallStatus.invalid_argument,
            error.OutOfMemory, error.ConsequenceLimit => HowlVtCallStatus.failed,
        });
    };
    return @intFromEnum(HowlVtCallStatus.ok);
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

pub fn terminalEncodePasteStart(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    var scratch: input.Scratch = .{};
    return copyBytes(out, input.encodePasteStart(owned, &scratch));
}

pub fn terminalEncodePasteEnd(handle: VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) FfiBytesResult {
    const owned = vtFromHandle(handle) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.missing_handle) };
    const out = bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(HowlVtCallStatus.invalid_argument) };
    var scratch: input.Scratch = .{};
    return copyBytes(out, input.encodePasteEnd(owned, &scratch));
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
    const source = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, null, 0, null, 0, null, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.short_buffer)), source.status);
    try std.testing.expectEqual(@as(u16, 2), source.source.rows);
    try std.testing.expectEqual(@as(u16, 4), source.source.cols);
}

test "vt ffi exports style attrs and resets" {
    const handle = terminalInit(1, 2, 0);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const bytes = "\x1b[1;2;3;8;9mA\x1b[22;23;28;29mB";
    const fed = terminalFeed(handle, bytes.ptr, bytes.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), fed.status);

    var cells: [2]FfiSurfaceCell = undefined;
    var dirty_rows: [1]u8 = undefined;
    var cols_start: [1]u16 = undefined;
    var cols_end: [1]u16 = undefined;
    const surface = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), surface.status);

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

test "vt ffi init options seed default cursor style and blink" {
    const handle = terminalInitWithOptions(2, 4, 8, .{
        .default_cursor_style = .{ .shape = 2, .blink = 0 },
    });
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    var cells: [8]FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;

    const initial = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), initial.status);
    try std.testing.expectEqual(@as(u8, 2), initial.source.cursor.shape);
    try std.testing.expectEqual(@as(u8, 0), initial.source.cursor.blink);

    const override = terminalFeed(handle, "\x1b[3 q".ptr, 6);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), override.status);

    const overridden = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), overridden.status);
    try std.testing.expectEqual(@as(u8, 1), overridden.source.cursor.shape);
    try std.testing.expectEqual(@as(u8, 1), overridden.source.cursor.blink);

    const reset = terminalFeed(handle, "\x1bc".ptr, 2);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), reset.status);

    const after_reset = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), after_reset.status);
    try std.testing.expectEqual(@as(u8, 2), after_reset.source.cursor.shape);
    try std.testing.expectEqual(@as(u8, 0), after_reset.source.cursor.blink);
}

test "vt ffi query visible meta reports explicit surface metadata" {
    const handle = terminalInit(2, 2, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const fed = terminalFeed(handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, 0), fed.status);

    const meta = terminalQueryVisibleMeta(handle, std.math.maxInt(u64));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(@as(u16, 2), meta.meta.rows);
    try std.testing.expectEqual(@as(u16, 2), meta.meta.cols);
    try std.testing.expectEqual(@as(u64, 1), meta.meta.history_count);
    try std.testing.expectEqual(@as(u8, 0), meta.meta.is_alternate_screen);
    try std.testing.expect(meta.meta.snapshot_seq != 0);
    try std.testing.expect(meta.meta.dirty_generation != 0);
}

fn testRawRgbBase64Owned(allocator: std.mem.Allocator, width: usize, height: usize) ![]u8 {
    const raw = try allocator.alloc(u8, width * height * 3);
    defer allocator.free(raw);
    @memset(raw, 0);
    const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(raw.len));
    _ = std.base64.standard.Encoder.encode(encoded, raw);
    return encoded;
}

test "vt ffi graphics queries expose active-screen retained truth" {
    const handle = terminalInit(4, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalSetCellPixelSize(handle, 10, 20));

    const payload = try testRawRgbBase64Owned(std.testing.allocator, 11, 13);
    defer std.testing.allocator.free(payload);
    const upload = try std.fmt.allocPrint(std.testing.allocator, "\x1b_Gi=7,s=11,v=13,t=d,f=24;{s}\x1b\\", .{payload});
    defer std.testing.allocator.free(upload);
    const place = "\x1b[3;5H\x1b_Ga=p,i=7,p=9,x=2,y=4,w=6,h=8,X=3,Y=5,c=10,r=12,z=-7\x1b\\";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, place.ptr, place.len).status);

    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.image_count);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.placement_count);
    try std.testing.expectEqual(@as(u32, 0), meta.meta.virtual_placement_count);
    try std.testing.expectEqual(@as(u8, 0), meta.meta.is_alternate_screen);
    try std.testing.expect(meta.meta.publication_seq != 0);

    const image = terminalQueryGraphicsImage(handle, meta.meta.publication_seq, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), image.status);
    try std.testing.expectEqual(@as(u32, 7), image.image.image_id);
    try std.testing.expectEqual(@as(u32, 0), image.image.image_number);
    try std.testing.expectEqual(@as(u16, 24), image.image.format);
    try std.testing.expectEqual(@as(u32, 11), image.image.width);
    try std.testing.expectEqual(@as(u32, 13), image.image.height);
    try std.testing.expectEqual(@as(u64, payload.len), image.image.payload_len);

    const placement = terminalQueryGraphicsPlacement(handle, meta.meta.publication_seq, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), placement.status);
    try std.testing.expectEqual(@as(u32, 7), placement.placement.image_id);
    try std.testing.expectEqual(@as(u32, 9), placement.placement.placement_id);
    try std.testing.expectEqual(@as(i32, -7), placement.placement.z_index);
    try std.testing.expectEqual(@as(u8, 1), placement.placement.anchor.kind);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.anchor.value);
    try std.testing.expectEqual(@as(u16, 4), placement.placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.placement.source_height);
    try std.testing.expectEqual(@as(u32, 3), placement.placement.cell_x_offset);
    try std.testing.expectEqual(@as(u32, 5), placement.placement.cell_y_offset);
    try std.testing.expectEqual(@as(u32, 10), placement.placement.columns);
    try std.testing.expectEqual(@as(u32, 12), placement.placement.rows);
    try std.testing.expectEqual(@as(u32, 3), placement.placement.dest_left_cell_px);
    try std.testing.expectEqual(@as(u32, 5), placement.placement.dest_top_cell_px);
    try std.testing.expectEqual(@as(u32, 103), placement.placement.dest_right_cell_px);
    try std.testing.expectEqual(@as(u32, 245), placement.placement.dest_bottom_cell_px);
    try std.testing.expectEqual(@as(u32, 10), placement.placement.dest_grid_columns);
    try std.testing.expectEqual(@as(u32, 12), placement.placement.dest_grid_rows);
    try std.testing.expectEqual(@as(u32, 10), placement.placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 12), placement.placement.effective_rows);

    const copied_payload = try std.testing.allocator.alloc(u8, payload.len);
    defer std.testing.allocator.free(copied_payload);
    const copied = terminalCopyGraphicsPayload(handle, meta.meta.publication_seq, 0, copied_payload.ptr, copied_payload.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), copied.status);
    try std.testing.expectEqualStrings(payload, copied_payload[0..@intCast(copied.written)]);
}

test "vt ffi graphics placement query exposes resolved omitted-size destination truth" {
    const handle = terminalInit(4, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalSetCellPixelSize(handle, 10, 20));

    const payload = try testRawRgbBase64Owned(std.testing.allocator, 40, 20);
    defer std.testing.allocator.free(payload);
    const upload = try std.fmt.allocPrint(std.testing.allocator, "\x1b_Gi=7,s=40,v=20,t=d,f=24;{s}\x1b\\", .{payload});
    defer std.testing.allocator.free(upload);
    const place = "\x1b_Ga=p,i=7,p=3,X=2,Y=5,c=2\x1b\\";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, place.ptr, place.len).status);

    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);

    const placement = terminalQueryGraphicsPlacement(handle, meta.meta.publication_seq, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), placement.status);
    try std.testing.expectEqual(@as(u32, 0), placement.placement.rows);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.dest_left_cell_px);
    try std.testing.expectEqual(@as(u32, 5), placement.placement.dest_top_cell_px);
    try std.testing.expectEqual(@as(u32, 22), placement.placement.dest_right_cell_px);
    try std.testing.expectEqual(@as(u32, 16), placement.placement.dest_bottom_cell_px);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.dest_grid_columns);
    try std.testing.expectEqual(@as(u32, 1), placement.placement.dest_grid_rows);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 1), placement.placement.effective_rows);
}

test "vt ffi graphics queries expose virtual placement prototypes separately" {
    const handle = terminalInit(4, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const payload = try testRawRgbBase64Owned(std.testing.allocator, 11, 13);
    defer std.testing.allocator.free(payload);
    const upload = try std.fmt.allocPrint(std.testing.allocator, "\x1b_Gi=7,s=11,v=13,t=d,f=24;{s}\x1b\\", .{payload});
    defer std.testing.allocator.free(upload);
    const place = "\x1b_Ga=p,i=7,p=9,U=1,x=2,y=4,w=6,h=8,c=10,r=12\x1b\\";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, place.ptr, place.len).status);

    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.image_count);
    try std.testing.expectEqual(@as(u32, 0), meta.meta.placement_count);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.virtual_placement_count);

    const placement = terminalQueryGraphicsVirtualPlacement(handle, meta.meta.publication_seq, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), placement.status);
    try std.testing.expectEqual(@as(u32, 7), placement.placement.image_id);
    try std.testing.expectEqual(@as(u32, 9), placement.placement.placement_id);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.placement.source_height);
    try std.testing.expectEqual(@as(u32, 10), placement.placement.columns);
    try std.testing.expectEqual(@as(u32, 12), placement.placement.rows);
}

test "vt ffi graphics queries expose chunked unicode no-move virtual contract" {
    const handle = terminalInit(6, 16, 6);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const payload = try testRawRgbBase64Owned(std.testing.allocator, 11, 13);
    defer std.testing.allocator.free(payload);
    const first = try std.fmt.allocPrint(std.testing.allocator, "\x1b[2;3H\x1b_GI=13,p=5,U=1,C=1,s=11,v=13,a=T,t=d,f=24,x=2,y=4,w=6,h=8,c=7,r=3,m=1;{s}\x1b\\", .{payload[0..4]});
    defer std.testing.allocator.free(first);
    const second = try std.fmt.allocPrint(std.testing.allocator, "\x1b[5;9H\x1b_Gp=99,x=1,y=1,w=1,h=1,c=1,r=1,m=0;{s}\x1b\\", .{payload[4..]});
    defer std.testing.allocator.free(second);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, first.ptr, first.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, second.ptr, second.len).status);

    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.image_count);
    try std.testing.expectEqual(@as(u32, 0), meta.meta.placement_count);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.virtual_placement_count);

    const image = terminalQueryGraphicsImage(handle, meta.meta.publication_seq, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), image.status);
    try std.testing.expectEqual(@as(u32, 1), image.image.image_id);
    try std.testing.expectEqual(@as(u32, 13), image.image.image_number);
    try std.testing.expectEqual(@as(u64, payload.len), image.image.payload_len);

    const copied_payload = try std.testing.allocator.alloc(u8, payload.len);
    defer std.testing.allocator.free(copied_payload);
    const copied = terminalCopyGraphicsPayload(handle, meta.meta.publication_seq, 0, copied_payload.ptr, copied_payload.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), copied.status);
    try std.testing.expectEqualStrings(payload, copied_payload[0..@intCast(copied.written)]);

    const placement = terminalQueryGraphicsVirtualPlacement(handle, meta.meta.publication_seq, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), placement.status);
    try std.testing.expectEqual(@as(u32, 1), placement.placement.image_id);
    try std.testing.expectEqual(@as(u32, 5), placement.placement.placement_id);
    try std.testing.expectEqual(@as(u32, 2), placement.placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.placement.source_height);
    try std.testing.expectEqual(@as(u32, 7), placement.placement.columns);
    try std.testing.expectEqual(@as(u32, 3), placement.placement.rows);
}

test "vt ffi graphics publication suppresses render-facing placeholder runs" {
    const handle = terminalInit(4, 8, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const upload = "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\";
    const place = "\x1b_Ga=p,i=7,p=9,U=1,c=3,r=1\x1b\\";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalSetCellPixelSize(handle, 10, 20));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, place.ptr, place.len).status);

    const owned = vtFromHandle(handle).?;
    var cell = screen.Screen.default_cell;
    cell.codepoint = 0x10EEEE;
    cell.combining_len = 2;
    cell.combining[0] = 0x0305;
    cell.combining[1] = 0x0305;
    cell.attrs.fg = screen.Screen.Color.indexed(7);
    cell.attrs.underline = true;
    cell.attrs.underline_style = .straight;
    cell.attrs.underline_color = screen.Screen.Color.indexed(9);
    owned.screen_state.active().cells.?[2] = cell;
    owned.screen_state.active().cells.?[3] = .{ .codepoint = 0x10EEEE, .attrs = cell.attrs };
    owned.screen_state.active().cells.?[4] = .{ .codepoint = 0x10EEEE, .attrs = cell.attrs };
    owned.postApply(true);

    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(@as(u32, 1), meta.meta.placement_count);
    try std.testing.expectEqual(@as(u32, 0), meta.meta.placeholder_run_count);

    try std.testing.expectEqual(
        @as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)),
        terminalQueryGraphicsPlaceholderRun(handle, meta.meta.publication_seq, 0).status,
    );
}

test "vt ffi graphics publication token rejects stale queries" {
    const handle = terminalInit(3, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const upload = "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, "x".ptr, 1).status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), terminalQueryGraphicsImage(handle, meta.meta.publication_seq, 0).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), terminalQueryGraphicsPlacement(handle, meta.meta.publication_seq, 0).status);

    var payload: [8]u8 = undefined;
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), terminalCopyGraphicsPayload(handle, meta.meta.publication_seq, 0, payload[0..].ptr, payload.len).status);
}

test "vt ffi graphics publication token rejects stale placeholder runs" {
    const handle = terminalInit(4, 8, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const upload = "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\";
    const place = "\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, place.ptr, place.len).status);

    const owned = vtFromHandle(handle).?;
    var cell = screen.Screen.default_cell;
    cell.codepoint = 0x10EEEE;
    cell.combining_len = 2;
    cell.combining[0] = 0x0305;
    cell.combining[1] = 0x0305;
    cell.attrs.fg = screen.Screen.Color.indexed(7);
    cell.attrs.underline = true;
    cell.attrs.underline_style = .straight;
    cell.attrs.underline_color = screen.Screen.Color.indexed(9);
    owned.screen_state.active().cells.?[0] = cell;
    owned.postApply(true);

    const meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(u32, 0), meta.meta.placeholder_run_count);

    const enter_alt = "\x1b[?1049h";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, enter_alt.ptr, enter_alt.len).status);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), terminalQueryGraphicsPlaceholderRun(handle, meta.meta.publication_seq, 0).status);
}

test "vt ffi graphics meta follows active screen only" {
    const handle = terminalInit(3, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const upload = "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\";
    const enter_alt = "\x1b[?1049h";
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, upload.ptr, upload.len).status);
    const main_meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(u32, 1), main_meta.meta.image_count);
    try std.testing.expectEqual(@as(u8, 0), main_meta.meta.is_alternate_screen);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFeed(handle, enter_alt.ptr, enter_alt.len).status);
    const alt_meta = terminalQueryGraphicsMeta(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), alt_meta.status);
    try std.testing.expectEqual(@as(u32, 0), alt_meta.meta.image_count);
    try std.testing.expectEqual(@as(u32, 0), alt_meta.meta.placement_count);
    try std.testing.expectEqual(@as(u32, 0), alt_meta.meta.virtual_placement_count);
    try std.testing.expectEqual(@as(u8, 1), alt_meta.meta.is_alternate_screen);
    try std.testing.expect(alt_meta.meta.publication_seq != main_meta.meta.publication_seq);
}

test "vt ffi set cell pixel size validates and applies" {
    const handle = terminalInit(3, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), terminalSetCellPixelSize(handle, 0, 10));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), terminalSetCellPixelSize(handle, 10, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalSetCellPixelSize(handle, 11, 19));

    const owned = vtFromHandle(handle).?;
    try std.testing.expectEqual(@as(u32, 11), owned.screen_state.primary.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), owned.screen_state.primary.cellPixelSize().?.height);
    try std.testing.expectEqual(@as(u32, 11), owned.screen_state.alternate.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), owned.screen_state.alternate.cellPixelSize().?.height);
}

test "vt ffi runtime obligation query and progress default idle" {
    const handle = terminalInit(3, 16, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const obligation = terminalQueryRuntimeObligation(handle, 1234);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), obligation.status);
    try std.testing.expectEqual(@as(u8, 0), obligation.obligation.pending_now);
    try std.testing.expectEqual(@as(u64, 0), obligation.obligation.deadline_ns);

    const progress = terminalProgressRuntime(handle, 1234);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), progress.status);
    try std.testing.expectEqual(@as(u8, 0), progress.state_changed);
    try std.testing.expectEqual(@as(u8, 0), progress.obligation.pending_now);
    try std.testing.expectEqual(@as(u64, 0), progress.obligation.deadline_ns);
}

test "vt ffi surface copy carries render color state" {
    const handle = terminalInit(2, 2, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const bytes = "\x1b]4;1;#010203\x1b\\\x1b]10;#040506\x1b\\\x1b]11;#070809\x1b\\\x1b]12;#0a0b0c\x1b\\";
    try std.testing.expectEqual(@as(i32, 0), terminalFeed(handle, bytes.ptr, bytes.len).status);

    var cells: [4]FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    const surface = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), surface.status);
    try std.testing.expectEqual(FfiRgb8{ .r = 4, .g = 5, .b = 6 }, surface.source.colors.foreground);
    try std.testing.expectEqual(FfiRgb8{ .r = 7, .g = 8, .b = 9 }, surface.source.colors.background);
    try std.testing.expectEqual(FfiRgb8{ .r = 10, .g = 11, .b = 12 }, surface.source.colors.cursor);
    try std.testing.expectEqual(FfiRgb8{ .r = 1, .g = 2, .b = 3 }, surface.source.colors.palette[1]);
}

test "vt ffi surface copy preserves semantic cell color identity" {
    const handle = terminalInit(1, 3, 0);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const bytes = "\x1b[31;44mA\x1b[38;2;1;2;3;48;5;200mB\x1b[39;49mC";
    try std.testing.expectEqual(@as(i32, 0), terminalFeed(handle, bytes.ptr, bytes.len).status);

    var cells: [3]FfiSurfaceCell = undefined;
    var dirty_rows: [1]u8 = undefined;
    var cols_start: [1]u16 = undefined;
    var cols_end: [1]u16 = undefined;
    const surface = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), surface.status);
    try std.testing.expectEqual(FfiColor{ .kind = 1, .value = 1 }, cells[0].fg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 1, .value = 4 }, cells[0].bg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 2, .value = 0x010203 }, cells[1].fg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 1, .value = 200 }, cells[1].bg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 0, .value = 0 }, cells[2].fg_color);
    try std.testing.expectEqual(FfiColor{ .kind = 0, .value = 0 }, cells[2].bg_color);
}

test "vt ffi copy surface clamps oversized scrollback offset" {
    const handle = terminalInit(2, 2, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const fed = terminalFeed(handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, 0), fed.status);

    const meta = terminalQueryVisibleMeta(handle, std.math.maxInt(u64));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);
    try std.testing.expectEqual(meta.meta.history_count, @as(u64, 1));
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

test "vt ffi copies visible cell hyperlink for matching snapshot" {
    const handle = terminalInit(1, 8, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const seq = "\x1b]8;;https://example.com\x07abc\x1b]8;;\x07";
    const fed = terminalFeed(handle, seq.ptr, seq.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), fed.status);

    const meta = terminalQueryVisibleMeta(handle, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), meta.status);

    var out: [32]u8 = undefined;
    const uri = terminalCopySurfaceHyperlink(handle, 0, meta.meta.snapshot_seq, 0, 1, out[0..].ptr, out.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), uri.status);
    try std.testing.expectEqualStrings("https://example.com", out[0..@intCast(uri.written)]);
}

test "vt ffi rejects visible cell hyperlink lookup for stale snapshot" {
    const handle = terminalInit(1, 8, 4);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const first_seq = "\x1b]8;;https://example.com\x07a\x1b]8;;\x07";
    const first_feed = terminalFeed(handle, first_seq.ptr, first_seq.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), first_feed.status);
    const first_meta = terminalQueryVisibleMeta(handle, 0);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), first_meta.status);

    const second_feed = terminalFeed(handle, "b".ptr, 1);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), second_feed.status);

    var out: [32]u8 = undefined;
    const uri = terminalCopySurfaceHyperlink(handle, 0, first_meta.meta.snapshot_seq, 0, 0, out[0..].ptr, out.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.invalid_argument)), uri.status);
}

test "vt ffi selection query and copy stay history-aware" {
    const handle = terminalInit(2, 4, 8);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const fed = terminalFeed(handle, "aa\r\nbb\r\ncc".ptr, 8);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), fed.status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalStartSelection(handle, -1, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalUpdateSelection(handle, 0, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFinishSelection(handle));

    const selection_result = terminalQuerySelection(handle);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), selection_result.status);
    try std.testing.expectEqual(@as(u8, 1), selection_result.selection.active);
    try std.testing.expectEqual(@as(i32, -1), selection_result.selection.start.row);
    try std.testing.expectEqual(@as(i32, 0), selection_result.selection.end.row);

    var text: [32]u8 = undefined;
    const copied = terminalCopySelection(handle, text[0..].ptr, text.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), copied.status);
    try std.testing.expectEqualStrings("aa\nbb", text[0..@intCast(copied.written)]);

    var cells: [8]FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;
    const surface = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), surface.status);
    try std.testing.expectEqual(@as(u8, 1), surface.source.selection.active);
    try std.testing.expectEqual(@as(i32, -1), surface.source.selection.start.row);
    try std.testing.expectEqual(@as(i32, 0), surface.source.selection.end.row);
}

test "vt ffi surface selection follows viewport and hugs visible content" {
    const handle = terminalInit(2, 4, 8);
    defer terminalDeinit(handle);
    try std.testing.expect(handle != null);

    const fed = terminalFeed(handle, "aa\r\nbb\r\ncc".ptr, 10);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), fed.status);

    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalStartSelection(handle, -1, 0));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalUpdateSelection(handle, 0, 1));
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), terminalFinishSelection(handle));

    var cells: [8]FfiSurfaceCell = undefined;
    var dirty_rows: [2]u8 = undefined;
    var cols_start: [2]u16 = undefined;
    var cols_end: [2]u16 = undefined;

    const live = terminalCopySurface(handle, 0, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), live.status);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[1].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[2].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[3].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[4].attrs.selected);

    const scrolled = terminalCopySurface(handle, 1, cells[0..].ptr, cells.len, dirty_rows[0..].ptr, dirty_rows.len, cols_start[0..].ptr, cols_start.len, cols_end[0..].ptr, cols_end.len);
    try std.testing.expectEqual(@as(i32, @intFromEnum(HowlVtCallStatus.ok)), scrolled.status);
    try std.testing.expectEqual(@as(u8, 1), cells[0].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[1].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[2].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[3].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[4].attrs.selected);
    try std.testing.expectEqual(@as(u8, 1), cells[5].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[6].attrs.selected);
    try std.testing.expectEqual(@as(u8, 0), cells[7].attrs.selected);
}
