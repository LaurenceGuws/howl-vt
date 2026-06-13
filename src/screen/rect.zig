const action_vocabulary = @import("../vocabulary.zig");
const style_mod = @import("style.zig");
const cell = @import("cell.zig");

const SemanticEvent = action_vocabulary.SemanticEvent;
const Cell = cell.Cell;

pub fn changeAttrs(self: anytype, area: SemanticEvent.RectArea, attrs: []const u16, reverse: bool) void {
    const c = self.cells orelse return;
    if (attrs.len == 0) return;
    const bounds = self.rectBounds(area) orelse return;
    self.markDirtyRows(bounds.top, bounds.bottom);
    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        const row_start = self.rowStart(row);
        const start_col = if (self.attr_change_extent_rect or row == bounds.top) bounds.left else 0;
        const end_col = if (self.attr_change_extent_rect or row == bounds.bottom) bounds.right else self.cols -| 1;
        var col = start_col;
        while (col <= end_col) : (col += 1) {
            const idx = row_start + @as(u32, col);
            style_mod.applyRectAttrOps(&c[@intCast(idx)].attrs, attrs, reverse);
        }
    }
}

pub fn erase(self: anytype, area: SemanticEvent.RectArea, selective: bool) void {
    const bounds = self.rectBounds(area) orelse return;
    self.markDirtyRows(bounds.top, bounds.bottom);
    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        if (selective) {
            self.selectiveClearRowRange(row, bounds.left, bounds.right + 1);
        } else {
            self.clearRowRange(row, bounds.left, bounds.right + 1);
        }
        if (bounds.left == 0 and bounds.right + 1 == self.cols) self.setRowWrapped(row, false);
    }
}

pub fn fill(self: anytype, area: SemanticEvent.RectArea, ch: u21) void {
    const c = self.cells orelse return;
    const bounds = self.rectBounds(area) orelse return;
    self.markDirtyRows(bounds.top, bounds.bottom);
    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        const start = self.rowStart(row);
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            c[start + col] = .{ .codepoint = ch, .attrs = self.current_attrs };
        }
    }
}

pub fn copy(self: anytype, req: SemanticEvent.RectCopy) void {
    const c = self.cells orelse return;
    _ = c;
    if (req.source_page != 1 or req.dest_page != 1) return;
    const src = self.rectBounds(req.area) orelse return;
    const row_base: u16 = if (self.origin_mode) self.scroll_top else 0;
    const row_limit: u16 = if (self.origin_mode) self.scrollBottom() else self.rows -| 1;
    const dest_top = row_base + @min(req.dest_top, row_limit -| row_base);
    const dest_left = @min(req.dest_left, self.cols -| 1);
    const height: u16 = src.bottom - src.top + 1;
    const width: u16 = src.right - src.left + 1;
    if (dest_top >= self.rows or dest_left >= self.cols) return;
    const copy_height = @min(height, self.rows - dest_top);
    const copy_width = @min(width, self.cols - dest_left);
    if (copy_height == 0 or copy_width == 0) return;

    const allocator = self.allocator orelse return;
    const copy_cell_count = @as(u32, copy_height) * @as(u32, copy_width);
    const temp = allocator.alloc(Cell, @intCast(copy_cell_count)) catch return;
    defer allocator.free(temp);

    var row: u16 = 0;
    while (row < copy_height) : (row += 1) {
        const temp_row_start = @as(u32, row) * @as(u32, copy_width);
        var col: u16 = 0;
        while (col < copy_width) : (col += 1) {
            temp[@intCast(temp_row_start + @as(u32, col))] = self.cellInfoAt(src.top + row, src.left + col);
        }
    }

    self.markDirtyRows(dest_top, dest_top + copy_height - 1);
    row = 0;
    while (row < copy_height) : (row += 1) {
        const dst_start = self.rowStart(dest_top + row);
        const temp_row_start = @as(u32, row) * @as(u32, copy_width);
        var col: u16 = 0;
        while (col < copy_width) : (col += 1) {
            self.cells.?[@intCast(dst_start + @as(u32, dest_left) + @as(u32, col))] = temp[@intCast(temp_row_start + @as(u32, col))];
        }
    }
}
