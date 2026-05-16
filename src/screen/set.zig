const std = @import("std");
const grid = @import("../grid.zig");

const Grid = grid.Grid;

pub const Set = struct {
    const CursorSnapshot = struct {
        row: u16,
        col: u16,
        wrap_pending: bool,
        cursor_visible: bool,
    };

    primary: Grid,
    alternate: Grid,
    alt_active: bool = false,
    saved_primary_cursor: ?CursorSnapshot = null,

    pub fn init(primary: Grid, alternate: Grid) Set {
        return .{ .primary = primary, .alternate = alternate };
    }

    pub fn active(self: *Set) *Grid {
        return if (self.alt_active) &self.alternate else &self.primary;
    }

    pub fn activeConst(self: *const Set) *const Grid {
        return if (self.alt_active) &self.alternate else &self.primary;
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
