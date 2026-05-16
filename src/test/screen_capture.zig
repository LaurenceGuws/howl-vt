const std = @import("std");
const selection_mod = @import("../selection.zig");
const screen_mod = @import("../screen.zig");

const Selection = selection_mod;
const Screen = screen_mod.Screen;

pub const Capture = struct {
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    cursor_visible: bool,
    auto_wrap: bool,
    cells: ?[]u21,
    history: ?[]u21,
    history_count: usize,
    history_capacity: u16,
    history_write_idx: usize,
    selection: ?Selection.TerminalSelection,

    pub fn captureFromScreen(allocator: std.mem.Allocator, screen: *const Screen, selection: ?Selection.TerminalSelection) !Capture {
        var capture = Capture{
            .allocator = allocator,
            .rows = screen.rows,
            .cols = screen.cols,
            .cursor_row = screen.cursor_row,
            .cursor_col = screen.cursor_col,
            .cursor_visible = screen.cursor_visible,
            .auto_wrap = screen.auto_wrap,
            .cells = null,
            .history = null,
            .history_count = screen.history_count,
            .history_capacity = screen.history_capacity,
            .history_write_idx = screen.history_write_idx,
            .selection = selection,
        };
        errdefer {
            if (capture.cells) |cells| allocator.free(cells);
            if (capture.history) |history| allocator.free(history);
        }

        if (screen.cells != null) {
            const size = @as(usize, screen.rows) * @as(usize, screen.cols);
            const owned_cells = try allocator.alloc(u21, size);
            var row: u16 = 0;
            while (row < screen.rows) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_cells[@as(usize, row) * @as(usize, screen.cols) + @as(usize, col)] = screen.cellAt(row, col);
                }
            }
            capture.cells = owned_cells;
        }

        if (screen.history_count > 0 and screen.cols > 0) {
            const size = screen.history_count * @as(usize, screen.cols);
            const owned_history = try allocator.alloc(u21, size);
            var row: usize = 0;
            while (row < screen.history_count) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_history[row * @as(usize, screen.cols) + @as(usize, col)] = @intCast(screen.historyCellAt(screen.history_count - 1 - row, col).codepoint);
                }
            }
            capture.history = owned_history;
        }

        return capture;
    }

    pub fn deinit(self: *Capture) void {
        if (self.cells) |cells| self.allocator.free(cells);
        self.cells = null;
        if (self.history) |history| self.allocator.free(history);
        self.history = null;
    }

    pub fn cellAt(self: *const Capture, row: u16, col: u16) u21 {
        const cells = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        return cells[@as(usize, row) * self.cols + col];
    }

    pub fn historyRowAt(self: *const Capture, history_idx: usize, col: u16) u21 {
        const history = self.history orelse return 0;
        if (history_idx >= self.history_count or col >= self.cols) return 0;
        const logical_slot = self.history_count - 1 - history_idx;
        return history[logical_slot * @as(usize, self.cols) + @as(usize, col)];
    }
};
