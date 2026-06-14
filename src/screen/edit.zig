const std = @import("std");
const cell = @import("cell.zig");

const Cell = cell.Cell;

pub fn insertColumns(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cursor.col >= self.cols or self.scroll_top > bottom) return;
    var row = self.scroll_top;
    while (row <= bottom) : (row += 1) insertColumnsInRow(self, row, count);
}

pub fn deleteColumns(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cursor.col >= self.cols or self.scroll_top > bottom) return;
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
    if (self.cursor.col >= self.cols) return;

    const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
    const row = rowCells(self, self.cursor.row) orelse return;
    const src_col = colCount(self.cursor.col);
    const dst_col = src_col + colCount(amount);
    const move_len = colCount(self.rightBoundary() + 1) - dst_col;

    std.debug.assert(src_col <= dst_col);
    std.debug.assert(dst_col <= colCount(self.rightBoundary() + 1));
    std.debug.assert(dst_col + move_len == colCount(self.rightBoundary() + 1));
    std.debug.assert(src_col + move_len <= row.len);
    std.debug.assert(dst_col + move_len <= row.len);
    std.debug.assert(src_col + colCount(amount) <= row.len);

    self.markDirtyCols(self.cursor.row, self.cursor.col, self.rightBoundary());
    if (move_len > 0) {
        std.mem.copyBackwards(Cell, row[@intCast(dst_col)..@intCast(dst_col + move_len)], row[@intCast(src_col)..@intCast(src_col + move_len)]);
    }
    @memset(row[@intCast(src_col)..@intCast(src_col + colCount(amount))], self.eraseCell());
    self.setRowWrapped(self.cursor.row, false);
}

pub fn deleteChars(self: anytype, count: u16) void {
    if (self.rows == 0 or self.cols == 0) return;
    if (self.cursor.col >= self.cols) return;

    const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
    const row = rowCells(self, self.cursor.row) orelse return;
    const dst_col = colCount(self.cursor.col);
    const src_col = @min(dst_col + colCount(amount), colCount(self.rightBoundary() + 1));
    const move_len = colCount(self.rightBoundary() + 1) - src_col;
    const tail_start = colCount(self.rightBoundary() + 1) - colCount(amount);
    const tail_end = colCount(self.rightBoundary() + 1);

    std.debug.assert(dst_col <= src_col);
    std.debug.assert(src_col <= tail_end);
    std.debug.assert(src_col + move_len == tail_end);
    std.debug.assert(dst_col + move_len <= row.len);
    std.debug.assert(src_col + move_len <= row.len);
    std.debug.assert(tail_start <= tail_end);
    std.debug.assert(tail_end <= row.len);

    self.markDirtyCols(self.cursor.row, self.cursor.col, self.rightBoundary());
    if (move_len > 0) {
        std.mem.copyForwards(Cell, row[@intCast(dst_col)..@intCast(dst_col + move_len)], row[@intCast(src_col)..@intCast(src_col + move_len)]);
    }
    @memset(row[@intCast(tail_start)..@intCast(tail_end)], self.eraseCell());
    self.setRowWrapped(self.cursor.row, false);
}

