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

pub fn deleteChars(self: anytype, count: u16) void {
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

fn insertColumnsInRow(self: anytype, row: u16, count: u16) void {
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

fn deleteColumnsInRow(self: anytype, row: u16, count: u16) void {
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

fn shiftRowLeft(self: anytype, row: u16, count: u16) void {
    const c = self.cells orelse return;
    const left = if (self.left_right_margin_mode) self.left_margin else 0;
    const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    if (left > right or right >= self.cols) return;

    const width = right - left + 1;
    const amount = @min(@max(count, 1), width);
    const start = self.rowStart(row);
    const cells = c[start .. start + @as(usize, self.cols)];
    const left_idx = @as(usize, left);
    const move_len = @as(usize, width - amount);

    self.markDirtyCols(row, left, right);
    if (move_len > 0) {
        std.mem.copyForwards(Cell, cells[left_idx .. left_idx + move_len], cells[left_idx + @as(usize, amount) .. left_idx + @as(usize, amount) + move_len]);
    }
    @memset(cells[left_idx + move_len .. left_idx + @as(usize, width)], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn shiftRowRight(self: anytype, row: u16, count: u16) void {
    const c = self.cells orelse return;
    const left = if (self.left_right_margin_mode) self.left_margin else 0;
    const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    if (left > right or right >= self.cols) return;

    const width = right - left + 1;
    const amount = @min(@max(count, 1), width);
    const start = self.rowStart(row);
    const cells = c[start .. start + @as(usize, self.cols)];
    const left_idx = @as(usize, left);
    const move_len = @as(usize, width - amount);

    self.markDirtyCols(row, left, right);
    if (move_len > 0) {
        std.mem.copyBackwards(Cell, cells[left_idx + @as(usize, amount) .. left_idx + @as(usize, amount) + move_len], cells[left_idx .. left_idx + move_len]);
    }
    @memset(cells[left_idx .. left_idx + @as(usize, amount)], self.eraseCell());
    self.setRowWrapped(row, false);
}
