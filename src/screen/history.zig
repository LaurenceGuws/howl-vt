const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;

/// Convert a checked standard-library length to the history/reflow domain.
pub fn count32(len: usize) u32 {
    std.debug.assert(len <= std.math.maxInt(u32));
    return @intCast(len);
}

/// Return rows needed for `cell_count`, or zero when no columns exist.
pub fn rowCountForCells(cell_count: u32, cols: u16) u32 {
    if (cols == 0) return 0;
    return @max(@as(u32, 1), std.math.divCeil(u32, cell_count, cols) catch unreachable);
}

/// Owned logical terminal line used while reflowing retained content.
pub const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(Cell) = .empty,
    cursor_offset: ?u32 = null,

    /// Release cloned cells and reset the line.
    pub fn deinit(self: *LogicalLine, allocator: std.mem.Allocator) void {
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Owned logical-content snapshot and cursor location used by resize.
pub const LogicalSnapshot = struct {
    logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty,
    cursor_found: bool = false,
    cursor_line_index: u32 = 0,
    cursor_offset: u32 = 0,

    /// Release every cloned line and reset the snapshot.
    pub fn deinit(self: *LogicalSnapshot, allocator: std.mem.Allocator) void {
        for (self.logical_lines.items) |*line| line.deinit(allocator);
        self.logical_lines.deinit(allocator);
        self.* = .{};
    }
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
    std.debug.assert(first_visible_line <= count32(logical_lines.len));
    if (first_visible_line < count32(logical_lines.len)) {
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

    if (first_visible_line < count32(logical_lines.len) and hidden_rows_in_first_visible_line > 0) {
        const line = logical_lines[@intCast(first_visible_line)];
        const row_start = line_row_starts[@intCast(first_visible_line)];
        const row_limit = @min(hidden_rows_in_first_visible_line, line_row_counts[@intCast(first_visible_line)]);
        std.debug.assert(row_start + row_limit <= count32(rewrapped.len));
        var prefix_len: u32 = 0;
        var hidden_row: u16 = 0;
        while (hidden_row < row_limit) : (hidden_row += 1) {
            const row = rewrapped[@intCast(row_start + hidden_row)];
            std.debug.assert(row.len <= cols);
            prefix_len += rewrapped[@intCast(row_start + hidden_row)].len;
        }
        prefix_len = @min(prefix_len, count32(line.cells.items.len));
        std.debug.assert(prefix_len <= count32(line.cells.items.len));
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

fn cloneAuthorityLine(allocator: std.mem.Allocator, cells: []const Cell) !HistoryLine {
    var line = HistoryLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    return line;
}
