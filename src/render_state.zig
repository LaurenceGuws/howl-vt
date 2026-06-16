const std = @import("std");
const host_state = @import("host_state.zig");
const screen = @import("screen.zig");
const screen_set = @import("screen_set.zig");
const selection_projection = @import("selection_projection.zig");
const terminal = @import("terminal.zig");

pub const RenderState = struct {
    cols: u16,
    rows: u16,
    dirty: Dirty,
    colors: Colors,
    cursor: Cursor,
    snapshot_seq: u64,
    dirty_generation: u64,
    history_count: u64,
    scrollback_offset: u64,
    scroll_row: u64,
    is_alternate_screen: bool,
    rows_storage: std.ArrayListUnmanaged(Row),

    pub const Dirty = enum(u8) {
        false = 0,
        partial = 1,
        full = 2,
    };

    pub const Row = struct {
        dirty: bool = false,
        cells: []Cell = &.{},
        selection: ?SelectionRange = null,
        highlights: []Highlight = &.{},
    };

    pub const Cell = struct {
        codepoint: u32 = 0,
        combining_len: u8 = 0,
        combining: [3]u32 = [_]u32{0} ** 3,
        continuation: bool = false,
        fg_color: Color = .{},
        bg_color: Color = .{},
        underline_color: Color = .{},
        underline_style: UnderlineStyle = .straight,
        bold: bool = false,
        dim: bool = false,
        italic: bool = false,
        underline: bool = false,
        blink: bool = false,
        inverse: bool = false,
        invisible: bool = false,
        strikethrough: bool = false,
        link_id: u32 = 0,
        selected: bool = false,
        highlighted: bool = false,
    };

    pub const Color = struct {
        kind: ColorKind = .default,
        value: u32 = 0,
    };

    pub const ColorKind = enum(u8) {
        default,
        indexed,
        rgb,
    };

    pub const UnderlineStyle = enum(u3) {
        straight,
        double,
        curly,
        dotted,
        dashed,
    };

    pub const Highlight = struct {
        tag: u8,
        index: u16,
        start_col: u16,
        end_col: u16,
    };

    pub const SelectionRange = struct {
        start_col: u16,
        end_col: u16,
    };

    pub const Colors = struct {
        background: Rgb8 = .{},
        foreground: Rgb8 = .{},
        cursor: ?Rgb8 = null,
        palette: [256]Rgb8 = [_]Rgb8{.{}} ** 256,
    };

    pub const Cursor = struct {
        visual_style: CursorVisualStyle = .block,
        visible: bool = true,
        blinking: bool = true,
        viewport: ?CursorViewport = null,
    };

    pub const CursorVisualStyle = enum(u8) {
        bar = 0,
        block = 1,
        underline = 2,
        block_hollow = 3,
    };

    pub const CursorViewport = struct {
        x: u16,
        y: u16,
        wide_tail: bool,
    };

    pub const Rgb8 = struct {
        r: u8 = 0,
        g: u8 = 0,
        b: u8 = 0,
    };

    pub fn empty() RenderState {
        return .{
            .cols = 0,
            .rows = 0,
            .dirty = .false,
            .colors = .{},
            .cursor = .{},
            .snapshot_seq = 0,
            .dirty_generation = 0,
            .history_count = 0,
            .scrollback_offset = 0,
            .scroll_row = 0,
            .is_alternate_screen = false,
            .rows_storage = .{ .items = &.{}, .capacity = 0 },
        };
    }

    pub fn deinit(self: *RenderState, allocator: std.mem.Allocator) void {
        for (self.rows_storage.items) |row| {
            allocator.free(row.cells);
            allocator.free(row.highlights);
        }
        self.rows_storage.deinit(allocator);
        self.* = empty();
    }

    pub fn update(self: *RenderState, allocator: std.mem.Allocator, vt: *terminal.Terminal, scrollback_offset: u64) !void {
        const previous_rows = self.rows;
        const previous_cols = self.cols;
        const previous_alternate = self.is_alternate_screen;
        const meta = vt.visibleMeta(scrollback_offset);
        const publication = vt.surfaceSnapshot(scrollback_offset);
        const snapshot = publication.snapshot;
        const view = snapshot.view;

        std.debug.assert(meta.rows == view.rows);
        std.debug.assert(meta.cols == view.cols);
        std.debug.assert(meta.history_count == view.history_count);
        std.debug.assert(meta.is_alternate_screen == view.is_alternate_screen);
        std.debug.assert(meta.snapshot_seq == publication.snapshot_seq);
        std.debug.assert(meta.dirty_generation == publication.dirty_generation);

        try self.resizeRows(allocator, view.rows, view.cols);

        self.cols = view.cols;
        self.rows = view.rows;
        self.snapshot_seq = publication.snapshot_seq;
        self.dirty_generation = publication.dirty_generation;
        self.history_count = view.history_count;
        self.scrollback_offset = view.scrollback_offset;
        self.scroll_row = view.start;
        self.is_alternate_screen = view.is_alternate_screen;
        self.colors = colorsFromTerminal(vt);
        self.cursor = cursorFromView(view);

        const dirty_rows = try allocator.alloc(u8, view.rows);
        defer allocator.free(dirty_rows);
        const cols_start = try allocator.alloc(u16, view.rows);
        defer allocator.free(cols_start);
        const cols_end = try allocator.alloc(u16, view.rows);
        defer allocator.free(cols_end);
        screen_set.copyDirtyRows(dirty_rows, cols_start, cols_end, snapshot.dirty);

        for (self.rows_storage.items, 0..) |*row, row_index| {
            row.dirty = dirty_rows[row_index] != 0;
            row.selection = null;
            if (snapshot.selection) |selected| {
                if (selection_projection.visibleRange(view, selected, @intCast(row_index))) |range| {
                    row.selection = .{ .start_col = range.start, .end_col = range.end_exclusive };
                }
            }
        }

        const cell_count: usize = @as(usize, view.rows) * @as(usize, view.cols);
        var flat_cells = try allocator.alloc(Cell, cell_count);
        defer allocator.free(flat_cells);
        screen_set.copyViewCells(view, flat_cells, cellFromScreen);
        for (self.rows_storage.items, 0..) |*row, row_index| {
            const base: usize = row_index * @as(usize, view.cols);
            @memcpy(row.cells, flat_cells[base..][0..view.cols]);
        }

        self.dirty = dirtyState(previous_rows, previous_cols, previous_alternate, view.rows, view.cols, view.is_alternate_screen, dirty_rows);
        std.debug.assert(self.rows_storage.items.len == self.rows);
    }

    pub fn ack(self: *RenderState, vt: *terminal.Terminal) bool {
        if (!vt.surface_publication.canAck(self.snapshot_seq, vt.dirty_generation)) return false;
        if (!vt.ackSurface(self.snapshot_seq)) return false;
        self.dirty = .false;
        for (self.rows_storage.items) |*row| row.dirty = false;
        return true;
    }

    pub fn updateHighlightsForHyperlink(self: *RenderState) void {
        std.debug.assert(self.rows_storage.items.len == self.rows);
    }

    pub fn rowCount(self: *const RenderState) u16 {
        std.debug.assert(self.rows_storage.items.len == self.rows);
        return self.rows;
    }

    pub fn cellCount(self: *const RenderState, row: u16) u16 {
        std.debug.assert(row < self.rows);
        const cells_len = self.rows_storage.items[row].cells.len;
        std.debug.assert(cells_len <= std.math.maxInt(u16));
        return @intCast(cells_len);
    }

    fn resizeRows(self: *RenderState, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        while (self.rows_storage.items.len > rows) {
            const row = self.rows_storage.pop().?;
            allocator.free(row.cells);
            allocator.free(row.highlights);
        }
        while (self.rows_storage.items.len < rows) {
            try self.rows_storage.append(allocator, .{});
        }
        for (self.rows_storage.items) |*row| {
            if (row.cells.len != cols) {
                allocator.free(row.cells);
                row.cells = try allocator.alloc(Cell, cols);
            }
            row.selection = null;
        }
    }

    fn dirtyState(previous_rows: u16, previous_cols: u16, previous_alternate: bool, rows: u16, cols: u16, alternate: bool, dirty_rows: []const u8) Dirty {
        if (previous_rows != rows or previous_cols != cols or previous_alternate != alternate) return .full;
        var dirty_count: u16 = 0;
        for (dirty_rows) |value| dirty_count += if (value != 0) 1 else 0;
        if (dirty_count == 0) return .false;
        if (dirty_count == rows) return .full;
        return .partial;
    }

    fn colorsFromTerminal(vt: *terminal.Terminal) Colors {
        const source = host_state.terminalColorState(vt);
        var out = Colors{
            .background = rgbFromScreen(source.background),
            .foreground = rgbFromScreen(source.foreground),
            .cursor = if (source.cursor) |value| rgbFromScreen(value) else null,
        };
        for (source.palette, 0..) |value, index| out.palette[index] = rgbFromScreen(value);
        return out;
    }

    fn rgbFromScreen(value: screen.Screen.Rgb) Rgb8 {
        return .{ .r = value.r, .g = value.g, .b = value.b };
    }

    fn cursorFromView(view: screen_set.View) Cursor {
        return .{
            .visual_style = switch (view.cursor_shape) {
                .bar => .bar,
                .block => .block,
                .underline => .underline,
                .none => .block_hollow,
            },
            .visible = view.cursor_visible,
            .blinking = view.cursor_blink,
            .viewport = if (view.cursor_visible) .{ .x = view.cursor_col, .y = view.cursor_row, .wide_tail = false } else null,
        };
    }

    fn cellFromScreen(value: screen.Screen.Cell) Cell {
        return .{
            .codepoint = value.codepoint,
            .combining_len = value.combining_len,
            .combining = value.combining,
            .continuation = screen.Screen.isCellContinuation(value),
            .fg_color = colorFromScreen(value.attrs.fg),
            .bg_color = colorFromScreen(value.attrs.bg),
            .underline_color = colorFromScreen(value.attrs.underline_color),
            .underline_style = underlineStyleFromScreen(value.attrs.underline_style),
            .bold = value.attrs.bold,
            .dim = value.attrs.dim,
            .italic = value.attrs.italic,
            .underline = value.attrs.underline,
            .blink = value.attrs.blink or value.attrs.blink_fast,
            .inverse = value.attrs.reverse,
            .invisible = value.attrs.invisible,
            .strikethrough = value.attrs.strikethrough,
            .link_id = value.attrs.link_id,
        };
    }

    fn colorFromScreen(value: screen.Screen.Color) Color {
        return .{
            .kind = switch (value.kind) {
                .default => .default,
                .indexed => .indexed,
                .rgb => .rgb,
            },
            .value = value.value,
        };
    }

    fn underlineStyleFromScreen(value: screen.Screen.UnderlineStyle) UnderlineStyle {
        return switch (value) {
            .straight => .straight,
            .double => .double,
            .curly => .curly,
            .dotted => .dotted,
            .dashed => .dashed,
        };
    }
};

