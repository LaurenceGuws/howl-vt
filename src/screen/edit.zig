//! Grid character and column edit mutations.

const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;

pub fn insertColumns(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cursor_col >= self.cols or self.scroll_top > bottom) return;
    var row = self.scroll_top;
    while (row <= bottom) : (row += 1) insertColumnsInRow(self, row, count);
}

pub fn deleteColumns(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cursor_col >= self.cols or self.scroll_top > bottom) return;
    var row = self.scroll_top;
    while (row <= bottom) : (row += 1) deleteColumnsInRow(self, row, count);
}

pub fn shiftColumnsLeft(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cols == 0 or self.scroll_top > bottom) return;
    var row = self.scroll_top;
    while (row <= bottom) : (row += 1) shiftRowLeft(self, row, count);
}

pub fn shiftColumnsRight(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cols == 0 or self.scroll_top > bottom) return;
    var row = self.scroll_top;
    while (row <= bottom) : (row += 1) shiftRowRight(self, row, count);
}

pub fn insertChars(self: anytype, count: u16) void {
    if (self.rows == 0 or self.cols == 0) return;
    if (self.cursor_col >= self.cols) return;

    const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor_col + 1);
    const row = rowCells(self, self.cursor_row) orelse return;
    const src_col = colIndex(self.cursor_col);
    const dst_col = src_col + colIndex(amount);
    const move_len = colIndex(self.rightBoundary() + 1) - dst_col;

    std.debug.assert(src_col <= dst_col);
    std.debug.assert(dst_col <= colIndex(self.rightBoundary() + 1));
    std.debug.assert(dst_col + move_len == colIndex(self.rightBoundary() + 1));
    std.debug.assert(src_col + move_len <= row.len);
    std.debug.assert(dst_col + move_len <= row.len);
    std.debug.assert(src_col + colIndex(amount) <= row.len);

    self.markDirtyCols(self.cursor_row, self.cursor_col, self.rightBoundary());
    if (move_len > 0) {
        std.mem.copyBackwards(Cell, row[dst_col .. dst_col + move_len], row[src_col .. src_col + move_len]);
    }
    @memset(row[src_col .. src_col + colIndex(amount)], self.eraseCell());
    self.setRowWrapped(self.cursor_row, false);
}

pub fn deleteChars(self: anytype, count: u16) void {
    if (self.rows == 0 or self.cols == 0) return;
    if (self.cursor_col >= self.cols) return;

    const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor_col + 1);
    const row = rowCells(self, self.cursor_row) orelse return;
    const dst_col = colIndex(self.cursor_col);
    const src_col = @min(dst_col + colIndex(amount), colIndex(self.rightBoundary() + 1));
    const move_len = colIndex(self.rightBoundary() + 1) - src_col;
    const tail_start = colIndex(self.rightBoundary() + 1) - colIndex(amount);
    const tail_end = colIndex(self.rightBoundary() + 1);

    std.debug.assert(dst_col <= src_col);
    std.debug.assert(src_col <= tail_end);
    std.debug.assert(src_col + move_len == tail_end);
    std.debug.assert(dst_col + move_len <= row.len);
    std.debug.assert(src_col + move_len <= row.len);
    std.debug.assert(tail_start <= tail_end);
    std.debug.assert(tail_end <= row.len);

    self.markDirtyCols(self.cursor_row, self.cursor_col, self.rightBoundary());
    if (move_len > 0) {
        std.mem.copyForwards(Cell, row[dst_col .. dst_col + move_len], row[src_col .. src_col + move_len]);
    }
    @memset(row[tail_start..tail_end], self.eraseCell());
    self.setRowWrapped(self.cursor_row, false);
}

