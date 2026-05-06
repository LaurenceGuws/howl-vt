//! Responsibility: hold grid cursor/cell/history state and apply semantics.
//! Ownership: terminal grid model authority.
//! Reason: centralize deterministic grid mutations behind semantic operations.

const std = @import("std");
const interpret_owner = @import("../interpret.zig");
const types = @import("types.zig");

/// Semantic event alias for grid application.
const SemanticEvent = interpret_owner.Interpret.SemanticEvent;
const Cell = types.Cell;
const Color = types.Color;
const CellAttrs = types.CellAttrs;
const CursorStyle = types.CursorStyle;
const default_cell = types.default_cell;
const default_cell_attrs = types.default_cell_attrs;
const default_underline_color = types.default_underline_color;

const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,
    cursor_offset: ?usize = null,
};

const HistoryLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,

    fn deinit(self: *HistoryLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

const RewrappedRow = struct {
    start: usize,
    len: usize,
    wrapped: bool,
};

fn allocDirtyCols(allocator: std.mem.Allocator, rows: u16, initial: u16) !?[]u16 {
    if (rows == 0) return null;
    const buf = try allocator.alloc(u16, rows);
    @memset(buf, initial);
    return buf;
}

fn allocTabStops(allocator: std.mem.Allocator, cols: u16) !?[]bool {
    if (cols == 0) return null;
    const buf = try allocator.alloc(bool, cols);
    setDefaultTabStops(buf);
    return buf;
}

fn setDefaultTabStops(stops: []bool) void {
    @memset(stops, false);
    for (stops, 0..) |*stop, idx| {
        if (idx != 0 and idx % 8 == 0) stop.* = true;
    }
}

fn copyTabStops(dst: ?[]bool, src: ?[]const bool) void {
    const d = dst orelse return;
    setDefaultTabStops(d);
    const s = src orelse return;
    @memcpy(d[0..@min(d.len, s.len)], s[0..@min(d.len, s.len)]);
}

fn dirtyRowsForFull(rows: u16, dirty_cols_start: ?[]const u16, dirty_cols_end: ?[]const u16) ?DirtyRows {
    if (rows == 0) return null;
    return .{
        .start_row = 0,
        .end_row = rows -| 1,
        .dirty_cols_start = dirty_cols_start orelse &.{},
        .dirty_cols_end = dirty_cols_end orelse &.{},
    };
}

pub const DirtyRows = struct {
    start_row: u16,
    end_row: u16,
    dirty_cols_start: []const u16 = &.{},
    dirty_cols_end: []const u16 = &.{},
};

/// Terminal grid model for cursor/cell/history behavior.
pub const GridModel = struct {
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
    pub fn init(rows: u16, cols: u16) GridModel {
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
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !GridModel {
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
        const dirty_cols_start = try allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try allocTabStops(allocator, cols);
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
            .dirty_rows = dirtyRowsForFull(rows, dirty_cols_start, dirty_cols_end),
            .dirty_cols_start = dirty_cols_start,
            .dirty_cols_end = dirty_cols_end,
            .tab_stops = tab_stops,
        };
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !GridModel {
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
        const dirty_cols_start = try allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try allocTabStops(allocator, cols);
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
            .dirty_rows = dirtyRowsForFull(rows, dirty_cols_start, dirty_cols_end),
            .dirty_cols_start = dirty_cols_start,
            .dirty_cols_end = dirty_cols_end,
            .tab_stops = tab_stops,
        };
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *GridModel, allocator: std.mem.Allocator) void {
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
    pub fn resize(self: *GridModel, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        self.allocator = allocator;
        try self.resizeWithReflow(allocator, rows, cols);
    }

    fn resizeWithReflow(self: *GridModel, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
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

        var current_line = try self.cloneOpenHistoryAsLogicalLine(allocator);
        defer current_line.cells.deinit(allocator);

        var cursor_line_index: usize = 0;
        var cursor_offset: usize = 0;
        var cursor_found = false;

        var history_line_idx: usize = 0;
        while (history_line_idx < self.history_lines.items.len) : (history_line_idx += 1) {
            const line = self.historyLineAt(history_line_idx);
            var copied = try cloneHistoryLine(allocator, line.cells.items);
            copied.cursor_offset = null;
            try logical_lines.append(allocator, copied);
        }

        var row: u16 = 0;
        while (row < old_rows) : (row += 1) {
            try self.appendSourceRowToLogicalLines(
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
        const first_visible_line = firstLineForRow(line_row_starts.items, line_row_counts.items, visible_start) orelse logical_lines.items.len;
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
        const new_dirty_cols_start = try allocDirtyCols(allocator, rows, 0);
        errdefer if (new_dirty_cols_start) |buf| allocator.free(buf);
        const new_dirty_cols_end = try allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (new_dirty_cols_end) |buf| allocator.free(buf);
        const new_tab_stops = try allocTabStops(allocator, cols);
        errdefer if (new_tab_stops) |buf| allocator.free(buf);
        copyTabStops(new_tab_stops, old_tab_stops);

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
        self.dirty_rows = dirtyRowsForFull(rows, new_dirty_cols_start, new_dirty_cols_end);

        try self.replaceHistoryAuthority(
            allocator,
            logical_lines.items,
            line_row_starts.items,
            line_row_counts.items,
            first_visible_line,
            hidden_rows_in_first_visible_line,
            rewrapped.items,
            cols,
        );
        try self.rebuildHistoryProjection(allocator);

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

    fn appendSourceRowToLogicalLines(
        self: *const GridModel,
        allocator: std.mem.Allocator,
        logical_lines: *std.ArrayListUnmanaged(LogicalLine),
        current_line: *LogicalLine,
        row_index: u16,
        cols: u16,
        cursor_found: *bool,
        cursor_line_index: *usize,
        cursor_offset: *usize,
    ) !void {
        const wrapped = self.rowWrapped(row_index);
        const is_cursor_row = row_index == self.cursor_row;
        const content_len = self.sourceRowContentLen(row_index, cols);

        if (is_cursor_row) {
            const row_cursor_offset = self.cursorOffsetInRow(cols);
            current_line.cursor_offset = current_line.cells.items.len + row_cursor_offset;
        }

        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            try current_line.cells.append(allocator, self.cellInfoAt(row_index, col));
        }

        if (!wrapped) {
            if (current_line.cursor_offset) |offset| {
                cursor_found.* = true;
                cursor_line_index.* = logical_lines.items.len;
                cursor_offset.* = offset;
            }
            try logical_lines.append(allocator, current_line.*);
            current_line.* = .{};
        }
    }

    fn sourceRowContentLen(self: *const GridModel, row_index: u16, cols: u16) u16 {
        var last_non_zero: u16 = 0;
        var has_content = false;
        var col: u16 = 0;
        while (col < cols) : (col += 1) {
            const value = self.cellInfoAt(row_index, col);
            if (value.codepoint != 0) {
                has_content = true;
                last_non_zero = col + 1;
            }
        }

        var len: u16 = if (has_content) last_non_zero else 0;
        if (self.rowWrapped(row_index) and cols > 0) {
            len = @max(len, cols);
        }
        return len;
    }

    fn cursorOffsetInRow(self: *const GridModel, cols: u16) usize {
        if (cols == 0) return 0;
        if (self.wrap_pending and self.cursor_col == cols - 1) {
            return cols;
        }
        return self.cursor_col;
    }

    fn cloneHistoryLine(allocator: std.mem.Allocator, cells: []const Cell) !LogicalLine {
        var line = LogicalLine{};
        try line.cells.appendSlice(allocator, cells);
        return line;
    }

    fn cloneHistoryAuthorityLine(allocator: std.mem.Allocator, cells: []const Cell) !HistoryLine {
        var line = HistoryLine{};
        try line.cells.appendSlice(allocator, cells);
        return line;
    }

    fn cloneOpenHistoryAsLogicalLine(self: *const GridModel, allocator: std.mem.Allocator) !LogicalLine {
        var line = LogicalLine{};
        if (self.open_history_line) |open_line| {
            try line.cells.appendSlice(allocator, open_line.cells.items);
        }
        return line;
    }

    fn firstLineForRow(line_row_starts: []const usize, line_row_counts: []const usize, row_index: usize) ?usize {
        for (line_row_starts, line_row_counts, 0..) |row_start, row_count, line_idx| {
            if (row_count == 0) continue;
            if (row_index < row_start + row_count) return line_idx;
        }
        return null;
    }

    fn replaceHistoryAuthority(
        self: *GridModel,
        allocator: std.mem.Allocator,
        logical_lines: []const LogicalLine,
        line_row_starts: []const usize,
        line_row_counts: []const usize,
        first_visible_line: usize,
        hidden_rows_in_first_visible_line: usize,
        rewrapped: []const RewrappedRow,
        cols: u16,
    ) !void {
        self.clearHistoryAuthority(allocator);

        const kept_complete_start = if (first_visible_line > @as(usize, self.history_capacity))
            first_visible_line - @as(usize, self.history_capacity)
        else
            0;

        var line_idx = kept_complete_start;
        while (line_idx < first_visible_line) : (line_idx += 1) {
            try self.history_lines.append(allocator, try cloneHistoryAuthorityLine(allocator, logical_lines[line_idx].cells.items));
        }

        if (first_visible_line < logical_lines.len and hidden_rows_in_first_visible_line > 0) {
            const line = logical_lines[first_visible_line];
            const row_start = line_row_starts[first_visible_line];
            const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[first_visible_line]);
            var prefix_len: usize = 0;
            var hidden_row: usize = 0;
            while (hidden_row < row_limit) : (hidden_row += 1) {
                prefix_len += rewrapped[row_start + hidden_row].len;
            }
            prefix_len = @min(prefix_len, line.cells.items.len);
            self.open_history_line = try cloneHistoryAuthorityLine(allocator, line.cells.items[0..prefix_len]);
        }

        if (self.history_lines.items.len > self.history_capacity) {
            const drop = self.history_lines.items.len - self.history_capacity;
            var i: usize = 0;
            while (i < drop) : (i += 1) {
                self.history_lines.items[i].deinit(allocator);
            }
            std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
            self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
        }

        _ = cols;
    }

    fn clearHistoryAuthority(self: *GridModel, allocator: std.mem.Allocator) void {
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.clearRetainingCapacity();
        self.history_lines_start = 0;
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
        self.open_history_reuse_slot = null;
    }

    fn rebuildHistoryProjection(self: *GridModel, allocator: std.mem.Allocator) !void {
        self.history_count = 0;
        self.history_write_idx = 0;

        if (self.history_capacity == 0 or self.cols == 0) return;

        var line_idx: usize = 0;
        while (line_idx < self.history_lines.items.len) : (line_idx += 1) {
            const line = self.historyLineAt(line_idx);
            try self.appendHistoryProjectionRows(allocator, line.cells.items, false);
        }
        if (self.open_history_line) |line| {
            try self.appendHistoryProjectionRows(allocator, line.cells.items, true);
        }
    }

    fn appendHistoryProjectionRows(
        self: *GridModel,
        allocator: std.mem.Allocator,
        cells: []const Cell,
        continues_to_visible: bool,
    ) !void {
        const cols = @as(usize, self.cols);
        if (cols == 0) return;
        const row_count: usize = @max(1, std.math.divCeil(usize, cells.len, cols) catch unreachable);

        var row_idx: usize = 0;
        while (row_idx < row_count) : (row_idx += 1) {
            const start = row_idx * cols;
            const end = @min(cells.len, start + cols);
            try self.appendProjectedHistoryRow(allocator, cells[start..end], row_idx + 1 < row_count or continues_to_visible);
        }
    }

    fn storeHistoryRow(self: *GridModel, row: u16) void {
        if (self.history_capacity == 0) return;
        const allocator = self.allocator orelse return;
        const wrapped = self.rowWrapped(row);
        const len = self.visibleRowContentLen(row);
        if (self.open_history_line == null) {
            const reusable = self.takeReusableHistoryLine();
            self.open_history_line = reusable.line;
            self.open_history_reuse_slot = reusable.slot;
        }
        const open_line = &self.open_history_line.?;
        var col: u16 = 0;
        while (col < len) : (col += 1) {
            open_line.cells.append(allocator, self.cellInfoAt(row, col)) catch return;
        }
        self.appendProjectedHistoryRow(allocator, open_line.cells.items[open_line.cells.items.len - len .. open_line.cells.items.len], wrapped) catch return;
        if (!wrapped) {
            const finalized = self.open_history_line.?;
            self.open_history_line = null;
            if (self.open_history_reuse_slot) |slot| {
                self.open_history_reuse_slot = null;
                self.history_lines.items[slot] = finalized;
            } else {
                self.history_lines.append(allocator, finalized) catch {
                    var failed = finalized;
                    failed.deinit(allocator);
                    return;
                };
                self.pruneHistoryLines(allocator);
            }
        }
    }

    fn visibleRowContentLen(self: *const GridModel, row: u16) u16 {
        var col = self.cols;
        while (col > 0) {
            const idx = col - 1;
            if (self.cellInfoAt(row, idx).codepoint != 0) return col;
            col -= 1;
        }
        if (self.rowWrapped(row) and self.cols > 0) return self.cols;
        return 0;
    }

    fn pruneHistoryLines(self: *GridModel, allocator: std.mem.Allocator) void {
        if (self.history_lines.items.len <= self.history_capacity) return;
        const drop = self.history_lines.items.len - self.history_capacity;
        var i: usize = 0;
        while (i < drop) : (i += 1) {
            self.dropOldestProjectedHistoryRows(self.projectedRowCountForCells(self.history_lines.items[i].cells.items));
            self.history_lines.items[i].deinit(allocator);
        }
        std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
        self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
    }

    fn takeReusableHistoryLine(self: *GridModel) struct { line: HistoryLine, slot: ?usize } {
        if (self.history_capacity == 0 or self.history_lines.items.len < self.history_capacity) return .{ .line = .{}, .slot = null };
        const slot = self.history_lines_start;
        var reusable = self.history_lines.items[slot];
        self.history_lines.items[slot] = .{};
        self.dropOldestProjectedHistoryRows(self.projectedRowCountForCells(reusable.cells.items));
        self.history_lines_start = (self.history_lines_start + 1) % self.history_lines.items.len;
        reusable.cells.clearRetainingCapacity();
        return .{ .line = reusable, .slot = slot };
    }

    fn historyLineAt(self: *const GridModel, logical_index: usize) HistoryLine {
        const slot = (self.history_lines_start + logical_index) % self.history_lines.items.len;
        return self.history_lines.items[slot];
    }

    fn appendProjectedHistoryRow(self: *GridModel, allocator: std.mem.Allocator, cells: []const Cell, wrapped: bool) !void {
        if (self.cols == 0) return;
        try self.ensureProjectedHistoryCapacity(allocator, self.history_count + 1);

        const wraps = self.history_wraps orelse return;
        const history = self.history orelse return;
        const slot = self.projectedHistoryAppendSlot();
        const cols = @as(usize, self.cols);
        const base = slot * cols;

        @memset(history[base .. base + cols], default_cell);
        @memcpy(history[base .. base + cells.len], cells);
        wraps[slot] = wrapped;
        self.history_count += 1;
    }

    fn ensureProjectedHistoryCapacity(self: *GridModel, allocator: std.mem.Allocator, min_rows: usize) !void {
        if (self.cols == 0) return;

        const current_rows = if (self.history_wraps) |wraps| wraps.len else 0;
        if (current_rows >= min_rows) return;

        const new_rows = @max(min_rows, @max(current_rows * 2, @as(usize, 8)));
        const cols = @as(usize, self.cols);
        const new_history = try allocator.alloc(Cell, new_rows * cols);
        errdefer allocator.free(new_history);
        @memset(new_history, default_cell);

        const new_wraps = try allocator.alloc(bool, new_rows);
        errdefer allocator.free(new_wraps);
        @memset(new_wraps, false);

        const old_count = self.history_count;
        var logical_row: usize = 0;
        while (logical_row < old_count) : (logical_row += 1) {
            const old_slot = self.historySlotForLogicalRow(logical_row) orelse break;
            const src_start = old_slot * cols;
            const dst_start = logical_row * cols;
            if (self.history) |history| {
                @memcpy(new_history[dst_start .. dst_start + cols], history[src_start .. src_start + cols]);
            }
            if (self.history_wraps) |wraps| new_wraps[logical_row] = wraps[old_slot];
        }

        if (self.history) |history| allocator.free(history);
        if (self.history_wraps) |wraps| allocator.free(wraps);
        self.history = new_history;
        self.history_wraps = new_wraps;
        self.history_write_idx = 0;
    }

    fn projectedHistoryAppendSlot(self: *const GridModel) usize {
        const capacity = self.projectedHistoryCapacity();
        if (capacity == 0) return 0;
        return (self.history_write_idx + self.history_count) % capacity;
    }

    fn projectedHistoryCapacity(self: *const GridModel) usize {
        return if (self.history_wraps) |wraps| wraps.len else 0;
    }

    fn projectedRowCountForCells(self: *const GridModel, cells: []const Cell) usize {
        const cols = @as(usize, self.cols);
        if (cols == 0) return 0;
        return @max(1, std.math.divCeil(usize, cells.len, cols) catch unreachable);
    }

    fn dropOldestProjectedHistoryRows(self: *GridModel, row_count: usize) void {
        if (row_count == 0 or self.history_count == 0) return;

        const drop = @min(row_count, self.history_count);
        const capacity = self.projectedHistoryCapacity();
        if (drop == self.history_count or capacity == 0) {
            self.history_count = 0;
            self.history_write_idx = 0;
            return;
        }

        self.history_write_idx = (self.history_write_idx + drop) % capacity;
        self.history_count -= drop;
    }

    /// Reset visible grid state to defaults.
    pub fn reset(self: *GridModel) void {
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
        if (self.tab_stops) |stops| setDefaultTabStops(stops);
    }

    pub fn peekDirtyRows(self: *const GridModel) ?DirtyRows {
        return self.dirty_rows;
    }

    pub fn clearDirtyRows(self: *GridModel) void {
        self.dirty_rows = null;
        if (self.dirty_cols_start) |buf| @memset(buf, self.cols);
        if (self.dirty_cols_end) |buf| @memset(buf, 0);
    }

    pub fn markAllDirty(self: *GridModel) void {
        self.markAllRowsDirty();
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const GridModel, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    pub fn cellInfoAt(self: *const GridModel, row: u16, col: u16) Cell {
        const c = self.cells orelse return default_cell;
        if (row >= self.rows or col >= self.cols) return default_cell;
        const start = self.rowStart(row);
        return c[start + @as(usize, col)];
    }

    pub fn tabStopAt(self: *const GridModel, col: u16) bool {
        return self.isTabStop(col);
    }

    pub fn insertMode(self: *const GridModel) bool {
        return self.insert_mode;
    }

    pub fn rectBoundsForReport(self: *const GridModel, area: SemanticEvent.RectArea) ?struct { top: u16, left: u16, bottom: u16, right: u16 } {
        const bounds = self.rectBounds(area) orelse return null;
        return .{ .top = bounds.top, .left = bounds.left, .bottom = bounds.bottom, .right = bounds.right };
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const GridModel, history_idx: usize, col: u16) u21 {
        return @intCast(self.historyCellAt(history_idx, col).codepoint);
    }

    pub fn historyCellAt(self: *const GridModel, history_idx: usize, col: u16) Cell {
        const h = self.history orelse return default_cell;
        if (history_idx >= self.history_count or col >= self.cols) return default_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return default_cell;
        return h[slot * @as(usize, self.cols) + @as(usize, col)];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const GridModel) usize {
        return self.history_count;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const GridModel) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const GridModel, endpoint_row: i32) bool {
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

    /// Apply one semantic event to grid state.
    pub fn apply(self: *GridModel, event: SemanticEvent) void {
        switch (event) {
            .cursor_up => |n| {
                self.wrap_pending = false;
                self.cursor_row = self.cursor_row -| n;
            },
            .cursor_down => |n| {
                self.wrap_pending = false;
                self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
            },
            .cursor_forward => |n| {
                self.wrap_pending = false;
                self.cursor_col = @min(self.cursor_col +| n, self.rightBoundary());
            },
            .cursor_back => |n| {
                self.wrap_pending = false;
                self.cursor_col = @max(self.cursor_col -| n, self.leftBoundary());
            },
            .cursor_next_line => |n| {
                self.wrap_pending = false;
                self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
                self.cursor_col = self.lineHomeCol();
            },
            .cursor_prev_line => |n| {
                self.wrap_pending = false;
                self.cursor_row = self.cursor_row -| n;
                self.cursor_col = self.lineHomeCol();
            },
            .cursor_horizontal_absolute => |col| {
                self.wrap_pending = false;
                self.cursor_col = @min(self.resolveAbsoluteCol(col), self.rightBoundary());
            },
            .cursor_vertical_absolute => |row| {
                self.wrap_pending = false;
                self.cursor_row = @min(row, self.rows -| 1);
            },
            .cursor_position => |pos| {
                self.wrap_pending = false;
                self.cursor_row = @min(self.resolveAbsoluteRow(pos.row), self.rows -| 1);
                self.cursor_col = @min(self.resolveAbsoluteCol(pos.col), self.rightBoundary());
            },
            .write_text => |s| {
                for (s) |byte| {
                    self.writeCell(@intCast(byte));
                }
            },
            .write_codepoint => |cp| self.writeCell(cp),
            .repeat_preceding => |count| {
                if (self.last_graphic_codepoint) |cp| {
                    var remaining = count;
                    while (remaining > 0) : (remaining -= 1) self.writeCell(cp);
                }
            },
            .line_feed => {
                self.wrap_pending = false;
                self.setRowWrapped(self.cursor_row, false);
                self.lineFeed();
            },
            .next_line => {
                self.wrap_pending = false;
                self.setRowWrapped(self.cursor_row, false);
                self.cursor_col = 0;
                self.lineFeed();
            },
            .reverse_index => {
                self.wrap_pending = false;
                self.reverseIndex();
            },
            .carriage_return => {
                self.wrap_pending = false;
                self.cursor_col = 0;
            },
            .backspace => {
                self.wrap_pending = false;
                self.cursor_col = self.cursor_col -| 1;
            },
            .horizontal_tab => {
                self.wrap_pending = false;
                self.horizontalTabForward(1);
            },
            .horizontal_tab_forward => |count| {
                self.wrap_pending = false;
                self.horizontalTabForward(count);
            },
            .horizontal_tab_back => |count| {
                self.wrap_pending = false;
                self.horizontalTabBack(count);
            },
            .horizontal_tab_set => self.setTabStop(),
            .tab_clear_current => self.clearCurrentTabStop(),
            .tab_clear_all => self.clearAllTabStops(),
            .cursor_visible => |visible| self.cursor_visible = visible,
            .cursor_style => |style| self.cursor_style = .{
                .shape = switch (style.shape) {
                    .block => .block,
                    .underline => .underline,
                    .bar => .bar,
                },
                .blink = style.blink,
            },
            .auto_wrap => |enabled| {
                self.auto_wrap = enabled;
                if (!enabled) self.wrap_pending = false;
            },
            .origin_mode => |enabled| {
                self.origin_mode = enabled;
                self.wrap_pending = false;
                self.cursor_row = if (enabled) self.scroll_top else 0;
                self.cursor_col = self.lineHomeCol();
            },
            .insert_mode => |enabled| self.insert_mode = enabled,
            .application_cursor_keys,
            .application_keypad,
            .ansi_mode_set,
            .ansi_mode_reset,
            .ansi_mode_query,
            .modify_other_keys_set,
            .modify_other_keys_query,
            .modify_other_keys_disable,
            .focus_reporting,
            .bracketed_paste,
            .mouse_tracking_off,
            .mouse_tracking_x10,
            .mouse_tracking_normal,
            .mouse_tracking_button_event,
            .mouse_tracking_any_event,
            .mouse_protocol_utf8,
            .mouse_protocol_sgr,
            .mouse_protocol_urxvt,
            .kitty_keyboard_set,
            .kitty_keyboard_query,
            .kitty_keyboard_push,
            .kitty_keyboard_pop,
            .kitty_shell_mark,
            .kitty_notification,
            .kitty_pointer_shape,
            .kitty_color_stack,
            .terminal_color_control,
            .hyperlink_set,
            .hyperlink_clear,
            .clipboard_set,
            .dec_mode_query,
            .dec_mode_save,
            .dec_mode_restore,
            .device_status_report,
            .cursor_position_report,
            .dec_cursor_position_report,
            .primary_device_attributes,
            .secondary_device_attributes,
            .tertiary_device_attributes,
            .xtchecksum,
            .rect_checksum_request,
            .presentation_state_report,
            .displayed_extent_report,
            .terminal_parameters_report,
            .xtreportcolors,
            .locator_reporting,
            .locator_filter,
            .locator_events,
            .locator_request,
            .kitty_graphics,
            => {},
            .save_cursor => self.saveCursor(),
            .restore_cursor => self.restoreCursor(),
            .sgr => |sgr| self.applySgr(sgr.params[0..sgr.param_count], sgr.separators[0..sgr.param_count]),
            .enter_alt_screen, .exit_alt_screen => {},
            .insert_lines => |count| {
                self.wrap_pending = false;
                self.insertLines(count);
            },
            .delete_lines => |count| {
                self.wrap_pending = false;
                self.deleteLines(count);
            },
            .insert_chars => |count| {
                self.wrap_pending = false;
                self.insertChars(count);
            },
            .delete_chars => |count| {
                self.wrap_pending = false;
                self.deleteChars(count);
            },
            .scroll_up_lines => |count| {
                self.wrap_pending = false;
                self.scrollUpRegion(self.scroll_top, self.scrollBottom(), count);
            },
            .scroll_down_lines => |count| {
                self.wrap_pending = false;
                self.scrollDownRegion(self.scroll_top, self.scrollBottom(), count);
            },
            .set_scroll_region => |region| {
                self.wrap_pending = false;
                self.setScrollRegion(region.top, region.bottom);
            },
            .reset_screen => self.reset(),
            .erase_display => |mode| {
                self.wrap_pending = false;
                self.eraseDisplay(mode);
            },
            .erase_line => |mode| {
                self.wrap_pending = false;
                self.eraseLine(mode);
            },
            .selective_erase_display => |mode| {
                self.wrap_pending = false;
                self.selectiveEraseDisplay(mode);
            },
            .selective_erase_line => |mode| {
                self.wrap_pending = false;
                self.selectiveEraseLine(mode);
            },
            .erase_chars => |count| {
                self.wrap_pending = false;
                self.eraseChars(count);
            },
            .character_protection => |enabled| self.current_attrs.protected = enabled,
            .attr_change_extent_rect => |enabled| self.attr_change_extent_rect = enabled,
            .left_right_margin_mode => |enabled| self.setLeftRightMarginMode(enabled),
            .set_left_right_margins => |margins| self.setLeftRightMargins(margins.left, margins.right),
            .rect_erase => |area| {
                self.wrap_pending = false;
                self.eraseRect(area, false);
            },
            .rect_selective_erase => |area| {
                self.wrap_pending = false;
                self.eraseRect(area, true);
            },
            .rect_fill => |req| {
                self.wrap_pending = false;
                self.fillRect(req.area, req.ch);
            },
            .rect_copy => |req| {
                self.wrap_pending = false;
                self.copyRect(req);
            },
            .rect_attrs_change => |req| {
                self.wrap_pending = false;
                self.changeRectAttrs(req.area, req.attrs.params[0..req.attrs.param_count], req.reverse);
            },
            .insert_columns => |count| {
                self.wrap_pending = false;
                self.insertColumns(count);
            },
            .delete_columns => |count| {
                self.wrap_pending = false;
                self.deleteColumns(count);
            },
        }
    }

    const RectBounds = struct {
        top: u16,
        left: u16,
        bottom: u16,
        right: u16,
    };

    fn eraseDisplay(self: *GridModel, mode: u2) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => {
                self.markDirtyRows(self.cursor_row, self.rows -| 1);
                self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
                var r = self.cursor_row + 1;
                while (r < self.rows) : (r += 1) {
                    self.clearRowRange(r, 0, self.cols);
                    self.setRowWrapped(r, false);
                }
            },
            1 => {
                self.markDirtyRows(0, self.cursor_row);
                var r: u16 = 0;
                while (r < self.cursor_row) : (r += 1) {
                    self.clearRowRange(r, 0, self.cols);
                    self.setRowWrapped(r, false);
                }
                self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
            },
            2 => {
                self.markAllRowsDirty();
                const cell = self.eraseCell();
                @memset(c, cell);
                if (self.row_wraps) |buf| @memset(buf, false);
            },
            3 => self.clearScrollback(),
        }
    }

    pub fn setCurrentLinkId(self: *GridModel, link_id: u32) void {
        self.current_attrs.link_id = link_id;
    }

    fn resolveAbsoluteRow(self: *const GridModel, row: u16) u16 {
        if (!self.origin_mode) return row;
        const bottom = self.scrollBottom();
        const region_len = bottom - self.scroll_top;
        return self.scroll_top + @min(row, region_len);
    }

    fn resolveAbsoluteCol(self: *const GridModel, col: u16) u16 {
        if (!(self.origin_mode and self.left_right_margin_mode)) return col;
        const region_len = self.right_margin - self.left_margin;
        return self.left_margin + @min(col, region_len);
    }

    fn saveCursor(self: *GridModel) void {
        self.saved_cursor = .{
            .row = self.cursor_row,
            .col = self.cursor_col,
            .wrap_pending = self.wrap_pending,
        };
    }

    fn restoreCursor(self: *GridModel) void {
        if (self.saved_cursor) |saved| {
            self.cursor_row = @min(saved.row, self.rows -| 1);
            self.cursor_col = @min(saved.col, self.rightBoundary());
            self.wrap_pending = saved.wrap_pending;
        }
    }

    fn lineHomeCol(self: *const GridModel) u16 {
        return if (self.origin_mode and self.left_right_margin_mode) self.left_margin else 0;
    }

    fn leftBoundary(self: *const GridModel) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    fn rightBoundary(self: *const GridModel) u16 {
        return if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    }

    fn clearScrollback(self: *GridModel) void {
        const allocator = self.allocator orelse return;
        self.clearHistoryAuthority(allocator);
        self.history_count = 0;
        self.history_write_idx = 0;
        self.markAllRowsDirty();
    }

    fn eraseLine(self: *GridModel, mode: u2) void {
        _ = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => {
                self.markDirtyCols(self.cursor_row, self.cursor_col, self.cols -| 1);
                self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
            },
            1 => {
                self.markDirtyCols(self.cursor_row, 0, self.cursor_col);
                self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
            },
            2 => {
                self.markDirtyRow(self.cursor_row);
                self.clearRowRange(self.cursor_row, 0, self.cols);
                self.setRowWrapped(self.cursor_row, false);
            },
            3 => {},
        }
    }

    fn eraseChars(self: *GridModel, count: u16) void {
        if (self.rows == 0 or self.cols == 0) return;
        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor_col + 1);
        self.markDirtyCols(self.cursor_row, self.cursor_col, self.cursor_col + amount - 1);
        self.clearRowRange(self.cursor_row, self.cursor_col, self.cursor_col + amount);
    }

    fn changeRectAttrs(self: *GridModel, area: SemanticEvent.RectArea, attrs: []const u16, reverse: bool) void {
        const c = self.cells orelse return;
        if (attrs.len == 0) return;
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRows(bounds.top, bounds.bottom);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const row_start = self.rowStart(row);
            const start_col = if (self.attr_change_extent_rect or row == bounds.top) bounds.left else 0;
            const end_col = if (self.attr_change_extent_rect or row == bounds.bottom) bounds.right else self.cols -| 1;
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                const idx = row_start + col;
                applyRectAttrOps(&c[idx].attrs, attrs, reverse);
            }
        }
    }

    fn selectiveEraseDisplay(self: *GridModel, mode: u2) void {
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => {
                self.selectiveClearRowRange(self.cursor_row, self.cursor_col, self.cols);
                var row = self.cursor_row + 1;
                while (row < self.rows) : (row += 1) {
                    self.selectiveClearRowRange(row, 0, self.cols);
                    self.setRowWrapped(row, false);
                }
            },
            1 => {
                var row: u16 = 0;
                while (row < self.cursor_row) : (row += 1) {
                    self.selectiveClearRowRange(row, 0, self.cols);
                    self.setRowWrapped(row, false);
                }
                self.selectiveClearRowRange(self.cursor_row, 0, self.cursor_col + 1);
            },
            2 => {
                var row: u16 = 0;
                while (row < self.rows) : (row += 1) {
                    self.selectiveClearRowRange(row, 0, self.cols);
                    self.setRowWrapped(row, false);
                }
            },
            3 => {},
        }
    }

    fn selectiveEraseLine(self: *GridModel, mode: u2) void {
        if (self.rows == 0 or self.cols == 0) return;
        switch (mode) {
            0 => self.selectiveClearRowRange(self.cursor_row, self.cursor_col, self.cols),
            1 => self.selectiveClearRowRange(self.cursor_row, 0, self.cursor_col + 1),
            2 => {
                self.selectiveClearRowRange(self.cursor_row, 0, self.cols);
                self.setRowWrapped(self.cursor_row, false);
            },
            3 => {},
        }
    }

    fn eraseRect(self: *GridModel, area: SemanticEvent.RectArea, selective: bool) void {
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRows(bounds.top, bounds.bottom);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            if (selective) {
                self.selectiveClearRowRange(row, bounds.left, bounds.right + 1);
            } else {
                self.clearRowRange(row, bounds.left, bounds.right + 1);
            }
            if (bounds.left == 0 and bounds.right + 1 == self.cols) self.setRowWrapped(row, false);
        }
    }

    fn fillRect(self: *GridModel, area: SemanticEvent.RectArea, ch: u21) void {
        const c = self.cells orelse return;
        const bounds = self.rectBounds(area) orelse return;
        self.markDirtyRows(bounds.top, bounds.bottom);
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const start = self.rowStart(row);
            var col = bounds.left;
            while (col <= bounds.right) : (col += 1) {
                c[start + col] = .{ .codepoint = ch, .attrs = self.current_attrs };
            }
        }
    }

    fn copyRect(self: *GridModel, req: SemanticEvent.RectCopy) void {
        const c = self.cells orelse return;
        _ = c;
        if (req.source_page != 1 or req.dest_page != 1) return;
        const src = self.rectBounds(req.area) orelse return;
        const row_base: u16 = if (self.origin_mode) self.scroll_top else 0;
        const row_limit: u16 = if (self.origin_mode) self.scrollBottom() else self.rows -| 1;
        const dest_top = row_base + @min(req.dest_top, row_limit -| row_base);
        const dest_left = @min(req.dest_left, self.cols -| 1);
        const height: u16 = src.bottom - src.top + 1;
        const width: u16 = src.right - src.left + 1;
        if (dest_top >= self.rows or dest_left >= self.cols) return;
        const copy_height = @min(height, self.rows - dest_top);
        const copy_width = @min(width, self.cols - dest_left);
        if (copy_height == 0 or copy_width == 0) return;

        const allocator = self.allocator orelse return;
        const temp = allocator.alloc(Cell, @as(usize, copy_height) * @as(usize, copy_width)) catch return;
        defer allocator.free(temp);

        var row: u16 = 0;
        while (row < copy_height) : (row += 1) {
            var col: u16 = 0;
            while (col < copy_width) : (col += 1) {
                temp[@as(usize, row) * @as(usize, copy_width) + col] = self.cellInfoAt(src.top + row, src.left + col);
            }
        }

        self.markDirtyRows(dest_top, dest_top + copy_height - 1);
        row = 0;
        while (row < copy_height) : (row += 1) {
            const dst_start = self.rowStart(dest_top + row);
            var col: u16 = 0;
            while (col < copy_width) : (col += 1) {
                self.cells.?[dst_start + dest_left + col] = temp[@as(usize, row) * @as(usize, copy_width) + col];
            }
        }
    }

    fn insertColumns(self: *GridModel, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor_col >= self.cols or self.scroll_top > bottom) return;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) self.insertColumnsInRow(row, count);
    }

    fn deleteColumns(self: *GridModel, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor_col >= self.cols or self.scroll_top > bottom) return;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) self.deleteColumnsInRow(row, count);
    }

    fn insertColumnsInRow(self: *GridModel, row: u16, count: u16) void {
        const c = self.cells orelse return;
        const amount = @min(@max(count, 1), self.cols - self.cursor_col);
        const start = self.rowStart(row);
        const cells = c[start .. start + @as(usize, self.cols)];
        const dst_col = @as(usize, self.cursor_col) + @as(usize, amount);
        const move_len = @as(usize, self.cols) - dst_col;
        self.markDirtyCols(row, self.cursor_col, self.cols -| 1);
        if (move_len > 0) std.mem.copyBackwards(Cell, cells[dst_col .. dst_col + move_len], cells[@as(usize, self.cursor_col) .. @as(usize, self.cursor_col) + move_len]);
        @memset(cells[@as(usize, self.cursor_col) .. @as(usize, self.cursor_col) + @as(usize, amount)], self.eraseCell());
        self.setRowWrapped(row, false);
    }

    fn deleteColumnsInRow(self: *GridModel, row: u16, count: u16) void {
        const c = self.cells orelse return;
        const amount = @min(@max(count, 1), self.cols - self.cursor_col);
        const start = self.rowStart(row);
        const cells = c[start .. start + @as(usize, self.cols)];
        const src_col = @min(@as(usize, self.cursor_col) + @as(usize, amount), @as(usize, self.cols));
        const move_len = @as(usize, self.cols) - src_col;
        self.markDirtyCols(row, self.cursor_col, self.cols -| 1);
        if (move_len > 0) std.mem.copyForwards(Cell, cells[@as(usize, self.cursor_col) .. @as(usize, self.cursor_col) + move_len], cells[src_col .. src_col + move_len]);
        @memset(cells[@as(usize, self.cols) - @as(usize, amount) .. @as(usize, self.cols)], self.eraseCell());
        self.setRowWrapped(row, false);
    }

    fn insertChars(self: *GridModel, count: u16) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        if (self.cursor_col >= self.cols) return;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor_col + 1);
        const start = self.rowStart(self.cursor_row);
        const row = c[start .. start + @as(usize, self.cols)];
        const dst_col: usize = @as(usize, self.cursor_col) + @as(usize, amount);
        const src_col: usize = self.cursor_col;
        const move_len = @as(usize, self.rightBoundary() + 1) - dst_col;

        self.markDirtyCols(self.cursor_row, self.cursor_col, self.rightBoundary());
        if (move_len > 0) {
            std.mem.copyBackwards(Cell, row[dst_col .. dst_col + move_len], row[src_col .. src_col + move_len]);
        }
        @memset(row[src_col .. src_col + @as(usize, amount)], self.eraseCell());
        self.setRowWrapped(self.cursor_row, false);
    }

    fn deleteChars(self: *GridModel, count: u16) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        if (self.cursor_col >= self.cols) return;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor_col + 1);
        const start = self.rowStart(self.cursor_row);
        const row = c[start .. start + @as(usize, self.cols)];
        const dst_col: usize = self.cursor_col;
        const src_col: usize = @min(@as(usize, self.cursor_col) + @as(usize, amount), @as(usize, self.rightBoundary() + 1));
        const move_len = @as(usize, self.rightBoundary() + 1) - src_col;

        self.markDirtyCols(self.cursor_row, self.cursor_col, self.rightBoundary());
        if (move_len > 0) {
            std.mem.copyForwards(Cell, row[dst_col .. dst_col + move_len], row[src_col .. src_col + move_len]);
        }
        @memset(row[@as(usize, self.rightBoundary() + 1) - @as(usize, amount) .. @as(usize, self.rightBoundary() + 1)], self.eraseCell());
        self.setRowWrapped(self.cursor_row, false);
    }

    fn writeCell(self: *GridModel, cp: u21) void {
        if (self.cols == 0 or self.rows == 0) return;
        const right = self.rightBoundary();
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (self.cursor_col == right) {
                self.setRowWrapped(self.cursor_row, true);
                self.lineFeed();
                self.cursor_col = if (self.left_right_margin_mode) self.left_margin else 0;
            }
        }
        if (self.insert_mode) self.insertChars(1);
        if (self.cells) |c| {
            const start = self.rowStart(self.cursor_row);
            self.markDirtyCols(self.cursor_row, self.cursor_col, self.cursor_col);
            c[start + @as(usize, self.cursor_col)] = .{
                .codepoint = cp,
                .attrs = self.current_attrs,
            };
        }
        self.last_graphic_codepoint = cp;
        if (self.cursor_col < right) {
            self.cursor_col += 1;
        } else if (self.auto_wrap) {
            self.wrap_pending = true;
        }
    }

    fn applySgr(self: *GridModel, params: []const i32, separators: []const u8) void {
        if (params.len == 0) {
            self.current_attrs = default_cell_attrs;
            return;
        }

        var i: usize = 0;
        while (i < params.len) : (i += 1) {
            const p = params[i];
            switch (p) {
                0 => self.current_attrs = default_cell_attrs,
                1 => self.current_attrs.bold = true,
                4 => {
                    if (i + 1 < params.len and separators[i + 1] == ':') {
                        switch (params[i + 1]) {
                            0 => self.current_attrs.underline = false,
                            1 => {
                                self.current_attrs.underline = true;
                                self.current_attrs.underline_style = .straight;
                            },
                            2 => {
                                self.current_attrs.underline = true;
                                self.current_attrs.underline_style = .double;
                            },
                            3 => {
                                self.current_attrs.underline = true;
                                self.current_attrs.underline_style = .curly;
                            },
                            4 => {
                                self.current_attrs.underline = true;
                                self.current_attrs.underline_style = .dotted;
                            },
                            5 => {
                                self.current_attrs.underline = true;
                                self.current_attrs.underline_style = .dashed;
                            },
                            else => {},
                        }
                        i += 1;
                    } else {
                        self.current_attrs.underline = true;
                        self.current_attrs.underline_style = .straight;
                    }
                },
                5, 6 => self.current_attrs.blink = true,
                7 => self.current_attrs.reverse = true,
                22 => self.current_attrs.bold = false,
                24 => {
                    self.current_attrs.underline = false;
                    self.current_attrs.underline_style = .straight;
                },
                25 => {
                    self.current_attrs.blink = false;
                    self.current_attrs.blink_fast = false;
                },
                27 => self.current_attrs.reverse = false,
                30...37 => self.current_attrs.fg = ansi16Color(@intCast(p - 30)),
                39 => self.current_attrs.fg = default_cell_attrs.fg,
                40...47 => self.current_attrs.bg = ansi16Color(@intCast(p - 40)),
                49 => self.current_attrs.bg = default_cell_attrs.bg,
                90...97 => self.current_attrs.fg = ansi16Color(@intCast((p - 90) + 8)),
                100...107 => self.current_attrs.bg = ansi16Color(@intCast((p - 100) + 8)),
                38, 48 => {
                    const is_fg = p == 38;
                    if (i + 1 >= params.len) break;
                    const mode = params[i + 1];
                    if (mode == 5) {
                        if (i + 2 >= params.len) break;
                        const color = indexed256Color(clampByte(params[i + 2]));
                        if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
                        i += 2;
                    } else if (mode == 2) {
                        if (i + 4 >= params.len) break;
                        const color = Color{
                            .r = clampByte(params[i + 2]),
                            .g = clampByte(params[i + 3]),
                            .b = clampByte(params[i + 4]),
                        };
                        if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
                        i += 4;
                    }
                },
                58 => {
                    if (i + 1 >= params.len) break;
                    const mode = params[i + 1];
                    if (mode == 5) {
                        if (i + 2 >= params.len) break;
                        self.current_attrs.underline_color = indexed256Color(clampByte(params[i + 2]));
                        i += 2;
                    } else if (mode == 2) {
                        if (i + 4 >= params.len) break;
                        self.current_attrs.underline_color = .{
                            .r = clampByte(params[i + 2]),
                            .g = clampByte(params[i + 3]),
                            .b = clampByte(params[i + 4]),
                        };
                        i += 4;
                    }
                },
                59 => self.current_attrs.underline_color = default_underline_color,
                else => {},
            }
        }
    }

    fn horizontalTabForward(self: *GridModel, count: u16) void {
        if (self.cols == 0) return;
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor_col >= self.cols - 1) break;
            var col = self.cursor_col + 1;
            while (col < self.cols and !self.isTabStop(col)) : (col += 1) {}
            self.cursor_col = if (col < self.cols) col else self.cols - 1;
        }
    }

    fn horizontalTabBack(self: *GridModel, count: u16) void {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor_col == 0) break;
            var col = self.cursor_col - 1;
            while (col > 0 and !self.isTabStop(col)) : (col -= 1) {}
            self.cursor_col = if (self.isTabStop(col)) col else 0;
        }
    }

    fn isTabStop(self: *const GridModel, col: u16) bool {
        if (self.tab_stops) |stops| {
            if (col < stops.len) return stops[col];
        }
        return col != 0 and col % 8 == 0;
    }

    fn setTabStop(self: *GridModel) void {
        if (self.tab_stops) |stops| {
            if (self.cursor_col < stops.len) stops[self.cursor_col] = true;
        }
    }

    fn clearCurrentTabStop(self: *GridModel) void {
        if (self.tab_stops) |stops| {
            if (self.cursor_col < stops.len) stops[self.cursor_col] = false;
        }
    }

    fn clearAllTabStops(self: *GridModel) void {
        if (self.tab_stops) |stops| @memset(stops, false);
    }

    fn lineFeed(self: *GridModel) void {
        if (self.rows == 0) return;
        const bottom = self.scrollBottom();
        if (self.cursor_row < bottom) {
            self.cursor_row += 1;
            return;
        }
        if (self.cursor_row == bottom) {
            self.scrollUpRegion(self.scroll_top, bottom, 1);
            return;
        }
        if (self.cursor_row < self.rows - 1) self.cursor_row += 1;
    }

    fn reverseIndex(self: *GridModel) void {
        if (self.rows == 0) return;
        if (self.cursor_row == self.scroll_top) {
            self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1);
        } else {
            self.cursor_row = self.cursor_row -| 1;
        }
    }

    fn scrollUp(self: *GridModel) void {
        const c = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        self.markAllRowsDirty();
        const row_len = @as(usize, self.cols);
        self.storeHistoryRow(0);
        self.row_origin = @intCast((@as(usize, self.row_origin) + 1) % @as(usize, self.rows));
        const bottom_start = self.rowStart(self.rows - 1);
        @memset(c[bottom_start .. bottom_start + row_len], default_cell);
        self.setRowWrapped(self.rows - 1, false);
    }

    fn scrollBottom(self: *const GridModel) u16 {
        return if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    }

    fn setScrollRegion(self: *GridModel, top: u16, bottom: ?u16) void {
        if (self.rows == 0) {
            self.scroll_top = 0;
            self.scroll_bottom = 0;
            self.cursor_row = 0;
            self.cursor_col = 0;
            return;
        }

        const new_top = @min(top, self.rows - 1);
        const new_bottom = if (bottom) |value| @min(value, self.rows - 1) else self.rows - 1;
        if (new_top >= new_bottom) return;

        self.scroll_top = new_top;
        self.scroll_bottom = new_bottom;
        self.cursor_row = if (self.origin_mode) self.scroll_top else 0;
        self.cursor_col = self.lineHomeCol();
    }

    fn setLeftRightMarginMode(self: *GridModel, enabled: bool) void {
        self.left_right_margin_mode = enabled;
        if (!enabled) {
            self.left_margin = 0;
            self.right_margin = self.cols -| 1;
        }
    }

    fn setLeftRightMargins(self: *GridModel, left: u16, right: ?u16) void {
        if (!self.left_right_margin_mode or self.cols < 2) return;
        const new_left = @min(left, self.cols - 2);
        const new_right = if (right) |value| @min(value, self.cols - 1) else self.cols - 1;
        if (new_left >= new_right) return;
        self.left_margin = new_left;
        self.right_margin = new_right;
        self.wrap_pending = false;
        self.cursor_row = if (self.origin_mode) self.scroll_top else 0;
        self.cursor_col = self.lineHomeCol();
    }

    fn insertLines(self: *GridModel, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor_row < self.scroll_top or self.cursor_row > bottom) return;
        self.scrollDownRegion(self.cursor_row, bottom, count);
    }

    fn deleteLines(self: *GridModel, count: u16) void {
        const bottom = self.scrollBottom();
        if (self.cursor_row < self.scroll_top or self.cursor_row > bottom) return;
        self.scrollUpRegion(self.cursor_row, bottom, count);
    }

    fn scrollUpRegion(self: *GridModel, top: u16, bottom: u16, count: u16) void {
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return;

        if (top == 0 and bounded_bottom == self.rows - 1) {
            var remaining = amount;
            while (remaining > 0) : (remaining -= 1) self.scrollUp();
            return;
        }

        self.markDirtyRows(top, bounded_bottom);
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;

        var dst = top;
        while (dst + amount <= bounded_bottom) : (dst += 1) {
            self.copyRowRange(dst, dst + amount, left, right + 1);
        }

        var clear_row = bounded_bottom - amount + 1;
        while (clear_row <= bounded_bottom) : (clear_row += 1) {
            self.clearRowRange(clear_row, left, right + 1);
            self.setRowWrapped(clear_row, false);
        }
    }

    fn scrollDownRegion(self: *GridModel, top: u16, bottom: u16, count: u16) void {
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return;

        self.markDirtyRows(top, bounded_bottom);
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;

        var dst = bounded_bottom;
        while (dst >= top + amount) {
            self.copyRowRange(dst, dst - amount, left, right + 1);
            if (dst == top + amount) break;
            dst -= 1;
        }

        var clear_row = top;
        while (clear_row < top + amount) : (clear_row += 1) {
            self.clearRowRange(clear_row, left, right + 1);
            self.setRowWrapped(clear_row, false);
        }
    }

    fn rowStart(self: *const GridModel, logical_row: u16) usize {
        const physical_row = (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
        return physical_row * @as(usize, self.cols);
    }

    fn rowWrapIndex(self: *const GridModel, logical_row: u16) ?usize {
        _ = self.row_wraps orelse return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (@as(usize, self.row_origin) + @as(usize, logical_row)) % @as(usize, self.rows);
    }

    fn rowWrapped(self: *const GridModel, logical_row: u16) bool {
        const wraps = self.row_wraps orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return wraps[idx];
    }

    fn setRowWrapped(self: *GridModel, logical_row: u16, wrapped: bool) void {
        const wraps = self.row_wraps orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        wraps[idx] = wrapped;
    }

    fn historySlotForLogicalRow(self: *const GridModel, logical_row: usize) ?usize {
        const capacity = self.projectedHistoryCapacity();
        if (logical_row >= self.history_count or capacity == 0) return null;
        return (self.history_write_idx + logical_row) % capacity;
    }

    fn historySlotForRecency(self: *const GridModel, history_idx: usize) ?usize {
        if (history_idx >= self.history_count) return null;
        return self.historySlotForLogicalRow(self.history_count - 1 - history_idx);
    }

    fn historyRowWrapped(self: *const GridModel, history_idx: usize) bool {
        const wraps = self.history_wraps orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return wraps[slot];
    }

    fn clearRowRange(self: *GridModel, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const start = self.rowStart(row);
        const cell = self.eraseCell();
        @memset(c[start + @as(usize, start_col) .. start + @as(usize, end_col_exclusive)], cell);
    }

    fn selectiveClearRowRange(self: *GridModel, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const start = self.rowStart(row);
        const cell = self.eraseCell();
        var col = start_col;
        while (col < end_col_exclusive) : (col += 1) {
            const idx = start + @as(usize, col);
            if (c[idx].attrs.protected) continue;
            c[idx] = cell;
        }
    }

    fn rectBounds(self: *const GridModel, area: SemanticEvent.RectArea) ?RectBounds {
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

    fn eraseCell(self: *const GridModel) Cell {
        return .{ .codepoint = 0, .attrs = self.current_attrs };
    }

    fn clearFullRow(self: *GridModel, row: u16) void {
        if (self.cols == 0) return;
        self.clearRowRange(row, 0, self.cols);
        self.setRowWrapped(row, false);
    }

    fn copyRow(self: *GridModel, dst_row: u16, src_row: u16) void {
        const c = self.cells orelse return;
        const row_len = @as(usize, self.cols);
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(Cell, c[dst_start .. dst_start + row_len], c[src_start .. src_start + row_len]);
        self.setRowWrapped(dst_row, self.rowWrapped(src_row));
    }

    fn copyRowRange(self: *GridModel, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(Cell, c[dst_start + start_col .. dst_start + end_col_exclusive], c[src_start + start_col .. src_start + end_col_exclusive]);
        self.setRowWrapped(dst_row, false);
    }

    fn markDirtyRow(self: *GridModel, row: u16) void {
        if (self.rows == 0 or row >= self.rows) return;
        self.markDirtyCols(row, 0, self.cols -| 1);
    }

    fn markDirtyCols(self: *GridModel, row: u16, start_col: u16, end_col: u16) void {
        if (self.rows == 0 or self.cols == 0 or row >= self.rows) return;
        const start = @min(start_col, self.cols -| 1);
        const end = @min(end_col, self.cols -| 1);
        const lo = @min(start, end);
        const hi = @max(start, end);
        if (self.dirty_rows) |*d| {
            d.start_row = @min(d.start_row, row);
            d.end_row = @max(d.end_row, row);
            d.dirty_cols_start = self.dirty_cols_start orelse &.{};
            d.dirty_cols_end = self.dirty_cols_end orelse &.{};
        } else {
            self.dirty_rows = .{
                .start_row = row,
                .end_row = row,
                .dirty_cols_start = self.dirty_cols_start orelse &.{},
                .dirty_cols_end = self.dirty_cols_end orelse &.{},
            };
        }
        if (self.dirty_cols_start) |cols_start| {
            cols_start[row] = @min(cols_start[row], lo);
        }
        if (self.dirty_cols_end) |cols_end| {
            cols_end[row] = @max(cols_end[row], hi);
        }
    }

    fn markDirtyRows(self: *GridModel, start_row: u16, end_row: u16) void {
        if (self.rows == 0) return;
        const start = @min(start_row, self.rows -| 1);
        const end = @min(end_row, self.rows -| 1);
        if (self.dirty_cols_start) |cols_start| {
            var row = start;
            while (row <= end) : (row += 1) cols_start[row] = 0;
        }
        if (self.dirty_cols_end) |cols_end| {
            var row = start;
            while (row <= end) : (row += 1) cols_end[row] = self.cols -| 1;
        }
        if (self.dirty_rows) |*d| {
            d.start_row = @min(d.start_row, start);
            d.end_row = @max(d.end_row, end);
            d.dirty_cols_start = self.dirty_cols_start orelse &.{};
            d.dirty_cols_end = self.dirty_cols_end orelse &.{};
        } else {
            self.dirty_rows = .{
                .start_row = start,
                .end_row = end,
                .dirty_cols_start = self.dirty_cols_start orelse &.{},
                .dirty_cols_end = self.dirty_cols_end orelse &.{},
            };
        }
    }

    fn markAllRowsDirty(self: *GridModel) void {
        if (self.rows == 0) return;
        if (self.dirty_cols_start) |buf| @memset(buf, 0);
        if (self.dirty_cols_end) |buf| @memset(buf, self.cols -| 1);
        self.dirty_rows = dirtyRowsForFull(self.rows, self.dirty_cols_start, self.dirty_cols_end);
    }

    fn clampByte(v: i32) u8 {
        return @intCast(std.math.clamp(v, 0, 255));
    }

    fn ansi16Color(idx: u8) Color {
        return switch (idx) {
            0 => .{ .r = 0, .g = 0, .b = 0 },
            1 => .{ .r = 170, .g = 0, .b = 0 },
            2 => .{ .r = 0, .g = 170, .b = 0 },
            3 => .{ .r = 170, .g = 85, .b = 0 },
            4 => .{ .r = 0, .g = 0, .b = 170 },
            5 => .{ .r = 170, .g = 0, .b = 170 },
            6 => .{ .r = 0, .g = 170, .b = 170 },
            7 => .{ .r = 170, .g = 170, .b = 170 },
            8 => .{ .r = 85, .g = 85, .b = 85 },
            9 => .{ .r = 255, .g = 85, .b = 85 },
            10 => .{ .r = 85, .g = 255, .b = 85 },
            11 => .{ .r = 255, .g = 255, .b = 85 },
            12 => .{ .r = 85, .g = 85, .b = 255 },
            13 => .{ .r = 255, .g = 85, .b = 255 },
            14 => .{ .r = 85, .g = 255, .b = 255 },
            15 => .{ .r = 255, .g = 255, .b = 255 },
            else => default_cell_attrs.fg,
        };
    }

    fn indexed256Color(idx: u8) Color {
        if (idx < 16) return ansi16Color(idx);
        if (idx < 232) {
            const i: u32 = idx - 16;
            return .{
                .r = @intCast((i / 36) * 51),
                .g = @intCast(((i / 6) % 6) * 51),
                .b = @intCast((i % 6) * 51),
            };
        }
        const gray: u8 = @intCast((@as(u32, idx) - 232) * 10 + 8);
        return .{ .r = gray, .g = gray, .b = gray };
    }

    fn applyRectAttrOps(target: *CellAttrs, attrs: []const u16, reverse: bool) void {
        for (attrs) |attr| {
            switch (attr) {
                0 => if (!reverse) {
                    target.bold = false;
                    target.underline = false;
                    target.underline_style = .straight;
                    target.blink = false;
                    target.blink_fast = false;
                    target.reverse = false;
                },
                1 => {
                    if (reverse) target.bold = !target.bold else target.bold = true;
                },
                4 => {
                    if (reverse) {
                        target.underline = !target.underline;
                        if (target.underline) target.underline_style = .straight;
                    } else {
                        target.underline = true;
                        target.underline_style = .straight;
                    }
                },
                5 => {
                    if (reverse) target.blink = !target.blink else target.blink = true;
                },
                7 => {
                    if (reverse) target.reverse = !target.reverse else target.reverse = true;
                },
                22 => {
                    if (!reverse) target.bold = false;
                },
                24 => {
                    if (!reverse) {
                    target.underline = false;
                    target.underline_style = .straight;
                    }
                },
                25 => {
                    if (!reverse) {
                        target.blink = false;
                        target.blink_fast = false;
                    }
                },
                27 => {
                    if (!reverse) target.reverse = false;
                },
                else => {},
            }
        }
    }
};
