const std = @import("std");
const dirty = @import("dirty.zig");
const cell = @import("cell.zig");
const history_mod = @import("history.zig");
const tabs = @import("tabs.zig");

const Cell = cell.Cell;
const LogicalLine = history_mod.LogicalLine;
const RewrappedRow = history_mod.RewrappedRow;
const default_cell = cell.default_cell;

const LogicalLinesState = struct {
    logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty,
    cursor_found: bool = false,
    cursor_line_index: u32 = 0,
    cursor_offset: u32 = 0,

    fn deinit(self: *LogicalLinesState, allocator: std.mem.Allocator) void {
        for (self.logical_lines.items) |*line| line.cells.deinit(allocator);
        self.logical_lines.deinit(allocator);
    }
};

const ReflowState = struct {
    flat_rows: std.ArrayListUnmanaged(Cell) = .empty,
    rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty,
    line_row_starts: std.ArrayListUnmanaged(u32) = .empty,
    line_row_counts: std.ArrayListUnmanaged(u16) = .empty,
    global_cursor_row: u32 = 0,
    global_cursor_col: u16 = 0,
    next_wrap_pending: bool = false,

    fn deinit(self: *ReflowState, allocator: std.mem.Allocator) void {
        self.flat_rows.deinit(allocator);
        self.rewrapped.deinit(allocator);
        self.line_row_starts.deinit(allocator);
        self.line_row_counts.deinit(allocator);
    }
};

const ViewportState = struct {
    total_rows: u32,
    visible_rows_kept: u16,
    visible_start: u32,
    first_visible_line: u32,
    hidden_rows_in_first_visible_line: u16,
};

const ResizeBuffers = struct {
    cells: ?[]Cell,
    row_wraps: ?[]bool,
    dirty_state: dirty.DirtyState,
    tab_stops: ?[]bool,
};

/// Prepare complete resized screen state while preserving the source.
pub fn prepareResize(self: anytype, allocator: std.mem.Allocator, rows: u16, cols: u16) error{OutOfMemory}!@TypeOf(self.*) {
    var lines = try collectLogicalLines(self, allocator, self.rows);
    defer lines.deinit(allocator);

    var reflow = try reflowLogicalLines(allocator, lines, cols);
    defer reflow.deinit(allocator);

    const viewport = projectViewport(@intCast(lines.logical_lines.items.len), reflow, rows);
    var buffers = try allocResizeBuffers(allocator, rows, cols, self.tab_stops);
    errdefer freeResizeBuffers(allocator, buffers);

    copyVisibleRows(buffers.cells, buffers.row_wraps, reflow, viewport, cols);
    var replacement = replacementBase(self, allocator);
    installResizeState(&replacement, rows, cols, buffers);
    buffers = emptyResizeBuffers();
    errdefer replacement.deinit(allocator);
    try rebuildResizeAuthority(&replacement, allocator, lines, reflow, viewport, cols);
    restoreCursor(&replacement, rows, cols, reflow, viewport);
    return replacement;
}

fn emptyResizeBuffers() ResizeBuffers {
    return .{
        .cells = null,
        .row_wraps = null,
        .dirty_state = .{},
        .tab_stops = null,
    };
}

fn replacementBase(self: anytype, allocator: std.mem.Allocator) @TypeOf(self.*) {
    var replacement = self.*;
    replacement.allocator = allocator;
    replacement.cells = null;
    replacement.row_wraps = null;
    replacement.dirty_state = .{};
    replacement.tab_stops = null;
    replacement.history = null;
    replacement.history_wraps = null;
    replacement.history_count = 0;
    replacement.history_write_idx = 0;
    replacement.history_lines = .empty;
    replacement.history_lines_start = 0;
    replacement.open_history_line = null;
    replacement.open_history_reuse_slot = null;
    return replacement;
}

