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

    if (self.cursor_col == 0) return null;
    return .{ .row = self.cursor_row, .col = self.cursor_col - 1 };
}

fn isTrailingCombiningCodepoint(cp: u21) bool {
    return switch (cp) {
        0x0300...0x036F,
        0x0483...0x0489,
        0x0591...0x05BD,
        0x05BF,
        0x05C1...0x05C2,
        0x05C4...0x05C5,
        0x0610...0x061A,
        0x064B...0x065F,
        0x0670,
        0x06D6...0x06DC,
        0x06DF...0x06E4,
        0x06E7...0x06E8,
        0x06EB...0x06EC,
        0x0730...0x074A,
        0x07EB...0x07F3,
        0x0816...0x0819,
        0x081B...0x0823,
        0x0825...0x0827,
        0x0829...0x082D,
        0x0951...0x0954,
        0x0F82...0x0F83,
        0x0F86...0x0F87,
        0x135D...0x135F,
        0x17DD,
        0x193A,
        0x1A17,
        0x1A75...0x1A7C,
        0x1B6B...0x1B73,
        0x1CD0...0x1CD2,
        0x1CDA...0x1CDB,
        0x1CE0,
        0x1AB0...0x1AFF,
        0x1DC0...0x1DFF,
        0x20D0...0x20FF,
        0x2CEF...0x2CF1,
        0x2DE0...0x2DFF,
        0xA66F,
        0xA67C...0xA67D,
        0xA6F0...0xA6F1,
        0xA8E0...0xA8F1,
        0xAAB0,
        0xAAB2...0xAAB3,
        0xAAB7...0xAAB8,
        0xAABE...0xAABF,
        0xAAC1,
        0x200C...0x200D,
        0xFE00...0xFE0F,
        0xFE20...0xFE2F,
        0x10A0F,
        0x10A38,
        0x1D185...0x1D189,
        0x1D1AA...0x1D1AD,
        0x1D242...0x1D244,
        0xE0100...0xE01EF,
        => true,
        else => false,
    };
}
