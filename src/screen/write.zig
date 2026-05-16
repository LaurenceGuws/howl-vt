//! Printable grid writes and repeat-preceding behavior.

pub fn writeText(self: anytype, text: []const u8) void {
    for (text) |byte| writeCell(self, @intCast(byte));
}

pub fn repeatPreceding(self: anytype, count: u16) void {
    if (self.last_graphic_codepoint) |cp| {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) writeCell(self, cp);
    }
}

pub fn writeCell(self: anytype, cp: u21) void {
    if (self.cols == 0 or self.rows == 0) return;
    const right = self.rightBoundary();
    if (self.wrap_pending) {
        self.wrap_pending = false;
        if (self.cursor_col == right) {
            self.setRowWrapped(self.cursor_row, true);
            self.lineFeed();
            self.cursor_col = if (self.left_right_margin_mode) self.left_margin else 0;
        }
    }
    if (self.insert_mode) self.insertChars(1);
    if (self.cells) |c| {
        const start = self.rowStart(self.cursor_row);
        self.markDirtyCols(self.cursor_row, self.cursor_col, self.cursor_col);
        c[start + @as(usize, self.cursor_col)] = .{
            .codepoint = cp,
            .attrs = self.current_attrs,
        };
    }
    self.last_graphic_codepoint = cp;
    if (self.cursor_col < right) {
        self.cursor_col += 1;
    } else if (self.auto_wrap) {
        self.wrap_pending = true;
    }
}
