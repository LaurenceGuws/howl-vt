const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;
const default_cell = cell.default_cell;

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
    const is_cursor_row = row_index == self.cursor_row;
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
    clearAuthority(self, allocator);

    std.debug.assert(line_row_starts.len == logical_lines.len);
    std.debug.assert(line_row_counts.len == logical_lines.len);
    std.debug.assert(first_visible_line <= logical_lines.len);
    if (first_visible_line < logical_lines.len) {
        std.debug.assert(hidden_rows_in_first_visible_line < line_row_counts[listIndex(first_visible_line)]);
    } else {
        std.debug.assert(hidden_rows_in_first_visible_line == 0);
    }

    const kept_complete_start = if (first_visible_line > self.history_capacity)
        first_visible_line - self.history_capacity
    else
        0;

    var line_idx: u32 = kept_complete_start;
    while (line_idx < first_visible_line) : (line_idx += 1) {
        try self.history_lines.append(allocator, try cloneAuthorityLine(allocator, logical_lines[listIndex(line_idx)].cells.items));
    }
    std.debug.assert(self.history_lines.items.len == first_visible_line - kept_complete_start);

    if (first_visible_line < logical_lines.len and hidden_rows_in_first_visible_line > 0) {
        const line = logical_lines[listIndex(first_visible_line)];
        const row_start = line_row_starts[listIndex(first_visible_line)];
        const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[listIndex(first_visible_line)]);
        std.debug.assert(row_start + row_limit <= rewrapped.len);
        var prefix_len: u32 = 0;
        var hidden_row: u16 = 0;
        while (hidden_row < row_limit) : (hidden_row += 1) {
            const row = rewrapped[listIndex(row_start + hidden_row)];
            std.debug.assert(row.len <= cols);
            prefix_len += rewrapped[listIndex(row_start + hidden_row)].len;
        }
        prefix_len = @min(prefix_len, @as(u32, @intCast(line.cells.items.len)));
        std.debug.assert(prefix_len <= line.cells.items.len);
        self.open_history_line = try cloneAuthorityLine(allocator, line.cells.items[0..listIndex(prefix_len)]);
    }

    if (self.history_lines.items.len > self.history_capacity) {
        const drop = self.history_lines.items.len - self.history_capacity;
        std.debug.assert(drop <= self.history_lines.items.len);
        var i: u32 = 0;
        while (i < drop) : (i += 1) {
            self.history_lines.items[listIndex(i)].deinit(allocator);
        }
        std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
        self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
    }
}

pub fn clearAuthority(self: anytype, allocator: std.mem.Allocator) void {
    for (self.history_lines.items) |*line| line.deinit(allocator);
    self.history_lines.clearRetainingCapacity();
    self.history_lines_start = 0;
    if (self.open_history_line) |*line| line.deinit(allocator);
    self.open_history_line = null;
    self.open_history_reuse_slot = null;
}

pub fn rebuildProjection(self: anytype, allocator: std.mem.Allocator) !void {
    self.history_count = 0;
    self.history_write_idx = 0;

    if (self.history_capacity == 0 or self.cols == 0) return;

    var line_idx: u32 = 0;
    while (line_idx < self.history_lines.items.len) : (line_idx += 1) {
        const line = historyLineAt(self, line_idx);
        try appendProjectionRows(self, allocator, line.cells.items, false);
    }
    if (self.open_history_line) |line| {
        try appendProjectionRows(self, allocator, line.cells.items, true);
    }
}

pub fn storeRow(self: anytype, row: u16) void {
    if (self.history_capacity == 0) return;
    const allocator = self.allocator orelse return;
    const wrapped = self.rowWrapped(row);
    const len = visibleRowContentLen(self, row);
    if (self.open_history_line == null) {
        const reusable = takeReusableLine(self);
        self.open_history_line = reusable.line;
        self.open_history_reuse_slot = reusable.slot;
    }
    const open_line = &self.open_history_line.?;
    var col: u16 = 0;
    while (col < len) : (col += 1) {
        open_line.cells.append(allocator, self.cellInfoAt(row, col)) catch return;
    }
    appendProjectedRow(self, allocator, open_line.cells.items[open_line.cells.items.len - len .. open_line.cells.items.len], wrapped) catch return;
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
            pruneLines(self, allocator);
        }
    }
}

pub fn historyLineAt(self: anytype, logical_index: usize) HistoryLine {
    const slot = (self.history_lines_start + logical_index) % self.history_lines.items.len;
    return self.history_lines.items[slot];
}

pub fn slotForLogicalRow(self: anytype, logical_row: usize) ?usize {
    const capacity = projectedCapacity(self);
    if (logical_row >= self.history_count or capacity == 0) return null;
    return (self.history_write_idx + logical_row) % capacity;
}

pub fn slotForRecency(self: anytype, history_idx: u32) ?usize {
    const bounded_idx = listIndex(history_idx);
    if (bounded_idx >= self.history_count) return null;
    return slotForLogicalRow(self, self.history_count - 1 - bounded_idx);
}

pub fn rowWrapped(self: anytype, history_idx: u32) bool {
    const wraps = self.history_wraps orelse return false;
    const slot = slotForRecency(self, history_idx) orelse return false;
    return wraps[slot];
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
    if (self.wrap_pending and self.cursor_col == cols - 1) {
        return cols;
    }
    return self.cursor_col;
}

fn cloneAuthorityLine(allocator: std.mem.Allocator, cells: []const Cell) !HistoryLine {
    var line = HistoryLine{};
    try line.cells.appendSlice(allocator, cells);
    return line;
}

