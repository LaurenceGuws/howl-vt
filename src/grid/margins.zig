//! Grid scroll and left/right margin configuration.

pub fn setScrollRegion(self: anytype, top: u16, bottom: ?u16) void {
    if (self.rows == 0) {
        self.scroll_top = 0;
        self.scroll_bottom = 0;
        self.cursor_row = 0;
        self.cursor_col = 0;
        return;
    }

    const new_top = @min(top, self.rows - 1);
    const new_bottom = if (bottom) |value| @min(value, self.rows - 1) else self.rows - 1;
    if (new_top >= new_bottom) return;

    self.scroll_top = new_top;
    self.scroll_bottom = new_bottom;
    self.cursor_row = if (self.origin_mode) self.scroll_top else 0;
    self.cursor_col = self.lineHomeCol();
}

pub fn setLeftRightMode(self: anytype, enabled: bool) void {
    self.left_right_margin_mode = enabled;
    if (!enabled) {
        self.left_margin = 0;
        self.right_margin = self.cols -| 1;
    }
}

pub fn setLeftRightMargins(self: anytype, left: u16, right: ?u16) void {
    if (!self.left_right_margin_mode or self.cols < 2) return;
    const new_left = @min(left, self.cols - 2);
    const new_right = if (right) |value| @min(value, self.cols - 1) else self.cols - 1;
    if (new_left >= new_right) return;
    self.left_margin = new_left;
    self.right_margin = new_right;
    self.wrap_pending = false;
    self.cursor_row = if (self.origin_mode) self.scroll_top else 0;
    self.cursor_col = self.lineHomeCol();
}
