//! Grid resize and reflow behavior.

const std = @import("std");
const dirty = @import("dirty.zig");
const cell = @import("cell.zig");
const history_mod = @import("history.zig");
const tabs = @import("tabs.zig");

const Cell = cell.Cell;
const LogicalLine = history_mod.LogicalLine;
const RewrappedRow = history_mod.RewrappedRow;
const default_cell = cell.default_cell;

/// Resize visible grid storage while preserving logical scrollback lines.
pub fn resizeWithReflow(self: anytype, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
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
