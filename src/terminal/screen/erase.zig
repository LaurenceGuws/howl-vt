const cell_mod = @import("cell.zig");
const events = @import("../../action/vocabulary.zig");

const EraseMode = events.EraseMode;

pub fn eraseDisplay(self: anytype, mode: EraseMode) void {
    const c = self.cells orelse return;
    if (self.rows == 0 or self.cols == 0) return;
    switch (mode) {
        .cursor_to_end => {
            self.markDirtyRows(self.cursor_row, self.rows -| 1);
            self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
            var r = self.cursor_row + 1;
            while (r < self.rows) : (r += 1) {
                self.clearRowRange(r, 0, self.cols);
                self.setRowWrapped(r, false);
            }
        },
        .start_to_cursor => {
            self.markDirtyRows(0, self.cursor_row);
            var r: u16 = 0;
            while (r < self.cursor_row) : (r += 1) {
                self.clearRowRange(r, 0, self.cols);
                self.setRowWrapped(r, false);
            }
            self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
        },
        .all => {
            self.markAllRowsDirty();
            const cell = self.eraseCell();
            @memset(c, cell);
            if (self.row_wraps) |buf| @memset(buf, false);
        },
        .scrollback => self.clearScrollback(),
    }
}

pub fn eraseLine(self: anytype, mode: EraseMode) void {
    _ = self.cells orelse return;
    if (self.rows == 0 or self.cols == 0) return;
    switch (mode) {
        .cursor_to_end => {
            self.markDirtyCols(self.cursor_row, self.cursor_col, self.cols -| 1);
            self.clearRowRange(self.cursor_row, self.cursor_col, self.cols);
        },
        .start_to_cursor => {
            self.markDirtyCols(self.cursor_row, 0, self.cursor_col);
            self.clearRowRange(self.cursor_row, 0, self.cursor_col + 1);
        },
        .all => {
            self.markDirtyRow(self.cursor_row);
            self.clearRowRange(self.cursor_row, 0, self.cols);
            self.setRowWrapped(self.cursor_row, false);
        },
        .scrollback => {},
    }
}

pub fn eraseChars(self: anytype, count: u16) void {
    if (self.rows == 0 or self.cols == 0) return;
    const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor_col + 1);
    self.markDirtyCols(self.cursor_row, self.cursor_col, self.cursor_col + amount - 1);
    self.clearRowRange(self.cursor_row, self.cursor_col, self.cursor_col + amount);
}

pub fn selectiveEraseDisplay(self: anytype, mode: EraseMode) void {
    if (self.rows == 0 or self.cols == 0) return;
    switch (mode) {
        .cursor_to_end => {
            self.selectiveClearRowRange(self.cursor_row, self.cursor_col, self.cols);
            var row = self.cursor_row + 1;
            while (row < self.rows) : (row += 1) {
                self.selectiveClearRowRange(row, 0, self.cols);
                self.setRowWrapped(row, false);
            }
        },
        .start_to_cursor => {
            var row: u16 = 0;
            while (row < self.cursor_row) : (row += 1) {
                self.selectiveClearRowRange(row, 0, self.cols);
                self.setRowWrapped(row, false);
            }
            self.selectiveClearRowRange(self.cursor_row, 0, self.cursor_col + 1);
        },
        .all => {
            var row: u16 = 0;
            while (row < self.rows) : (row += 1) {
                self.selectiveClearRowRange(row, 0, self.cols);
                self.setRowWrapped(row, false);
            }
        },
        .scrollback => {},
    }
}

pub fn selectiveEraseLine(self: anytype, mode: EraseMode) void {
    if (self.rows == 0 or self.cols == 0) return;
    switch (mode) {
        .cursor_to_end => self.selectiveClearRowRange(self.cursor_row, self.cursor_col, self.cols),
        .start_to_cursor => self.selectiveClearRowRange(self.cursor_row, 0, self.cursor_col + 1),
        .all => {
            self.selectiveClearRowRange(self.cursor_row, 0, self.cols);
            self.setRowWrapped(self.cursor_row, false);
        },
        .scrollback => {},
    }
}

pub fn clearRowRange(self: anytype, row: u16, start_col: u16, end_col_exclusive: u16) void {
    const c = self.cells orelse return;
    const start = self.rowStart(row);
    const cell = self.eraseCell();
    @memset(c[@intCast(start + @as(u32, start_col))..@intCast(start + @as(u32, end_col_exclusive))], cell);
}

pub fn selectiveClearRowRange(self: anytype, row: u16, start_col: u16, end_col_exclusive: u16) void {
    const c = self.cells orelse return;
    const start = self.rowStart(row);
    const cell = self.eraseCell();
    var col = start_col;
    while (col < end_col_exclusive) : (col += 1) {
        const idx = start + @as(u32, col);
        if (c[@intCast(idx)].attrs.protected) continue;
        c[@intCast(idx)] = cell;
    }
}

pub fn eraseCell(self: anytype) cell_mod.Cell {
    return .{ .codepoint = 0, .attrs = self.current_attrs };
}

pub fn clearFullRow(self: anytype, row: u16) void {
    if (self.cols == 0) return;
    clearRowRange(self, row, 0, self.cols);
    self.setRowWrapped(row, false);
}