fn collectLogicalLines(self: anytype, allocator: std.mem.Allocator, old_rows: u16) !LogicalLinesState {
    var result = LogicalLinesState{};
    errdefer result.deinit(allocator);

    var current_line = try history_mod.cloneOpenHistoryAsLogicalLine(self, allocator);
    defer current_line.cells.deinit(allocator);

    var history_line_idx: u32 = 0;
    while (history_line_idx < self.history_lines.items.len) : (history_line_idx += 1) {
        const line = self.historyLineAt(history_line_idx);
        var copied = try history_mod.cloneHistoryLine(allocator, line.cells.items);
        copied.cursor_offset = null;
        try result.logical_lines.append(allocator, copied);
    }

    var row: u16 = 0;
    while (row < old_rows) : (row += 1) {
        try history_mod.appendSourceRowToLogicalLines(
            self,
            allocator,
            &result.logical_lines,
            &current_line,
            row,
            self.cols,
            &result.cursor_found,
            &result.cursor_line_index,
            &result.cursor_offset,
        );
    }

    try finishLogicalLines(allocator, &result, &current_line);
    return result;
}

fn finishLogicalLines(allocator: std.mem.Allocator, result: *LogicalLinesState, current_line: *LogicalLine) !void {
    if (current_line.cells.items.len > 0 or current_line.cursor_offset != null or result.logical_lines.items.len == 0) {
        if (current_line.cursor_offset) |offset| {
            result.cursor_found = true;
            result.cursor_line_index = @intCast(result.logical_lines.items.len);
            result.cursor_offset = offset;
        }
        try result.logical_lines.append(allocator, current_line.*);
        current_line.* = .{};
    }

    while (result.logical_lines.items.len > 1) {
        const last_idx = result.logical_lines.items.len - 1;
        const last = &result.logical_lines.items[last_idx];
        if (last.cells.items.len > 0) break;
        if (result.cursor_found and result.cursor_line_index == last_idx) break;
        last.cells.deinit(allocator);
        result.logical_lines.items.len = last_idx;
    }
}

fn reflowLogicalLines(allocator: std.mem.Allocator, lines: LogicalLinesState, cols: u16) !ReflowState {
    var result = ReflowState{};
    errdefer result.deinit(allocator);

    var row_cursor_base: u32 = 0;
    for (lines.logical_lines.items, 0..) |line, line_idx| {
        const rewrapped_before = result.rewrapped.items.len;
        const has_cursor = lines.cursor_found and lines.cursor_line_index == line_idx;
        const line_cursor_offset = boundedCursorOffset(line, has_cursor, lines.cursor_offset);
        const row_count = lineRowCount(@intCast(line.cells.items.len), cols);
        try result.line_row_starts.append(allocator, @intCast(result.rewrapped.items.len));
        try result.line_row_counts.append(allocator, row_count);
        updateCursor(&result, row_cursor_base, line_cursor_offset, cols, has_cursor);
        try appendRewrappedRows(allocator, &result, line.cells.items, row_count, cols);
        row_cursor_base += row_count;

        std.debug.assert(result.line_row_starts.items.len == result.line_row_counts.items.len);
        std.debug.assert(result.rewrapped.items.len == rewrapped_before + row_count);
        std.debug.assert(result.rewrapped.items.len == row_cursor_base);
        std.debug.assert(result.flat_rows.items.len == result.rewrapped.items.len * colCount(cols));
    }

    std.debug.assert(result.line_row_starts.items.len == lines.logical_lines.items.len);
    std.debug.assert(result.line_row_counts.items.len == lines.logical_lines.items.len);
    return result;
}

fn appendRewrappedRows(allocator: std.mem.Allocator, result: *ReflowState, cells: []const Cell, row_count: u16, cols: u16) !void {
    if (cols == 0) return;
    if (row_count == 0) unreachable;

    const flat_rows_before = count32(result.flat_rows.items);
    const cell_len = count32(cells);

    var row_idx: u16 = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        const start = rowStart(row_idx, cols);
        const end = @min(cell_len, start + colCount(cols));
        std.debug.assert(start <= end);
        std.debug.assert(end <= cell_len);
        try result.rewrapped.append(allocator, .{
            .start = count32(result.flat_rows.items),
            .len = @intCast(end - start),
            .wrapped = row_idx + 1 < row_count,
        });
        try appendRowCells(allocator, &result.flat_rows, cells, start, cols);
    }

    std.debug.assert(count32(result.flat_rows.items) == flat_rows_before + @as(u32, row_count) * colCount(cols));
}