test "render_state empty has no rows before update" {
    var state = RenderState.empty();
    defer state.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 0), state.rowCount());
    try std.testing.expectEqual(RenderState.Dirty.false, state.dirty);
}

test "render_state update copies viewport metadata cells dirty cursor colors and selection" {
    var vt = try terminal.Terminal.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer vt.deinit();
    try std.testing.expect((try vt.feed("aa\r\nbb\r\ncc")).state_changed);
    vt.startSelection(0, 0);
    vt.updateSelection(1, 1);
    vt.finishSelection();
    try std.testing.expect((try vt.feed("\x1b]4;1;#010203\x1b\\\x1b]10;#040506\x1b\\\x1b]11;#070809\x1b\\\x1b]12;#0a0b0c\x1b\\")).state_changed);

    var state = RenderState.empty();
    defer state.deinit(std.testing.allocator);
    try state.update(std.testing.allocator, &vt, 0);

    try std.testing.expectEqual(@as(u16, 2), state.rows);
    try std.testing.expectEqual(@as(u16, 4), state.cols);
    try std.testing.expectEqual(@as(u64, 1), state.history_count);
    try std.testing.expectEqual(@as(u64, 0), state.scrollback_offset);
    try std.testing.expectEqual(@as(usize, 2), state.rows_storage.items.len);
    try std.testing.expect(state.snapshot_seq != 0);
    try std.testing.expect(state.dirty_generation != 0);
    try std.testing.expectEqual(RenderState.Dirty.full, state.dirty);
    try std.testing.expectEqual(@as(u32, 'b'), state.rows_storage.items[0].cells[0].codepoint);
    try std.testing.expectEqual(@as(u32, 'c'), state.rows_storage.items[1].cells[0].codepoint);
    try std.testing.expectEqual(@as(u16, 2), state.cursor.viewport.?.x);
    try std.testing.expectEqual(@as(u16, 1), state.cursor.viewport.?.y);
    try std.testing.expectEqual(false, state.cursor.viewport.?.wide_tail);
    try std.testing.expectEqual(RenderState.Rgb8{ .r = 4, .g = 5, .b = 6 }, state.colors.foreground);
    try std.testing.expectEqual(RenderState.Rgb8{ .r = 7, .g = 8, .b = 9 }, state.colors.background);
    try std.testing.expectEqual(RenderState.Rgb8{ .r = 10, .g = 11, .b = 12 }, state.colors.cursor.?);
    try std.testing.expectEqual(RenderState.Rgb8{ .r = 1, .g = 2, .b = 3 }, state.colors.palette[1]);
    try std.testing.expectEqual(RenderState.SelectionRange{ .start_col = 0, .end_col = 2 }, state.rows_storage.items[0].selection.?);

    try std.testing.expect(state.ack(&vt));
    try state.update(std.testing.allocator, &vt, 0);
    try std.testing.expectEqual(RenderState.Dirty.false, state.dirty);

    try std.testing.expect((try vt.feed("dd")).state_changed);
    try state.update(std.testing.allocator, &vt, 0);
    try std.testing.expectEqual(RenderState.Dirty.partial, state.dirty);

    try std.testing.expect((try vt.feed("ee")).state_changed);
    try std.testing.expect(!state.ack(&vt));
    try std.testing.expectEqual(RenderState.Dirty.partial, state.dirty);
    try std.testing.expect(state.rows_storage.items[1].dirty);

    try state.update(std.testing.allocator, &vt, 1);
    try std.testing.expectEqual(@as(u64, 1), state.scrollback_offset);
    try std.testing.expectEqual(RenderState.SelectionRange{ .start_col = 0, .end_col = 2 }, state.rows_storage.items[0].selection.?);
}

