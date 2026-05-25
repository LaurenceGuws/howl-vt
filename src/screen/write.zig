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
    if (appendCombiningToLeadCell(self, cp)) return;

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
        c[@intCast(start + @as(u32, self.cursor_col))] = .{
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

fn appendCombiningToLeadCell(self: anytype, cp: u21) bool {
    if (!isTrailingCombiningCodepoint(cp)) return false;

    const pos = previousLeadCellPos(self) orelse return false;
    const cells = self.cells orelse return false;
    const idx = self.rowStart(pos.row) + @as(u32, pos.col);
    const cell = &cells[@intCast(idx)];
    if (cell.codepoint == 0) return false;
    if (cell.combining_len >= cell.combining.len) return true;

    cell.combining[cell.combining_len] = cp;
    cell.combining_len += 1;
    self.markDirtyCols(pos.row, pos.col, pos.col);
    return true;
}

fn previousLeadCellPos(self: anytype) ?struct { row: u16, col: u16 } {
    const right = self.rightBoundary();
    if (self.wrap_pending) return .{ .row = self.cursor_row, .col = right };

    if (cursorCellHasText(self)) return .{ .row = self.cursor_row, .col = self.cursor_col };
    if (self.cursor_col == 0) return null;
    return .{ .row = self.cursor_row, .col = self.cursor_col - 1 };
}

fn cursorCellHasText(self: anytype) bool {
    const cells = self.cells orelse return false;
    if (self.cursor_row >= self.rows) return false;
    if (self.cursor_col >= self.cols) return false;
    const idx = self.rowStart(self.cursor_row) + @as(u32, self.cursor_col);
    return cells[@intCast(idx)].codepoint != 0;
}

fn isTrailingCombiningCodepoint(cp: u21) bool {
    return switch (cp) {
        0x0300...0x036F,
        0x1AB0...0x1AFF,
        0x1DC0...0x1DFF,
        0x20D0...0x20FF,
        0x200C...0x200D,
        0xFE00...0xFE0F,
        0xFE20...0xFE2F,
        0xE0100...0xE01EF,
        => true,
        else => false,
    };
}