fn appendRowCells(allocator: std.mem.Allocator, flat_rows: *std.ArrayListUnmanaged(Cell), cells: []const Cell, start: u32, cols: u16) !void {
    const cell_len = count32(cells);
    var col_idx: u16 = 0;
    while (col_idx < cols) : (col_idx += 1) {
        const src_idx = start + @as(u32, col_idx);
        if (src_idx < cell_len) {
            try flat_rows.append(allocator, cells[@intCast(src_idx)]);
        } else {
            try flat_rows.append(allocator, default_cell);
        }
    }
}

fn updateCursor(result: *ReflowState, row_cursor_base: u32, line_cursor_offset: u32, cols: u16, has_cursor: bool) void {
    if (!has_cursor) return;
    if (cols == 0) {
        result.global_cursor_row = 0;
        result.global_cursor_col = 0;
        result.next_wrap_pending = false;
        return;
    }

    if (lineCursorWraps(line_cursor_offset, cols)) {
        result.global_cursor_row = row_cursor_base + @as(u32, line_cursor_offset / cols) - 1;
        result.global_cursor_col = cols - 1;
        result.next_wrap_pending = true;
        return;
    }

    result.global_cursor_row = row_cursor_base + @as(u32, line_cursor_offset / cols);
    result.global_cursor_col = @intCast(line_cursor_offset % cols);
    result.next_wrap_pending = false;
}

fn projectViewport(logical_line_count: u32, reflow: ReflowState, rows: u16) ViewportState {
    const total_rows: u32 = @intCast(reflow.rewrapped.items.len);
    const visible_rows_kept: u16 = @intCast(@min(@as(u32, rows), total_rows));
    const visible_start = total_rows - visible_rows_kept;
    const first_visible_line = history_mod.firstLineForRowBounded(
        reflow.line_row_starts.items,
        reflow.line_row_counts.items,
        visible_start,
    ) orelse logical_line_count;
    const hidden_rows_in_first_visible_line: u16 = if (first_visible_line < logical_line_count)
        @intCast(visible_start - reflow.line_row_starts.items[@intCast(first_visible_line)])
    else
        0;

    std.debug.assert(visible_rows_kept <= rows);
    std.debug.assert(visible_rows_kept <= total_rows);
    std.debug.assert(visible_start <= total_rows);
    std.debug.assert(visible_start + visible_rows_kept == total_rows);
    std.debug.assert(first_visible_line <= logical_line_count);
    if (total_rows == 0) {
        std.debug.assert(first_visible_line == logical_line_count);
        std.debug.assert(hidden_rows_in_first_visible_line == 0);
    } else {
        std.debug.assert(first_visible_line < logical_line_count);
        std.debug.assert(reflow.line_row_starts.items[@intCast(first_visible_line)] <= visible_start);
        std.debug.assert(hidden_rows_in_first_visible_line < reflow.line_row_counts.items[@intCast(first_visible_line)]);
    }

    return .{
        .total_rows = total_rows,
        .visible_rows_kept = visible_rows_kept,
        .visible_start = visible_start,
        .first_visible_line = first_visible_line,
        .hidden_rows_in_first_visible_line = hidden_rows_in_first_visible_line,
    };
}

fn allocResizeBuffers(allocator: std.mem.Allocator, rows: u16, cols: u16, old_tab_stops: ?[]bool) !ResizeBuffers {
    const cell_count = cellCount(rows, cols);
    var cells: ?[]Cell = null;
    if (cell_count > 0) {
        const buf = try allocator.alloc(Cell, cell_count);
        @memset(buf, default_cell);
        cells = buf;
    }
    errdefer if (cells) |buf| allocator.free(buf);

    var row_wraps: ?[]bool = null;
    if (rows > 0) {
        const buf = try allocator.alloc(bool, rows);
        @memset(buf, false);
        row_wraps = buf;
    }
    errdefer if (row_wraps) |buf| allocator.free(buf);

    const dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
    errdefer if (dirty_cols_start) |buf| allocator.free(buf);
    const dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
    errdefer if (dirty_cols_end) |buf| allocator.free(buf);
    const tab_stops = try tabs.allocTabStops(allocator, cols);
    errdefer if (tab_stops) |buf| allocator.free(buf);
    tabs.copyTabStops(tab_stops, old_tab_stops);

    std.debug.assert((cells != null) == (cell_count > 0));
    std.debug.assert((row_wraps != null) == (rows > 0));
    std.debug.assert((dirty_cols_start != null) == (rows > 0));
    std.debug.assert((dirty_cols_end != null) == (rows > 0));
    std.debug.assert((tab_stops != null) == (cols > 0));
    if (cells) |buf| std.debug.assert(buf.len == cell_count);
    if (row_wraps) |buf| std.debug.assert(buf.len == rows);
    if (dirty_cols_start) |buf| std.debug.assert(buf.len == rows);
    if (dirty_cols_end) |buf| std.debug.assert(buf.len == rows);
    if (tab_stops) |buf| std.debug.assert(buf.len == cols);

    return .{
        .cells = cells,
        .row_wraps = row_wraps,
        .dirty_state = dirty.DirtyState.initFull(rows, dirty_cols_start, dirty_cols_end),
        .tab_stops = tab_stops,
    };
}

