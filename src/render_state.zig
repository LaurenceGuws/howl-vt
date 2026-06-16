const std = @import("std");

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
        selected: bool = false,
        highlighted: bool = false,
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

    pub fn update(self: *RenderState) void {
        std.debug.assert(self.rows_storage.items.len == self.rows);
    }

    pub fn ack(self: *RenderState) void {
        self.dirty = .false;
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
};

test "render_state empty has no rows before update" {
    var state = RenderState.empty();
    defer state.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 0), state.rowCount());
    try std.testing.expectEqual(RenderState.Dirty.false, state.dirty);
}
