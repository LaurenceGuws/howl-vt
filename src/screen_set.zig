const std = @import("std");
const screen_mod = @import("screen.zig");
const selection = @import("selection.zig");

const Screen = screen_mod.Screen;
const SelectionState = selection.SelectionState;

pub const Options = struct {
    scrollback_offset: u32 = 0,
};

pub const RowSource = union(enum) {
    history: u32,
    screen: u16,
};

pub const View = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cursor_visible: bool,
    cursor_shape: Screen.CursorShape,
    is_alternate_screen: bool,
    scrollback_offset: u32,
    history_count: u32,
    start: u32,
    screen: *const Screen,

    pub fn rowSource(self: View, row: u16) RowSource {
        if (self.rows == 0 or row >= self.rows) return .{ .screen = 0 };
        const src_row = self.start + rowIndex(row);
        std.debug.assert(self.start + rowIndex(self.rows) <= self.history_count + rowIndex(self.rows));
        std.debug.assert(src_row >= self.start);
        std.debug.assert(src_row < self.history_count + rowIndex(self.rows));
        if (src_row < self.history_count) return .{ .history = self.history_count - 1 - src_row };
        return .{ .screen = @intCast(@min(src_row - self.history_count, rowIndex(self.rows -| 1))) };
    }

    pub fn sourceCellInfoAt(self: View, source: RowSource, col: u16) Screen.Cell {
        return switch (source) {
            .history => |recency| self.screen.historyCellAt(recency, col),
            .screen => |screen_row| self.screen.cellInfoAt(screen_row, col),
        };
    }

    pub fn cellInfoAt(self: View, row: u16, col: u16) Screen.Cell {
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

pub const Set = struct {
    const CursorSnapshot = struct {
        row: u16,
        col: u16,
        wrap_pending: bool,
        cursor_visible: bool,
    };

    primary: Screen,
    alternate: Screen,
    primary_selection: SelectionState = SelectionState.init(),
    alternate_selection: SelectionState = SelectionState.init(),
    alt_active: bool = false,
    saved_primary_cursor: ?CursorSnapshot = null,

    pub fn init(primary: Screen, alternate: Screen) Set {
        return .{ .primary = primary, .alternate = alternate };
    }

    pub fn active(self: *Set) *Screen {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    pub fn activeConst(self: *const Set) *const Screen {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    pub fn activeSelection(self: *Set) *SelectionState {
        return if (self.alt_active) &self.alternate_selection else &self.primary_selection;
    }

    pub fn activeSelectionConst(self: *const Set) *const SelectionState {
        return if (self.alt_active) &self.alternate_selection else &self.primary_selection;
    }

    pub fn reset(self: *Set) void {
        self.active().reset();
    }

    pub fn resize(self: *Set, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
        try self.primary.resize(allocator, rows, cols);
        try self.alternate.resize(allocator, rows, cols);
    }

    pub fn enterAlt(self: *Set, clear_alt: bool, save_cursor: bool) void {
        if (save_cursor) {
            self.saved_primary_cursor = .{
                .row = self.primary.cursor_row,
                .col = self.primary.cursor_col,
                .wrap_pending = self.primary.wrap_pending,
                .cursor_visible = self.primary.cursor_visible,
            };
            std.debug.assert(self.saved_primary_cursor != null);
        }
        if (clear_alt) self.alternate.reset();
        self.alt_active = true;
        self.alternate.markAllDirty();
        std.debug.assert(self.alt_active);
    }

    pub fn exitAlt(self: *Set, restore_cursor: bool) void {
        self.alt_active = false;
        if (restore_cursor) {
            if (self.saved_primary_cursor) |saved| {
                self.primary.cursor_row = @min(saved.row, self.primary.rows -| 1);
                self.primary.cursor_col = @min(saved.col, self.primary.cols -| 1);
                self.primary.wrap_pending = saved.wrap_pending;
                self.primary.cursor_visible = saved.cursor_visible;
                std.debug.assert(self.primary.cursor_row < self.primary.rows or self.primary.rows == 0);
                std.debug.assert(self.primary.cursor_col < self.primary.cols or self.primary.cols == 0);
            }
            self.saved_primary_cursor = null;
        }
        self.primary.markAllDirty();
        std.debug.assert(!self.alt_active);
    }

    pub fn deinit(self: *Set, allocator: std.mem.Allocator) void {
        self.primary.deinit(allocator);
        self.alternate.deinit(allocator);
    }
};

pub fn visibleView(screen_state: *const Set, options: Options) View {
    const active = screen_state.activeConst();
    const history_count: u32 = if (screen_state.alt_active) 0 else active.historyCount();
    const offset = @min(options.scrollback_offset, history_count);
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

pub fn peekDirtyRows(screen_state: *const Set) ?Screen.DirtyRows {
    return screen_state.activeConst().peekDirtyRows();
}

pub fn clearDirtyRows(screen_state: *Set) void {
    screen_state.active().clearDirtyRows();
}

pub fn historyRowAt(screen_state: *const Set, history_idx: u32, col: u16) u21 {
    if (screen_state.alt_active) return 0;
    return screen_state.primary.historyRowAt(history_idx, col);
}

pub fn historyCellAt(screen_state: *const Set, history_idx: u32, col: u16) Screen.Cell {
    if (screen_state.alt_active) return Screen.default_cell;
    return screen_state.primary.historyCellAt(history_idx, col);
}

pub fn historyCapacity(screen_state: *const Set) u16 {
    return screen_state.primary.historyCapacity();
}

fn rowIndex(row: u16) u32 {
    return row;
}
