const std = @import("std");
const grid = @import("../grid.zig");
const screen_set = @import("set.zig");

const Grid = grid.Grid;
const ScreenSet = screen_set.Set;

pub const Options = struct {
    scrollback_offset: usize = 0,
};

pub const RowSource = union(enum) {
    history: u32,
    screen: u16,
};

/// Read-only scrollback-aware view of terminal rows visible to a host.
pub const View = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cursor_visible: bool,
    cursor_shape: Grid.CursorShape,
    is_alternate_screen: bool,
    scrollback_offset: u32,
    history_count: u32,
    start: u32,
    screen: *const Grid,

    pub fn rowSource(self: View, row: u16) RowSource {
        if (self.rows == 0 or row >= self.rows) return .{ .screen = 0 };
        const src_row = self.start + rowIndex(row);
        std.debug.assert(self.start + rowIndex(self.rows) <= self.history_count + rowIndex(self.rows));
        std.debug.assert(src_row >= self.start);
        std.debug.assert(src_row < self.history_count + rowIndex(self.rows));
        if (src_row < self.history_count) {
            return .{ .history = self.history_count - 1 - src_row };
        }
        return .{ .screen = @intCast(@min(src_row - self.history_count, rowIndex(self.rows -| 1))) };
    }

    pub fn sourceCellInfoAt(self: View, source: RowSource, col: u16) Grid.Cell {
        return switch (source) {
            .history => |recency| self.screen.historyCellAt(recency, col),
            .screen => |screen_row| self.screen.cellInfoAt(screen_row, col),
        };
    }

    pub fn cellInfoAt(self: View, row: u16, col: u16) Grid.Cell {
        return self.sourceCellInfoAt(self.rowSource(row), col);
    }

    pub fn cellAt(self: View, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    pub fn rowDepth(self: View, row: u16) u32 {
        if (self.rows == 0 or row >= self.rows) return self.scrollback_offset;
        std.debug.assert(self.scrollback_offset <= self.history_count);
        return self.scrollback_offset + rowIndex(self.rows - 1 - row);
    }

    pub fn contentEndExclusive(self: View, row: u16) u16 {
        if (self.scrollback_offset == 0 and row > self.cursor_row) return 0;
        var scan = self.cols;
        while (scan > 0) {
            const idx = scan - 1;
            const cell = self.cellInfoAt(row, idx);
            if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
            scan -= 1;
        }
        return if (self.cols > 0) 1 else 0;
    }
};

pub fn visibleView(screen_state: *const ScreenSet, options: Options) View {
    const active = screen_state.activeConst();
    const history_count: u32 = if (screen_state.alt_active) 0 else @intCast(active.historyCount());
    const offset: u32 = @intCast(@min(options.scrollback_offset, @as(usize, history_count)));
    const rows_count: u32 = active.rows;
    const total_rows = history_count + rows_count;
    const start = if (total_rows >= rows_count + offset) total_rows - rows_count - offset else 0;
    std.debug.assert(offset <= history_count);
    std.debug.assert(total_rows >= rows_count);
    std.debug.assert(start + rows_count <= total_rows);
    std.debug.assert(total_rows - (start + rows_count) == offset);
    return .{
        .rows = active.rows,
        .cols = active.cols,
        .cursor_row = active.cursor_row,
        .cursor_col = active.cursor_col,
        .cursor_visible = active.cursor_visible,
        .cursor_shape = active.cursor_style.shape,
        .is_alternate_screen = screen_state.alt_active,
        .scrollback_offset = offset,
        .history_count = history_count,
        .start = start,
        .screen = active,
    };
}

pub fn peekDirtyRows(screen_state: *const ScreenSet) ?Grid.DirtyRows {
    return screen_state.activeConst().peekDirtyRows();
}

pub fn clearDirtyRows(screen_state: *ScreenSet) void {
    screen_state.active().clearDirtyRows();
}

pub fn historyRowAt(screen_state: *const ScreenSet, history_idx: usize, col: u16) u21 {
    if (screen_state.alt_active) return 0;
    return screen_state.primary.historyRowAt(history_idx, col);
}

pub fn historyCellAt(screen_state: *const ScreenSet, history_idx: usize, col: u16) Grid.Cell {
    if (screen_state.alt_active) return Grid.default_cell;
    return screen_state.primary.historyCellAt(history_idx, col);
}

pub fn historyCapacity(screen_state: *const ScreenSet) u16 {
    return screen_state.primary.historyCapacity();
}

fn rowIndex(row: u16) u32 {
    return row;
}