fn appendProjectionRows(self: anytype, allocator: std.mem.Allocator, cells: []const Cell, continues_to_visible: bool) !void {
    const cols = colCount(self.cols);
    if (cols == 0) return;
    const row_count = rowCountForCells(cells.len, cols);
    std.debug.assert(row_count > 0);

    var row_idx: u32 = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        const start = listIndex(row_idx) * cols;
        const end = @min(cells.len, start + cols);
        std.debug.assert(start <= end);
        std.debug.assert(end <= cells.len);
        try appendProjectedRow(self, allocator, cells[start..end], row_idx + 1 < row_count or continues_to_visible);
    }
}

fn visibleRowContentLen(self: anytype, row: u16) u16 {
    var col = self.cols;
    while (col > 0) {
        const idx = col - 1;
        if (self.cellInfoAt(row, idx).codepoint != 0) return col;
        col -= 1;
    }
    if (self.rowWrapped(row) and self.cols > 0) return self.cols;
    return 0;
}

fn pruneLines(self: anytype, allocator: std.mem.Allocator) void {
    if (self.history_lines.items.len <= self.history_capacity) return;
    const drop = self.history_lines.items.len - self.history_capacity;
    std.debug.assert(drop <= self.history_lines.items.len);
    var i: u32 = 0;
    while (i < drop) : (i += 1) {
        dropOldestProjectedRows(self, projectedRowCountForCells(self, self.history_lines.items[listIndex(i)].cells.items));
        self.history_lines.items[listIndex(i)].deinit(allocator);
    }
    std.mem.copyForwards(HistoryLine, self.history_lines.items[0 .. self.history_lines.items.len - drop], self.history_lines.items[drop..]);
    self.history_lines.shrinkRetainingCapacity(self.history_lines.items.len - drop);
}

fn takeReusableLine(self: anytype) struct { line: HistoryLine, slot: ?usize } {
    if (self.history_capacity == 0 or self.history_lines.items.len < self.history_capacity) return .{ .line = .{}, .slot = null };
    const slot = self.history_lines_start;
    var reusable = self.history_lines.items[slot];
    self.history_lines.items[slot] = .{};
    dropOldestProjectedRows(self, projectedRowCountForCells(self, reusable.cells.items));
    self.history_lines_start = (self.history_lines_start + 1) % self.history_lines.items.len;
    reusable.cells.clearRetainingCapacity();
    return .{ .line = reusable, .slot = slot };
}

fn appendProjectedRow(self: anytype, allocator: std.mem.Allocator, cells: []const Cell, wrapped: bool) !void {
    if (self.cols == 0) return;
    try ensureProjectedCapacity(self, allocator, self.history_count + 1);

    const wraps = self.history_wraps orelse return;
    const history = self.history orelse return;
    const slot = projectedAppendSlot(self);
    const cols = colCount(self.cols);
    const base = slot * cols;

    std.debug.assert(cells.len <= cols);
    std.debug.assert(slot < wraps.len);
    std.debug.assert(base + cols <= history.len);

    @memset(history[base .. base + cols], default_cell);
    @memcpy(history[base .. base + cells.len], cells);
    wraps[slot] = wrapped;
    self.history_count += 1;
}

fn ensureProjectedCapacity(self: anytype, allocator: std.mem.Allocator, min_rows: usize) !void {
    if (self.cols == 0) return;

    const current_rows = if (self.history_wraps) |wraps| wraps.len else 0;
    if (current_rows >= min_rows) return;

    const new_rows = @max(min_rows, @max(current_rows * 2, @as(usize, 8)));
    const cols = colCount(self.cols);
    const new_history = try allocator.alloc(Cell, new_rows * cols);
    errdefer allocator.free(new_history);
    @memset(new_history, default_cell);

    const new_wraps = try allocator.alloc(bool, new_rows);
    errdefer allocator.free(new_wraps);
    @memset(new_wraps, false);

    const old_count = self.history_count;
    std.debug.assert(old_count <= current_rows);
    var logical_row: usize = 0;
    while (logical_row < old_count) : (logical_row += 1) {
        const old_slot = slotForLogicalRow(self, logical_row) orelse break;
        const src_start = old_slot * cols;
        const dst_start = logical_row * cols;
        std.debug.assert(old_slot < current_rows);
        std.debug.assert(src_start + cols <= if (self.history) |history| history.len else 0);
        std.debug.assert(dst_start + cols <= new_history.len);
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

fn projectedAppendSlot(self: anytype) usize {
    const capacity = projectedCapacity(self);
    if (capacity == 0) return 0;
    return (self.history_write_idx + self.history_count) % capacity;
}

fn projectedCapacity(self: anytype) usize {
    return if (self.history_wraps) |wraps| wraps.len else 0;
}

fn projectedRowCountForCells(self: anytype, cells: []const Cell) usize {
    const cols = colCount(self.cols);
    if (cols == 0) return 0;
    return rowCountForCells(cells.len, cols);
}

fn dropOldestProjectedRows(self: anytype, row_count: usize) void {
    if (row_count == 0 or self.history_count == 0) return;

    const drop = @min(row_count, self.history_count);
    const capacity = projectedCapacity(self);
    std.debug.assert(drop <= self.history_count);
    if (drop == self.history_count or capacity == 0) {
        self.history_count = 0;
        self.history_write_idx = 0;
        return;
    }

    std.debug.assert(self.history_write_idx < capacity);
    self.history_write_idx = (self.history_write_idx + drop) % capacity;
    self.history_count -= drop;
}

fn colCount(cols: u16) usize {
    return @intCast(cols);
}

fn listIndex(value: u32) usize {
    return @intCast(value);
}

fn rowCountForCells(cell_count: usize, cols: usize) usize {
    return @max(1, std.math.divCeil(usize, cell_count, cols) catch unreachable);
}
