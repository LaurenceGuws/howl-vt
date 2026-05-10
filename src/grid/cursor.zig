//! Grid cursor bounds, origin, and save/restore.

pub const CursorShape = enum {
    block,
    underline,
    bar,
};

pub const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

pub const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

pub fn resolveAbsoluteRow(self: anytype, row: u16) u16 {
    if (!self.origin_mode) return row;
    const bottom = if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    const region_len = bottom - self.scroll_top;
    return self.scroll_top + @min(row, region_len);
}

pub fn resolveAbsoluteCol(self: anytype, col: u16) u16 {
    if (!(self.origin_mode and self.left_right_margin_mode)) return col;
    const region_len = self.right_margin - self.left_margin;
    return self.left_margin + @min(col, region_len);
}

pub fn save(self: anytype) void {
    self.saved_cursor = .{
        .row = self.cursor_row,
        .col = self.cursor_col,
        .wrap_pending = self.wrap_pending,
    };
}

pub fn restore(self: anytype) void {
    if (self.saved_cursor) |saved| {
        self.cursor_row = @min(saved.row, self.rows -| 1);
        self.cursor_col = @min(saved.col, rightBoundary(self));
        self.wrap_pending = saved.wrap_pending;
    }
}

pub fn lineHomeCol(self: anytype) u16 {
    return if (self.origin_mode and self.left_right_margin_mode) self.left_margin else 0;
}

pub fn leftBoundary(self: anytype) u16 {
    return if (self.left_right_margin_mode) self.left_margin else 0;
}

pub fn rightBoundary(self: anytype) u16 {
    return if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
}