fn freeResizeBuffers(allocator: std.mem.Allocator, buffers: ResizeBuffers) void {
    if (buffers.cells) |buf| allocator.free(buf);
    if (buffers.row_wraps) |buf| allocator.free(buf);
    var dirty_state = buffers.dirty_state;
    dirty_state.deinit(allocator);
    if (buffers.tab_stops) |buf| allocator.free(buf);
}

fn copyVisibleRows(new_cells: ?[]Cell, new_row_wraps: ?[]bool, reflow: ReflowState, viewport: ViewportState, cols: u16) void {
    const dst = new_cells orelse return;
    const dst_wraps = new_row_wraps orelse return;

    std.debug.assert(viewport.visible_start + viewport.visible_rows_kept <= viewport.total_rows);
    std.debug.assert(viewport.total_rows == count32(reflow.rewrapped.items));
    std.debug.assert(count32(dst_wraps) >= viewport.visible_rows_kept);
    std.debug.assert(count32(dst) >= cellCount(viewport.visible_rows_kept, cols));
    std.debug.assert(count32(reflow.flat_rows.items) == count32(reflow.rewrapped.items) * colCount(cols));

    var src_row = viewport.visible_start;
    var view_row: u16 = 0;
    while (view_row < viewport.visible_rows_kept) : (view_row += 1) {
        const src = reflow.rewrapped.items[@intCast(src_row)];
        const dst_start = rowStart(view_row, cols);
        std.debug.assert(dst_start + colCount(cols) <= count32(dst));
        @memcpy(dst[@intCast(dst_start)..@intCast(dst_start + colCount(cols))], flatRowSlice(reflow.flat_rows.items, src, cols));
        dst_wraps[@intCast(view_row)] = src.wrapped;
        src_row += 1;
    }

    std.debug.assert(src_row == viewport.visible_start + viewport.visible_rows_kept);
}

fn installResizeState(self: anytype, rows: u16, cols: u16, buffers: ResizeBuffers) void {
    self.rows = rows;
    self.cols = cols;
    self.cells = buffers.cells;
    self.row_wraps = buffers.row_wraps;
    self.dirty_state = buffers.dirty_state;
    self.tab_stops = buffers.tab_stops;
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
    self.dirty_state.rows = dirty.rowsForFull(rows, self.dirty_state.cols_start, self.dirty_state.cols_end);

    std.debug.assert(self.rows == rows);
    std.debug.assert(self.cols == cols);
    std.debug.assert((self.cells != null) == (rows > 0 and cols > 0));
    std.debug.assert((self.row_wraps != null) == (rows > 0));
    std.debug.assert((self.dirty_state.cols_start != null) == (rows > 0));
    std.debug.assert((self.dirty_state.cols_end != null) == (rows > 0));
    std.debug.assert((self.tab_stops != null) == (cols > 0));
    if (self.cells) |buf| std.debug.assert(buf.len == cellCount(rows, cols));
    if (self.row_wraps) |buf| std.debug.assert(buf.len == rows);
    if (self.dirty_state.cols_start) |buf| std.debug.assert(buf.len == rows);
    if (self.dirty_state.cols_end) |buf| std.debug.assert(buf.len == rows);
    if (self.tab_stops) |buf| std.debug.assert(buf.len == cols);
    std.debug.assert(self.history == null);
    std.debug.assert(self.history_wraps == null);
    std.debug.assert(self.history_count == 0);
    std.debug.assert(self.history_write_idx == 0);
    std.debug.assert(self.row_origin == 0);
    std.debug.assert(self.view_padding_rows == 0);
    std.debug.assert(self.scroll_top == 0);
    std.debug.assert(self.scroll_bottom == rows -| 1);
    std.debug.assert(self.left_right_margin_mode == false);
    std.debug.assert(self.left_margin == 0);
    std.debug.assert(self.right_margin == cols -| 1);
}

