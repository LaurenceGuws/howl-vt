//! Responsibility: own dirty-row tracking payloads and allocation helpers.
//! Ownership: terminal grid dirty-region concern.
//! Reason: keep repaint invalidation bookkeeping separate from screen mutation logic.

const std = @import("std");

pub const DirtyRows = struct {
    start_row: u16,
    end_row: u16,
    dirty_cols_start: []const u16 = &.{},
    dirty_cols_end: []const u16 = &.{},
};

pub fn allocDirtyCols(allocator: std.mem.Allocator, rows: u16, initial: u16) !?[]u16 {
    if (rows == 0) return null;
    const buf = try allocator.alloc(u16, rows);
    @memset(buf, initial);
    return buf;
}

pub fn rowsForFull(rows: u16, dirty_cols_start: ?[]const u16, dirty_cols_end: ?[]const u16) ?DirtyRows {
    if (rows == 0) return null;
    return .{
        .start_row = 0,
        .end_row = rows -| 1,
        .dirty_cols_start = dirty_cols_start orelse &.{},
        .dirty_cols_end = dirty_cols_end orelse &.{},
    };
}

pub fn markRow(self: anytype, row: u16) void {
    if (self.rows == 0 or row >= self.rows) return;
    markCols(self, row, 0, self.cols -| 1);
}

pub fn markCols(self: anytype, row: u16, start_col: u16, end_col: u16) void {
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

pub fn markRows(self: anytype, start_row: u16, end_row: u16) void {
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

pub fn markAllRows(self: anytype) void {
    if (self.rows == 0) return;
    if (self.dirty_cols_start) |buf| @memset(buf, 0);
    if (self.dirty_cols_end) |buf| @memset(buf, self.cols -| 1);
    self.dirty_rows = rowsForFull(self.rows, self.dirty_cols_start, self.dirty_cols_end);
}
