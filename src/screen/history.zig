const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;

fn count32(items: anytype) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

pub const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,
    cursor_offset: ?u32 = null,
};

pub const HistoryLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,

    pub fn deinit(self: *HistoryLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

pub const RewrappedRow = struct {
    start: u32,
    len: u16,
    wrapped: bool,
};

pub fn collectLogicalLines(self: anytype, allocator: std.mem.Allocator, rows: u16) !std.ArrayListUnmanaged(LogicalLine) {
    var logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty;
    errdefer {
        for (logical_lines.items) |*line| line.cells.deinit(allocator);
        logical_lines.deinit(allocator);
    }

    var current_line = try cloneOpenHistoryAsLogicalLine(self, allocator);
    defer current_line.cells.deinit(allocator);

    var history_line_idx: u32 = 0;
    while (history_line_idx < self.history_lines.items.len) : (history_line_idx += 1) {
        const line = self.historyLineAt(history_line_idx);
        var copied = try cloneHistoryLine(allocator, line.cells.items);
        copied.cursor_offset = null;
        try logical_lines.append(allocator, copied);
    }

    var cursor_found = false;
    var cursor_line_index: u32 = 0;
    var cursor_offset: u32 = 0;
    var row: u16 = 0;
    while (row < rows) : (row += 1) {
        try appendSourceRowToLogicalLines(
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
        try logical_lines.append(allocator, current_line);
        current_line = .{};
    }

    while (logical_lines.items.len > 1) {
        const last_idx = logical_lines.items.len - 1;
        const last = &logical_lines.items[last_idx];
        if (last.cells.items.len > 0) break;
        last.cells.deinit(allocator);
        logical_lines.items.len = last_idx;
    }

    return logical_lines;
}

pub fn appendSourceRowToLogicalLines(
    self: anytype,
    allocator: std.mem.Allocator,
    logical_lines: *std.ArrayListUnmanaged(LogicalLine),
    current_line: *LogicalLine,
    row_index: u16,
    cols: u16,
    cursor_found: *bool,
    cursor_line_index: *u32,
    cursor_offset: *u32,
) !void {
    const wrapped = self.rowWrapped(row_index);
    const is_cursor_row = row_index == self.cursor.row;
    const content_len = sourceRowContentLen(self, row_index, cols);

    if (is_cursor_row) {
        const row_cursor_offset = cursorOffsetInRow(self, cols);
        current_line.cursor_offset = @as(u32, @intCast(current_line.cells.items.len)) + row_cursor_offset;
    }

    var col: u16 = 0;
    while (col < content_len) : (col += 1) {
        try current_line.cells.append(allocator, self.cellInfoAt(row_index, col));
    }

    if (!wrapped) {
        if (current_line.cursor_offset) |offset| {
            cursor_found.* = true;
            cursor_line_index.* = @intCast(logical_lines.items.len);
            cursor_offset.* = offset;
        }
        try logical_lines.append(allocator, current_line.*);
        current_line.* = .{};
    }
}

pub fn cloneHistoryLine(allocator: std.mem.Allocator, cells: []const Cell) !LogicalLine {
    var line = LogicalLine{};
    try line.cells.appendSlice(allocator, cells);
    return line;
}

pub fn cloneOpenHistoryAsLogicalLine(self: anytype, allocator: std.mem.Allocator) !LogicalLine {
    var line = LogicalLine{};
    if (self.open_history_line) |open_line| {
        try line.cells.appendSlice(allocator, open_line.cells.items);
    }
    return line;
}

pub fn firstLineForRowBounded(line_row_starts: []const u32, line_row_counts: []const u16, row_index: u32) ?u32 {
    std.debug.assert(line_row_starts.len == line_row_counts.len);
    for (line_row_starts, line_row_counts, 0..) |row_start, row_count, line_idx| {
        if (row_count == 0) continue;
        if (row_index < row_start + row_count) return @intCast(line_idx);
    }
    return null;
}

pub fn replaceAuthority(
    self: anytype,
    allocator: std.mem.Allocator,
    logical_lines: []const LogicalLine,
    line_row_starts: []const u32,
    line_row_counts: []const u16,
    first_visible_line: u32,
    hidden_rows_in_first_visible_line: u16,
    rewrapped: []const RewrappedRow,
    cols: u16,
) !void {
    self.clearHistoryAuthority(allocator);

    std.debug.assert(line_row_starts.len == logical_lines.len);
    std.debug.assert(line_row_counts.len == logical_lines.len);
    std.debug.assert(first_visible_line <= count32(logical_lines));
    if (first_visible_line < count32(logical_lines)) {
        std.debug.assert(hidden_rows_in_first_visible_line < line_row_counts[@intCast(first_visible_line)]);
    } else {
        std.debug.assert(hidden_rows_in_first_visible_line == 0);
    }

    const kept_complete_start = if (first_visible_line > self.history_capacity)
        first_visible_line - self.history_capacity
    else
        0;

    var line_idx: u32 = kept_complete_start;
    while (line_idx < first_visible_line) : (line_idx += 1) {
        var line = try cloneAuthorityLine(allocator, logical_lines[@intCast(line_idx)].cells.items);
        self.history_lines.append(allocator, line) catch |err| {
            line.deinit(allocator);
            return err;
        };
    }
    std.debug.assert(self.history_lines.items.len == first_visible_line - kept_complete_start);

    if (first_visible_line < count32(logical_lines) and hidden_rows_in_first_visible_line > 0) {
        const line = logical_lines[@intCast(first_visible_line)];
        const row_start = line_row_starts[@intCast(first_visible_line)];
        const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[@intCast(first_visible_line)]);
        std.debug.assert(row_start + row_limit <= count32(rewrapped));
        var prefix_len: u32 = 0;
        var hidden_row: u16 = 0;
        while (hidden_row < row_limit) : (hidden_row += 1) {
            const row = rewrapped[@intCast(row_start + hidden_row)];
            std.debug.assert(row.len <= cols);
            prefix_len += rewrapped[@intCast(row_start + hidden_row)].len;
        }
        prefix_len = @min(prefix_len, count32(line.cells.items));
        std.debug.assert(prefix_len <= count32(line.cells.items));
        self.open_history_line = try cloneAuthorityLine(allocator, line.cells.items[0..@intCast(prefix_len)]);
    }

    if (self.history_lines.items.len > self.history_capacity) {
        const drop = self.history_lines.items.len - self.history_capacity;
        std.debug.assert(drop <= self.history_lines.items.len);
        var i: u32 = 0;
        while (i < drop) : (i += 1) {
            self.history_lines.items[@intCast(i)].deinit(allocator);
        }
        std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
        self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
    }
}

fn sourceRowContentLen(self: anytype, row_index: u16, cols: u16) u16 {
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

fn cursorOffsetInRow(self: anytype, cols: u16) u32 {
    if (cols == 0) return 0;
    if (self.wrap_pending and self.cursor.col == cols - 1) {
        return cols;
    }
    return self.cursor.col;
}

fn cloneAuthorityLine(allocator: std.mem.Allocator, cells: []const Cell) !HistoryLine {
    var line = HistoryLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    return line;
}

fn colCount(cols: u16) u32 {
    return cols;
}

fn rowCountForCells(cell_count: u32, cols: u16) u32 {
    return @max(@as(u32, 1), std.math.divCeil(u32, cell_count, cols) catch unreachable);
}
