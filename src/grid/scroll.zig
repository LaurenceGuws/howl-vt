//! Responsibility: own line feed and scrolling mutations.
//! Ownership: terminal grid scroll concern.
//! Reason: keep viewport movement separate from grid state storage fields.

const types = @import("types.zig");

pub fn lineFeed(self: anytype) void {
    if (self.rows == 0) return;
    const bottom = self.scrollBottom();
    if (self.cursor_row < bottom) {
        self.cursor_row += 1;
        return;
    }
    if (self.cursor_row == bottom) {
        scrollUpRegion(self, self.scroll_top, bottom, 1);
        return;
    }
    if (self.cursor_row < self.rows - 1) self.cursor_row += 1;
}

pub fn reverseIndex(self: anytype) void {
    if (self.rows == 0) return;
    if (self.cursor_row == self.scroll_top) {
        scrollDownRegion(self, self.scroll_top, self.scrollBottom(), 1);
    } else {
        self.cursor_row = self.cursor_row -| 1;
    }
}

pub fn scrollUp(self: anytype) void {
    const c = self.cells orelse return;
    if (self.rows == 0 or self.cols == 0) return;
    self.markAllRowsDirty();
    const row_len = @as(usize, self.cols);
    self.storeHistoryRow(0);
    self.row_origin = @intCast((@as(usize, self.row_origin) + 1) % @as(usize, self.rows));
    const bottom_start = self.rowStart(self.rows - 1);
    @memset(c[bottom_start .. bottom_start + row_len], types.default_cell);
    self.setRowWrapped(self.rows - 1, false);
}

pub fn insertLines(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cursor_row < self.scroll_top or self.cursor_row > bottom) return;
    scrollDownRegion(self, self.cursor_row, bottom, count);
}

pub fn deleteLines(self: anytype, count: u16) void {
    const bottom = self.scrollBottom();
    if (self.cursor_row < self.scroll_top or self.cursor_row > bottom) return;
    scrollUpRegion(self, self.cursor_row, bottom, count);
}

pub fn scrollUpRegion(self: anytype, top: u16, bottom: u16, count: u16) void {
    if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return;
    const bounded_bottom = @min(bottom, self.rows - 1);
    const region_len: u16 = bounded_bottom - top + 1;
    const amount = @min(count, region_len);
    if (amount == 0) return;

    if (top == 0 and bounded_bottom == self.rows - 1) {
        var remaining = amount;
        while (remaining > 0) : (remaining -= 1) scrollUp(self);
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

pub fn scrollDownRegion(self: anytype, top: u16, bottom: u16, count: u16) void {
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