fn insertColumnsInRow(self: anytype, row: u16, count: u16) void {
    const amount = @min(@max(count, 1), self.cols - self.cursor_col);
    const cells = rowCells(self, row) orelse return;
    const cursor_col = colIndex(self.cursor_col);
    const dst_col = cursor_col + colIndex(amount);
    const move_len = colIndex(self.cols) - dst_col;

    std.debug.assert(cursor_col <= dst_col);
    std.debug.assert(dst_col <= colIndex(self.cols));
    std.debug.assert(dst_col + move_len == colIndex(self.cols));
    std.debug.assert(cursor_col + move_len <= cells.len);
    std.debug.assert(dst_col + move_len <= cells.len);
    std.debug.assert(cursor_col + colIndex(amount) <= cells.len);

    self.markDirtyCols(row, self.cursor_col, self.cols -| 1);
    if (move_len > 0) std.mem.copyBackwards(Cell, cells[dst_col .. dst_col + move_len], cells[cursor_col .. cursor_col + move_len]);
    @memset(cells[cursor_col .. cursor_col + colIndex(amount)], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn deleteColumnsInRow(self: anytype, row: u16, count: u16) void {
    const amount = @min(@max(count, 1), self.cols - self.cursor_col);
    const cells = rowCells(self, row) orelse return;
    const cursor_col = colIndex(self.cursor_col);
    const src_col = @min(cursor_col + colIndex(amount), colIndex(self.cols));
    const move_len = colIndex(self.cols) - src_col;

    std.debug.assert(cursor_col <= src_col);
    std.debug.assert(src_col <= colIndex(self.cols));
    std.debug.assert(src_col + move_len == colIndex(self.cols));
    std.debug.assert(cursor_col + move_len <= cells.len);
    std.debug.assert(src_col + move_len <= cells.len);
    std.debug.assert(colIndex(self.cols) - colIndex(amount) <= colIndex(self.cols));

    self.markDirtyCols(row, self.cursor_col, self.cols -| 1);
    if (move_len > 0) std.mem.copyForwards(Cell, cells[cursor_col .. cursor_col + move_len], cells[src_col .. src_col + move_len]);
    @memset(cells[colIndex(self.cols) - colIndex(amount) .. colIndex(self.cols)], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn shiftRowLeft(self: anytype, row: u16, count: u16) void {
    const left = if (self.left_right_margin_mode) self.left_margin else 0;
    const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    if (left > right or right >= self.cols) return;

    const width = right - left + 1;
    const amount = @min(@max(count, 1), width);
    const cells = rowCells(self, row) orelse return;
    const left_idx = colIndex(left);
    const move_len = colIndex(width - amount);

    std.debug.assert(width > 0);
    std.debug.assert(amount <= width);
    std.debug.assert(right + 1 <= self.cols);
    std.debug.assert(left_idx + colIndex(width) <= cells.len);
    std.debug.assert(left_idx + colIndex(amount) + move_len <= cells.len);
    std.debug.assert(left_idx + move_len <= left_idx + colIndex(width));

    self.markDirtyCols(row, left, right);
    if (move_len > 0) {
        std.mem.copyForwards(Cell, cells[left_idx .. left_idx + move_len], cells[left_idx + colIndex(amount) .. left_idx + colIndex(amount) + move_len]);
    }
    @memset(cells[left_idx + move_len .. left_idx + colIndex(width)], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn shiftRowRight(self: anytype, row: u16, count: u16) void {
    const left = if (self.left_right_margin_mode) self.left_margin else 0;
    const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    if (left > right or right >= self.cols) return;

    const width = right - left + 1;
    const amount = @min(@max(count, 1), width);
    const cells = rowCells(self, row) orelse return;
    const left_idx = colIndex(left);
    const move_len = colIndex(width - amount);

    std.debug.assert(width > 0);
    std.debug.assert(amount <= width);
    std.debug.assert(right + 1 <= self.cols);
    std.debug.assert(left_idx + colIndex(width) <= cells.len);
    std.debug.assert(left_idx + colIndex(amount) + move_len <= cells.len);
    std.debug.assert(left_idx + colIndex(amount) <= left_idx + colIndex(width));

    self.markDirtyCols(row, left, right);
    if (move_len > 0) {
        std.mem.copyBackwards(Cell, cells[left_idx + colIndex(amount) .. left_idx + colIndex(amount) + move_len], cells[left_idx .. left_idx + move_len]);
    }
    @memset(cells[left_idx .. left_idx + colIndex(amount)], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn rowCells(self: anytype, row: u16) ?[]Cell {
    const c = self.cells orelse return null;
    const start = self.rowStart(row);
    std.debug.assert(row < self.rows);
    std.debug.assert(start + colIndex(self.cols) <= c.len);
    return c[start .. start + colIndex(self.cols)];
}

fn colIndex(value: u16) usize {
    return @intCast(value);
}