test "render_state update preserves full surface cell facts" {
    var vt = try terminal.Terminal.initWithCellsAndHistory(std.testing.allocator, 1, 4, 4);
    defer vt.deinit();
    const source = "\x1b]8;;https://example.com\x07\x1b[1;2;3;4;5;7;8;9;38;2;1;2;3;48;5;200;58;2;4;5;6mA\xcc\x81\x1b]8;;\x07";
    try std.testing.expect((try vt.feed(source)).state_changed);

    var state = RenderState.empty();
    defer state.deinit(std.testing.allocator);
    try state.update(std.testing.allocator, &vt, 0);

    const cell = state.rows_storage.items[0].cells[0];
    try std.testing.expectEqual(@as(u32, 'A'), cell.codepoint);
    try std.testing.expectEqual(@as(u8, 1), cell.combining_len);
    try std.testing.expectEqual(@as(u32, 0x0301), cell.combining[0]);
    try std.testing.expectEqual(RenderState.Color{ .kind = .rgb, .value = 0x010203 }, cell.fg_color);
    try std.testing.expectEqual(RenderState.Color{ .kind = .indexed, .value = 200 }, cell.bg_color);
    try std.testing.expectEqual(RenderState.Color{ .kind = .rgb, .value = 0x040506 }, cell.underline_color);
    try std.testing.expectEqual(RenderState.UnderlineStyle.straight, cell.underline_style);
    try std.testing.expect(cell.bold);
    try std.testing.expect(cell.dim);
    try std.testing.expect(cell.italic);
    try std.testing.expect(cell.underline);
    try std.testing.expect(cell.blink);
    try std.testing.expect(cell.inverse);
    try std.testing.expect(cell.invisible);
    try std.testing.expect(cell.strikethrough);
    try std.testing.expect(cell.link_id != 0);
}