fn insertColumnsInRow(self: anytype, row: u16, count: u16) void {
    const amount = @min(@max(count, 1), self.cols - self.cursor.col);
    const cells = rowCells(self, row) orelse return;
    const cursor_col = colCount(self.cursor.col);
    const dst_col = cursor_col + colCount(amount);
    const move_len = colCount(self.cols) - dst_col;

    std.debug.assert(cursor_col <= dst_col);
    std.debug.assert(dst_col <= colCount(self.cols));
    std.debug.assert(dst_col + move_len == colCount(self.cols));
    std.debug.assert(cursor_col + move_len <= cells.len);
    std.debug.assert(dst_col + move_len <= cells.len);
    std.debug.assert(cursor_col + colCount(amount) <= cells.len);

    self.markDirtyCols(row, self.cursor.col, self.cols -| 1);
    if (move_len > 0) std.mem.copyBackwards(Cell, cells[@intCast(dst_col)..@intCast(dst_col + move_len)], cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)]);
    @memset(cells[@intCast(cursor_col)..@intCast(cursor_col + colCount(amount))], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn deleteColumnsInRow(self: anytype, row: u16, count: u16) void {
    const amount = @min(@max(count, 1), self.cols - self.cursor.col);
    const cells = rowCells(self, row) orelse return;
    const cursor_col = colCount(self.cursor.col);
    const src_col = @min(cursor_col + colCount(amount), colCount(self.cols));
    const move_len = colCount(self.cols) - src_col;

    std.debug.assert(cursor_col <= src_col);
    std.debug.assert(src_col <= colCount(self.cols));
    std.debug.assert(src_col + move_len == colCount(self.cols));
    std.debug.assert(cursor_col + move_len <= cells.len);
    std.debug.assert(src_col + move_len <= cells.len);
    std.debug.assert(colCount(self.cols) - colCount(amount) <= colCount(self.cols));

    self.markDirtyCols(row, self.cursor.col, self.cols -| 1);
    if (move_len > 0) std.mem.copyForwards(Cell, cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)], cells[@intCast(src_col)..@intCast(src_col + move_len)]);
    @memset(cells[@intCast(colCount(self.cols) - colCount(amount))..@intCast(colCount(self.cols))], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn shiftRowLeft(self: anytype, row: u16, count: u16) void {
    const left = if (self.left_right_margin_mode) self.left_margin else 0;
    const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    if (left > right or right >= self.cols) return;

    const width = right - left + 1;
    const amount = @min(@max(count, 1), width);
    const cells = rowCells(self, row) orelse return;
    const left_idx = colCount(left);
    const move_len = colCount(width - amount);

    std.debug.assert(width > 0);
    std.debug.assert(amount <= width);
    std.debug.assert(right + 1 <= self.cols);
    std.debug.assert(left_idx + colCount(width) <= cells.len);
    std.debug.assert(left_idx + colCount(amount) + move_len <= cells.len);
    std.debug.assert(left_idx + move_len <= left_idx + colCount(width));

    self.markDirtyCols(row, left, right);
    if (move_len > 0) {
        std.mem.copyForwards(Cell, cells[@intCast(left_idx)..@intCast(left_idx + move_len)], cells[@intCast(left_idx + colCount(amount))..@intCast(left_idx + colCount(amount) + move_len)]);
    }
    @memset(cells[@intCast(left_idx + move_len)..@intCast(left_idx + colCount(width))], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn shiftRowRight(self: anytype, row: u16, count: u16) void {
    const left = if (self.left_right_margin_mode) self.left_margin else 0;
    const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
    if (left > right or right >= self.cols) return;

    const width = right - left + 1;
    const amount = @min(@max(count, 1), width);
    const cells = rowCells(self, row) orelse return;
    const left_idx = colCount(left);
    const move_len = colCount(width - amount);

    std.debug.assert(width > 0);
    std.debug.assert(amount <= width);
    std.debug.assert(right + 1 <= self.cols);
    std.debug.assert(left_idx + colCount(width) <= cells.len);
    std.debug.assert(left_idx + colCount(amount) + move_len <= cells.len);
    std.debug.assert(left_idx + colCount(amount) <= left_idx + colCount(width));

    self.markDirtyCols(row, left, right);
    if (move_len > 0) {
        std.mem.copyBackwards(Cell, cells[@intCast(left_idx + colCount(amount))..@intCast(left_idx + colCount(amount) + move_len)], cells[@intCast(left_idx)..@intCast(left_idx + move_len)]);
    }
    @memset(cells[@intCast(left_idx)..@intCast(left_idx + colCount(amount))], self.eraseCell());
    self.setRowWrapped(row, false);
}

fn rowCells(self: anytype, row: u16) ?[]Cell {
    const c = self.cells orelse return null;
    const start = self.rowStart(row);
    std.debug.assert(row < self.rows);
    std.debug.assert(start + colCount(self.cols) <= c.len);
    return c[@intCast(start)..@intCast(start + colCount(self.cols))];
}

fn colCount(value: u16) u32 {
    return value;
}
