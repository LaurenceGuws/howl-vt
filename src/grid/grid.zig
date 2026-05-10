//! Responsibility: own grid cursor, cell, margin, history state, and screen actions.
//! Ownership: terminal grid instance authority.
//! Reason: centralize deterministic screen mutations behind typed screen actions.

const std = @import("std");
const interpret = @import("../interpret/interpret.zig");
const cursor = @import("cursor.zig");
const dirty = @import("dirty.zig");
const edit = @import("edit.zig");
const erase = @import("erase.zig");
const grid_apply = @import("apply.zig");
const history_mod = @import("history.zig");
const margins = @import("margins.zig");
const rect = @import("rect.zig");
const scroll = @import("scroll.zig");
const style_mod = @import("style.zig");
const tabs = @import("tabs.zig");
const types = @import("types.zig");
const write = @import("write.zig");

/// Semantic event alias for grid application.
const SemanticEvent = interpret.SemanticEvent;
const ScreenAction = interpret.ScreenAction;
const LogicalLine = history_mod.LogicalLine;
const HistoryLine = history_mod.HistoryLine;
const RewrappedRow = history_mod.RewrappedRow;

/// Terminal screen state for cursor, cells, margins, and history.
pub const Grid = struct {
    pub const Color = types.Color;
    pub const UnderlineStyle = types.UnderlineStyle;
    pub const CellAttrs = types.CellAttrs;
    pub const Cell = types.Cell;
    pub const CursorShape = types.CursorShape;
    pub const CursorStyle = types.CursorStyle;
    pub const default_fg = types.default_fg;
    pub const default_bg = types.default_bg;
    pub const default_cell_attrs = types.default_cell_attrs;
    pub const default_cell = types.default_cell;
    pub const defaultCell = types.defaultCell;
    pub const isCellContinuation = types.isCellContinuation;
    pub const DirtyRows = dirty.DirtyRows;

    allocator: ?std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    wrap_pending: bool,
    cursor_visible: bool,
    cursor_style: CursorStyle,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    left_right_margin_mode: bool,
    left_margin: u16,
    right_margin: u16,
    attr_change_extent_rect: bool,
    view_padding_rows: u16,
    row_origin: u16,
    scroll_top: u16,
    scroll_bottom: u16,
    cells: ?[]Cell,
    row_wraps: ?[]bool,
    history: ?[]Cell,
    history_wraps: ?[]bool,
    history_capacity: u16,
    history_count: usize,
    history_write_idx: usize,
    history_lines: std.ArrayListUnmanaged(HistoryLine),
    history_lines_start: usize,
    open_history_line: ?HistoryLine,
    open_history_reuse_slot: ?usize,
    saved_cursor: ?struct {
        row: u16,
        col: u16,
        wrap_pending: bool,
    },
    last_graphic_codepoint: ?u21,
    current_attrs: CellAttrs,
    dirty_rows: ?DirtyRows,
    dirty_cols_start: ?[]u16,
    dirty_cols_end: ?[]u16,
    tab_stops: ?[]bool,

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) Grid {
        return .{
            .allocator = null,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .cursor_style = types.default_cursor_style,
            .auto_wrap = true,
            .origin_mode = false,
            .insert_mode = false,
            .left_right_margin_mode = false,
            .left_margin = 0,
            .right_margin = cols -| 1,
            .attr_change_extent_rect = false,
            .view_padding_rows = 0,
            .row_origin = 0,
            .scroll_top = 0,
            .scroll_bottom = rows -| 1,
            .cells = null,
            .row_wraps = null,
            .history = null,
            .history_wraps = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
            .history_lines = .empty,
            .history_lines_start = 0,
            .open_history_line = null,
            .open_history_reuse_slot = null,
            .saved_cursor = null,
            .last_graphic_codepoint = null,
            .current_attrs = default_cell_attrs,
            .dirty_rows = null,
            .dirty_cols_start = null,
            .dirty_cols_end = null,
            .tab_stops = null,
        };
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Grid {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]Cell = if (size > 0) blk: {
            const buf = try allocator.alloc(Cell, size);
            @memset(buf, default_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        errdefer if (row_wraps) |buf| allocator.free(buf);
        const dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try tabs.allocTabStops(allocator, cols);
        errdefer if (tab_stops) |buf| allocator.free(buf);
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .cursor_style = types.default_cursor_style,
            .auto_wrap = true,
            .origin_mode = false,
            .insert_mode = false,
            .left_right_margin_mode = false,
            .left_margin = 0,
            .right_margin = cols -| 1,
            .attr_change_extent_rect = false,
            .view_padding_rows = 0,
            .row_origin = 0,
            .scroll_top = 0,
            .scroll_bottom = rows -| 1,
            .cells = cells,
            .row_wraps = row_wraps,
            .history = null,
            .history_wraps = null,
            .history_capacity = 0,
            .history_count = 0,
            .history_write_idx = 0,
            .history_lines = .empty,
            .history_lines_start = 0,
            .open_history_line = null,
            .open_history_reuse_slot = null,
            .saved_cursor = null,
            .last_graphic_codepoint = null,
            .current_attrs = default_cell_attrs,
            .dirty_rows = dirty.rowsForFull(rows, dirty_cols_start, dirty_cols_end),
            .dirty_cols_start = dirty_cols_start,
            .dirty_cols_end = dirty_cols_end,
            .tab_stops = tab_stops,
        };
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Grid {
        const size = @as(usize, rows) * @as(usize, cols);
        const cells: ?[]Cell = if (size > 0) blk: {
            const buf = try allocator.alloc(Cell, size);
            @memset(buf, default_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        errdefer if (row_wraps) |buf| allocator.free(buf);
        const dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try tabs.allocTabStops(allocator, cols);
        errdefer if (tab_stops) |buf| allocator.free(buf);
        const history: ?[]Cell = if (cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(Cell, 0);
            break :blk buf;
        } else null;
        errdefer if (history) |buf| allocator.free(buf);
        const history_wraps: ?[]bool = if (cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(bool, 0);
            break :blk buf;
        } else null;
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor_row = 0,
            .cursor_col = 0,
            .wrap_pending = false,
            .cursor_visible = true,
            .cursor_style = types.default_cursor_style,
            .auto_wrap = true,
            .origin_mode = false,
            .insert_mode = false,
            .left_right_margin_mode = false,
            .left_margin = 0,
            .right_margin = cols -| 1,
            .attr_change_extent_rect = false,
            .view_padding_rows = 0,
            .row_origin = 0,
            .scroll_top = 0,
            .scroll_bottom = rows -| 1,
            .cells = cells,
            .row_wraps = row_wraps,
            .history = history,
            .history_wraps = history_wraps,
            .history_capacity = if (cells != null) history_capacity else 0,
            .history_count = 0,
            .history_write_idx = 0,
            .history_lines = .empty,
            .history_lines_start = 0,
            .open_history_line = null,
            .open_history_reuse_slot = null,
            .saved_cursor = null,
            .last_graphic_codepoint = null,
            .current_attrs = default_cell_attrs,
            .dirty_rows = dirty.rowsForFull(rows, dirty_cols_start, dirty_cols_end),
            .dirty_cols_start = dirty_cols_start,
            .dirty_cols_end = dirty_cols_end,
            .tab_stops = tab_stops,
        };
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *Grid, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.row_wraps) |buf| allocator.free(buf);
        self.row_wraps = null;
        if (self.dirty_cols_start) |buf| allocator.free(buf);
        self.dirty_cols_start = null;
        if (self.dirty_cols_end) |buf| allocator.free(buf);
        self.dirty_cols_end = null;
        if (self.tab_stops) |buf| allocator.free(buf);
        self.tab_stops = null;
        if (self.history) |h| allocator.free(h);
        self.history = null;
        if (self.history_wraps) |buf| allocator.free(buf);
        self.history_wraps = null;
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.deinit(allocator);
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
    }

    /// Resize visible grid while preserving retained history rows.
    pub fn resize(self: *Grid, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        self.allocator = allocator;
        try self.resizeWithReflow(allocator, rows, cols);
    }

    fn resizeWithReflow(self: *Grid, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        const old_cells = self.cells;
        const old_row_wraps = self.row_wraps;
        const old_dirty_cols_start = self.dirty_cols_start;
        const old_dirty_cols_end = self.dirty_cols_end;
        const old_tab_stops = self.tab_stops;
        const old_rows = self.rows;
        const old_history = self.history;
        const old_history_wraps = self.history_wraps;

        var logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty;
        defer {
            for (logical_lines.items) |*line| line.cells.deinit(allocator);
            logical_lines.deinit(allocator);
        }

        var current_line = try history_mod.cloneOpenHistoryAsLogicalLine(self, allocator);
        defer current_line.cells.deinit(allocator);

        var cursor_line_index: usize = 0;
        var cursor_offset: usize = 0;
        var cursor_found = false;

        var history_line_idx: usize = 0;
        while (history_line_idx < self.history_lines.items.len) : (history_line_idx += 1) {
            const line = history_mod.historyLineAt(self, history_line_idx);
            var copied = try history_mod.cloneHistoryLine(allocator, line.cells.items);
            copied.cursor_offset = null;
            try logical_lines.append(allocator, copied);
        }

        var row: u16 = 0;
        while (row < old_rows) : (row += 1) {
            try history_mod.appendSourceRowToLogicalLines(
                self,
                allocator,
                &logical_lines,
                &current_line,
                row,
                self.cols,
                &cursor_found,
                &cursor_line_index,
                &cursor_offset,
            );
        }

        if (current_line.cells.items.len > 0 or current_line.cursor_offset != null or logical_lines.items.len == 0) {
            if (current_line.cursor_offset) |offset| {
                cursor_found = true;
                cursor_line_index = logical_lines.items.len;
                cursor_offset = offset;
            }
            try logical_lines.append(allocator, current_line);
            current_line = .{};
        }

        while (logical_lines.items.len > 1) {
            const last_idx = logical_lines.items.len - 1;
            const last = &logical_lines.items[last_idx];
            if (last.cells.items.len > 0) break;
            if (cursor_found and cursor_line_index == last_idx) break;
            last.cells.deinit(allocator);
            logical_lines.items.len = last_idx;
        }

        var flat_rows: std.ArrayListUnmanaged(Cell) = .empty;
        defer flat_rows.deinit(allocator);
        var rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty;
        defer rewrapped.deinit(allocator);
        var line_row_starts: std.ArrayListUnmanaged(usize) = .empty;
        defer line_row_starts.deinit(allocator);
        var line_row_counts: std.ArrayListUnmanaged(usize) = .empty;
        defer line_row_counts.deinit(allocator);

        var global_cursor_row: usize = 0;
        var global_cursor_col: usize = 0;
        var next_wrap_pending = false;
        var row_cursor_base: usize = 0;

        for (logical_lines.items, 0..) |line, line_idx| {
            const has_cursor = cursor_found and cursor_line_index == line_idx;
            const line_cursor_offset = if (has_cursor) @min(cursor_offset, line.cells.items.len) else 0;
            const effective_len = line.cells.items.len;
            const row_count: usize = if (cols == 0) 0 else @max(1, std.math.divCeil(usize, effective_len, cols) catch unreachable);
            try line_row_starts.append(allocator, rewrapped.items.len);
            try line_row_counts.append(allocator, row_count);

            if (has_cursor) {
                if (cols == 0) {
                    global_cursor_row = 0;
                    global_cursor_col = 0;
                    next_wrap_pending = false;
                } else if (line_cursor_offset > 0 and line_cursor_offset % cols == 0) {
                    global_cursor_row = row_cursor_base + (line_cursor_offset / cols) - 1;
                    global_cursor_col = cols - 1;
                    next_wrap_pending = true;
                } else {
                    global_cursor_row = row_cursor_base + (line_cursor_offset / cols);
                    global_cursor_col = line_cursor_offset % cols;
                    next_wrap_pending = false;
                }
            }

            if (cols == 0) continue;

            if (row_count == 0) unreachable;
            var row_idx: usize = 0;
            while (row_idx < row_count) : (row_idx += 1) {
                const start = row_idx * @as(usize, cols);
                const end = @min(effective_len, start + @as(usize, cols));
                try rewrapped.append(allocator, .{
                    .start = flat_rows.items.len,
                    .len = end - start,
                    .wrapped = row_idx + 1 < row_count,
                });

                var col_idx: usize = 0;
                while (col_idx < @as(usize, cols)) : (col_idx += 1) {
                    const src_idx = start + col_idx;
                    if (src_idx < line.cells.items.len) {
                        try flat_rows.append(allocator, line.cells.items[src_idx]);
                    } else {
                        try flat_rows.append(allocator, default_cell);
                    }
                }
            }

            row_cursor_base += row_count;
        }

        const total_rows = rewrapped.items.len;
        const visible_rows_kept: usize = @min(@as(usize, rows), total_rows);
        const visible_start = total_rows - visible_rows_kept;
        const top_blank_rows: usize = 0;
        const first_visible_line = history_mod.firstLineForRow(line_row_starts.items, line_row_counts.items, visible_start) orelse logical_lines.items.len;
        const hidden_rows_in_first_visible_line: usize = if (first_visible_line < logical_lines.items.len)
            visible_start - line_row_starts.items[first_visible_line]
        else
            0;

        const cell_count = @as(usize, rows) * @as(usize, cols);
        var new_cells: ?[]Cell = null;
        if (cell_count > 0) {
            const buf = try allocator.alloc(Cell, cell_count);
            @memset(buf, default_cell);
            new_cells = buf;
        }
        errdefer if (new_cells) |buf| allocator.free(buf);

        var new_row_wraps: ?[]bool = null;
        if (rows > 0) {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            new_row_wraps = buf;
        }
        errdefer if (new_row_wraps) |buf| allocator.free(buf);
        const new_dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
        errdefer if (new_dirty_cols_start) |buf| allocator.free(buf);
        const new_dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (new_dirty_cols_end) |buf| allocator.free(buf);
        const new_tab_stops = try tabs.allocTabStops(allocator, cols);
        errdefer if (new_tab_stops) |buf| allocator.free(buf);
        tabs.copyTabStops(new_tab_stops, old_tab_stops);

        if (new_cells) |dst| {
            const dst_wraps = new_row_wraps.?;
            var src_row: usize = visible_start;
            var view_row: usize = 0;
            while (view_row < visible_rows_kept) : ({
                view_row += 1;
                src_row += 1;
            }) {
                const src = rewrapped.items[src_row];
                const dst_row = top_blank_rows + view_row;
                const dst_start = dst_row * @as(usize, cols);
                @memcpy(dst[dst_start .. dst_start + @as(usize, cols)], flat_rows.items[src.start .. src.start + @as(usize, cols)]);
                dst_wraps[dst_row] = src.wrapped;
            }
        }

        self.rows = rows;
        self.cols = cols;
        self.cells = new_cells;
        self.row_wraps = new_row_wraps;
        self.dirty_cols_start = new_dirty_cols_start;
        self.dirty_cols_end = new_dirty_cols_end;
        self.tab_stops = new_tab_stops;
        self.history = null;
        self.history_wraps = null;
        self.history_count = 0;
        self.history_write_idx = 0;
        self.row_origin = 0;
        self.view_padding_rows = 0;
        self.scroll_top = 0;
        self.scroll_bottom = rows -| 1;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = cols -| 1;
        self.attr_change_extent_rect = false;
        self.dirty_rows = dirty.rowsForFull(rows, new_dirty_cols_start, new_dirty_cols_end);

        try history_mod.replaceAuthority(
            self,
            allocator,
            logical_lines.items,
            line_row_starts.items,
            line_row_counts.items,
            first_visible_line,
            hidden_rows_in_first_visible_line,
            rewrapped.items,
            cols,
        );
        try history_mod.rebuildProjection(self, allocator);

        if (rows == 0 or cols == 0 or total_rows == 0) {
            self.cursor_row = 0;
            self.cursor_col = 0;
            self.wrap_pending = false;
        } else {
            const clamped_cursor_row = std.math.clamp(global_cursor_row, visible_start, visible_start + visible_rows_kept - 1);
            self.cursor_row = @intCast(top_blank_rows + (clamped_cursor_row - visible_start));
            self.cursor_col = @intCast(@min(global_cursor_col, @as(usize, cols - 1)));
            self.wrap_pending = next_wrap_pending and self.cursor_row < rows and self.cursor_col == cols - 1;
        }

        if (old_cells) |buf| allocator.free(buf);
        if (old_row_wraps) |buf| allocator.free(buf);
        if (old_dirty_cols_start) |buf| allocator.free(buf);
        if (old_dirty_cols_end) |buf| allocator.free(buf);
        if (old_tab_stops) |buf| allocator.free(buf);
        if (old_history) |buf| allocator.free(buf);
        if (old_history_wraps) |buf| allocator.free(buf);
    }

    pub fn storeHistoryRow(self: *Grid, row: u16) void {
        history_mod.storeRow(self, row);
    }

    fn clearHistoryAuthority(self: *Grid, allocator: std.mem.Allocator) void {
        history_mod.clearAuthority(self, allocator);
    }

    /// Reset visible grid state to defaults.
    pub fn reset(self: *Grid) void {
        self.cursor_row = 0;
        self.cursor_col = 0;
        self.wrap_pending = false;
        self.cursor_visible = true;
        self.cursor_style = types.default_cursor_style;
        self.auto_wrap = true;
        self.origin_mode = false;
        self.insert_mode = false;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = self.cols -| 1;
        self.attr_change_extent_rect = false;
        self.view_padding_rows = 0;
        self.row_origin = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.saved_cursor = null;
        self.last_graphic_codepoint = null;
        self.current_attrs = default_cell_attrs;
        self.markAllRowsDirty();
        if (self.cells) |c| @memset(c, default_cell);
        if (self.row_wraps) |buf| @memset(buf, false);
        if (self.tab_stops) |stops| tabs.setDefaultTabStops(stops);
    }

    pub fn peekDirtyRows(self: *const Grid) ?DirtyRows {
        return self.dirty_rows;
    }

    pub fn clearDirtyRows(self: *Grid) void {
        self.dirty_rows = null;
        if (self.dirty_cols_start) |buf| @memset(buf, self.cols);
        if (self.dirty_cols_end) |buf| @memset(buf, 0);
    }

    pub fn markAllDirty(self: *Grid) void {
        self.markAllRowsDirty();
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const Grid, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    pub fn cellInfoAt(self: *const Grid, row: u16, col: u16) Cell {
        const c = self.cells orelse return default_cell;
        if (row >= self.rows or col >= self.cols) return default_cell;
        const start = self.rowStart(row);
        return c[start + @as(usize, col)];
    }

    pub fn tabStopAt(self: *const Grid, col: u16) bool {
        return self.isTabStop(col);
    }

    pub fn insertMode(self: *const Grid) bool {
        return self.insert_mode;
    }

    pub fn rectBoundsForReport(self: *const Grid, area: SemanticEvent.RectArea) ?struct { top: u16, left: u16, bottom: u16, right: u16 } {
        const bounds = self.rectBounds(area) orelse return null;
        return .{ .top = bounds.top, .left = bounds.left, .bottom = bounds.bottom, .right = bounds.right };
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const Grid, history_idx: usize, col: u16) u21 {
        return @intCast(self.historyCellAt(history_idx, col).codepoint);
    }

    pub fn historyCellAt(self: *const Grid, history_idx: usize, col: u16) Cell {
        const h = self.history orelse return default_cell;
        if (history_idx >= self.history_count or col >= self.cols) return default_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return default_cell;
        return h[slot * @as(usize, self.cols) + @as(usize, col)];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const Grid) usize {
        return self.history_count;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const Grid) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const Grid, endpoint_row: i32) bool {
        if (self.history_capacity == 0 or self.history_lines.items.len < self.history_capacity) {
            return false;
        }
        const projected_rows_i32: i32 = if (self.history_count > @as(usize, std.math.maxInt(i32)))
            std.math.maxInt(i32)
        else
            @intCast(self.history_count);
        if (endpoint_row < -projected_rows_i32) {
            return true;
        }
        return false;
    }

    /// Apply one terminal event to screen state.
    pub fn apply(self: *Grid, event: SemanticEvent) void {
        const action = interpret.screenAction(event) orelse return;
        self.applyScreen(action);
    }

    pub fn applyScreen(self: *Grid, event: ScreenAction) void {
        grid_apply.applyScreen(self, event);
    }

    pub const RectBounds = struct {
        top: u16,
        left: u16,
        bottom: u16,
        right: u16,
    };

    pub fn eraseDisplay(self: *Grid, mode: u2) void {
        erase.eraseDisplay(self, mode);
    }

    pub fn setCurrentLinkId(self: *Grid, link_id: u32) void {
        self.current_attrs.link_id = link_id;
    }

    pub fn resolveAbsoluteRow(self: *const Grid, row: u16) u16 {
        return cursor.resolveAbsoluteRow(self, row);
    }

    pub fn resolveAbsoluteCol(self: *const Grid, col: u16) u16 {
        return cursor.resolveAbsoluteCol(self, col);
    }

    pub fn saveCursor(self: *Grid) void {
        cursor.save(self);
    }

    pub fn restoreCursor(self: *Grid) void {
        cursor.restore(self);
    }

    pub fn lineHomeCol(self: *const Grid) u16 {
        return cursor.lineHomeCol(self);
    }

    pub fn leftBoundary(self: *const Grid) u16 {
        return cursor.leftBoundary(self);
    }

    pub fn rightBoundary(self: *const Grid) u16 {
        return cursor.rightBoundary(self);
    }

    pub fn clearScrollback(self: *Grid) void {
        const allocator = self.allocator orelse return;
        self.clearHistoryAuthority(allocator);
        self.history_count = 0;
        self.history_write_idx = 0;
        self.markAllRowsDirty();
    }

    pub fn eraseLine(self: *Grid, mode: u2) void {
        erase.eraseLine(self, mode);
    }

    pub fn eraseChars(self: *Grid, count: u16) void {
        erase.eraseChars(self, count);
    }

    pub fn changeRectAttrs(self: *Grid, area: SemanticEvent.RectArea, attrs: []const u16, reverse: bool) void {
        rect.changeAttrs(self, area, attrs, reverse);
    }

    pub fn selectiveEraseDisplay(self: *Grid, mode: u2) void {
        erase.selectiveEraseDisplay(self, mode);
    }

    pub fn selectiveEraseLine(self: *Grid, mode: u2) void {
        erase.selectiveEraseLine(self, mode);
    }

    pub fn eraseRect(self: *Grid, area: SemanticEvent.RectArea, selective: bool) void {
        rect.erase(self, area, selective);
    }

    pub fn fillRect(self: *Grid, area: SemanticEvent.RectArea, ch: u21) void {
        rect.fill(self, area, ch);
    }

    pub fn copyRect(self: *Grid, req: SemanticEvent.RectCopy) void {
        rect.copy(self, req);
    }

    pub fn insertColumns(self: *Grid, count: u16) void {
        edit.insertColumns(self, count);
    }

    pub fn deleteColumns(self: *Grid, count: u16) void {
        edit.deleteColumns(self, count);
    }

    pub fn shiftColumnsLeft(self: *Grid, count: u16) void {
        edit.shiftColumnsLeft(self, count);
    }

    pub fn shiftColumnsRight(self: *Grid, count: u16) void {
        edit.shiftColumnsRight(self, count);
    }

    pub fn insertChars(self: *Grid, count: u16) void {
        edit.insertChars(self, count);
    }

    pub fn deleteChars(self: *Grid, count: u16) void {
        edit.deleteChars(self, count);
    }

    pub fn writeCell(self: *Grid, cp: u21) void {
        write.writeCell(self, cp);
    }

    pub fn writeText(self: *Grid, text: []const u8) void {
        write.writeText(self, text);
    }

    pub fn repeatPreceding(self: *Grid, count: u16) void {
        write.repeatPreceding(self, count);
    }

    pub fn applySgr(self: *Grid, params: []const i32, separators: []const u8) void {
        style_mod.applySgr(self, params, separators);
    }

    pub fn horizontalTabForward(self: *Grid, count: u16) void {
        tabs.horizontalForward(self, count);
    }

    pub fn horizontalTabBack(self: *Grid, count: u16) void {
        tabs.horizontalBack(self, count);
    }

    fn isTabStop(self: *const Grid, col: u16) bool {
        return tabs.isStop(self, col);
    }

    pub fn setTabStop(self: *Grid) void {
        tabs.setStop(self);
    }

    pub fn clearCurrentTabStop(self: *Grid) void {
        tabs.clearCurrentStop(self);
    }

    pub fn clearAllTabStops(self: *Grid) void {
        tabs.clearAllStops(self);
    }

    pub fn resetDefaultTabStops(self: *Grid) void {
        tabs.resetDefaultStops(self);
    }

    pub fn lineFeed(self: *Grid) void {
        scroll.lineFeed(self);
    }

    pub fn reverseIndex(self: *Grid) void {
        scroll.reverseIndex(self);
    }

    fn scrollUp(self: *Grid) void {
        scroll.scrollUp(self);
    }

    pub fn scrollBottom(self: *const Grid) u16 {
        return if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    }

    pub fn setScrollRegion(self: *Grid, top: u16, bottom: ?u16) void {
        margins.setScrollRegion(self, top, bottom);
    }

    pub fn setLeftRightMarginMode(self: *Grid, enabled: bool) void {
        margins.setLeftRightMode(self, enabled);
    }

    pub fn setLeftRightMargins(self: *Grid, left: u16, right: ?u16) void {
        margins.setLeftRightMargins(self, left, right);
    }

    pub fn insertLines(self: *Grid, count: u16) void {
        scroll.insertLines(self, count);
    }

    pub fn deleteLines(self: *Grid, count: u16) void {
        scroll.deleteLines(self, count);
    }

    pub fn scrollUpRegion(self: *Grid, top: u16, bottom: u16, count: u16) void {
        scroll.scrollUpRegion(self, top, bottom, count);
    }

    pub fn scrollDownRegion(self: *Grid, top: u16, bottom: u16, count: u16) void {
        scroll.scrollDownRegion(self, top, bottom, count);
    }

    pub fn rowStart(self: *const Grid, logical_row: u16) usize {
        const physical_row = (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
        return physical_row * @as(usize, self.cols);
    }

    fn rowWrapIndex(self: *const Grid, logical_row: u16) ?usize {
        _ = self.row_wraps orelse return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
    }

    pub fn rowWrapped(self: *const Grid, logical_row: u16) bool {
        const wraps = self.row_wraps orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return wraps[idx];
    }

    pub fn setRowWrapped(self: *Grid, logical_row: u16, wrapped: bool) void {
        const wraps = self.row_wraps orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        wraps[idx] = wrapped;
    }

    fn historySlotForLogicalRow(self: *const Grid, logical_row: usize) ?usize {
        return history_mod.slotForLogicalRow(self, logical_row);
    }

    fn historySlotForRecency(self: *const Grid, history_idx: usize) ?usize {
        return history_mod.slotForRecency(self, history_idx);
    }

    fn historyRowWrapped(self: *const Grid, history_idx: usize) bool {
        return history_mod.rowWrapped(self, history_idx);
    }

    pub fn clearRowRange(self: *Grid, row: u16, start_col: u16, end_col_exclusive: u16) void {
        erase.clearRowRange(self, row, start_col, end_col_exclusive);
    }

    pub fn selectiveClearRowRange(self: *Grid, row: u16, start_col: u16, end_col_exclusive: u16) void {
        erase.selectiveClearRowRange(self, row, start_col, end_col_exclusive);
    }

    pub fn rectBounds(self: *const Grid, area: SemanticEvent.RectArea) ?RectBounds {
        if (self.rows == 0 or self.cols == 0) return null;
        const row_base: u16 = if (self.origin_mode) self.scroll_top else 0;
        const row_limit: u16 = if (self.origin_mode) self.scrollBottom() else self.rows - 1;
        const row_span = row_limit -| row_base;
        const top = row_base + @min(area.top, row_span);
        const bottom = row_base + @min(area.bottom orelse row_span, row_span);
        const left = @min(area.left, self.cols - 1);
        const right = @min(area.right orelse self.cols - 1, self.cols - 1);
        if (top > bottom or left > right) return null;
        return .{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    pub fn eraseCell(self: *const Grid) Cell {
        return erase.eraseCell(self);
    }

    fn clearFullRow(self: *Grid, row: u16) void {
        erase.clearFullRow(self, row);
    }

    fn copyRow(self: *Grid, dst_row: u16, src_row: u16) void {
        const c = self.cells orelse return;
        const row_len = @as(usize, self.cols);
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(Cell, c[dst_start .. dst_start + row_len], c[src_start .. src_start + row_len]);
        self.setRowWrapped(dst_row, self.rowWrapped(src_row));
    }

    pub fn copyRowRange(self: *Grid, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(Cell, c[dst_start + start_col .. dst_start + end_col_exclusive], c[src_start + start_col .. src_start + end_col_exclusive]);
        self.setRowWrapped(dst_row, false);
    }

    pub fn markDirtyRow(self: *Grid, row: u16) void {
        dirty.markRow(self, row);
    }

    pub fn markDirtyCols(self: *Grid, row: u16, start_col: u16, end_col: u16) void {
        dirty.markCols(self, row, start_col, end_col);
    }

    pub fn markDirtyRows(self: *Grid, start_row: u16, end_row: u16) void {
        dirty.markRows(self, start_row, end_row);
    }

    pub fn markAllRowsDirty(self: *Grid) void {
        dirty.markAllRows(self);
    }
};