fn rebuildResizeAuthority(self: anytype, allocator: std.mem.Allocator, lines: LogicalLinesState, reflow: ReflowState, viewport: ViewportState, cols: u16) !void {
    std.debug.assert(reflow.line_row_starts.items.len == lines.logical_lines.items.len);
    std.debug.assert(reflow.line_row_counts.items.len == lines.logical_lines.items.len);
    std.debug.assert(viewport.total_rows == count32(reflow.rewrapped.items));
    std.debug.assert(viewport.first_visible_line <= count32(lines.logical_lines.items));
    if (viewport.first_visible_line < count32(lines.logical_lines.items)) {
        std.debug.assert(viewport.hidden_rows_in_first_visible_line < reflow.line_row_counts.items[@intCast(viewport.first_visible_line)]);
    } else {
        std.debug.assert(viewport.hidden_rows_in_first_visible_line == 0);
    }

    try history_mod.replaceAuthority(
        self,
        allocator,
        lines.logical_lines.items,
        reflow.line_row_starts.items,
        reflow.line_row_counts.items,
        viewport.first_visible_line,
        viewport.hidden_rows_in_first_visible_line,
        reflow.rewrapped.items,
        cols,
    );
    try self.rebuildHistoryProjection(allocator);
}

fn restoreCursor(self: anytype, rows: u16, cols: u16, reflow: ReflowState, viewport: ViewportState) void {
    if (rows == 0 or cols == 0 or viewport.total_rows == 0) {
        self.cursor.setPositionStructural(0, 0);
        self.wrap_pending = false;
        std.debug.assert(self.cursor.row == 0);
        std.debug.assert(self.cursor.col == 0);
        std.debug.assert(self.wrap_pending == false);
        return;
    }

    const last_visible_row = viewport.visible_start + viewport.visible_rows_kept - 1;
    const clamped_cursor_row = std.math.clamp(reflow.global_cursor_row, viewport.visible_start, last_visible_row);
    self.cursor.setPositionStructural(@intCast(clamped_cursor_row - viewport.visible_start), @min(reflow.global_cursor_col, cols - 1));
    self.wrap_pending = reflow.next_wrap_pending and self.cursor.row < rows and self.cursor.col == cols - 1;

    std.debug.assert(viewport.visible_rows_kept > 0);
    std.debug.assert(clamped_cursor_row >= viewport.visible_start);
    std.debug.assert(clamped_cursor_row <= last_visible_row);
    std.debug.assert(self.cursor.row < rows);
    std.debug.assert(self.cursor.col < cols);
    if (self.wrap_pending) std.debug.assert(self.cursor.col == cols - 1);
}

fn boundedCursorOffset(line: LogicalLine, has_cursor: bool, cursor_offset: u32) u32 {
    if (!has_cursor) return 0;
    return @min(cursor_offset, @as(u32, @intCast(line.cells.items.len)));
}

fn lineCursorWraps(line_cursor_offset: u32, cols: u16) bool {
    return line_cursor_offset > 0 and line_cursor_offset % cols == 0;
}

fn lineRowCount(cell_count: u32, cols: u16) u16 {
    if (cols == 0) return 0;
    const rows = @max(@as(u32, 1), std.math.divCeil(u32, cell_count, cols) catch unreachable);
    return @intCast(rows);
}

fn flatRowSlice(flat_rows: []const Cell, row: RewrappedRow, cols: u16) []const Cell {
    const start = row.start;
    std.debug.assert(start + colCount(cols) <= count32(flat_rows));
    return flat_rows[@intCast(start)..@intCast(start + colCount(cols))];
}

fn cellCount(rows: u16, cols: u16) u32 {
    return @as(u32, rows) * @as(u32, cols);
}

fn rowStart(row: u16, cols: u16) u32 {
    return @as(u32, row) * @as(u32, cols);
}

fn colCount(cols: u16) u32 {
    return cols;
}

fn count32(items: anytype) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}
