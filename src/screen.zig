const std = @import("std");
const parser_mod = @import("parser.zig");
const semantic_event = @import("semantic_event.zig");
const cell = @import("screen/cell.zig");
const color = @import("screen/color.zig");
const cursor = @import("screen/cursor.zig");
const dirty = @import("screen/dirty.zig");
const edit = @import("screen/edit.zig");
const erase = @import("screen/erase.zig");
const screen_apply = @import("screen/apply.zig");
const history_mod = @import("screen/history.zig");
const margins = @import("screen/margins.zig");
const rect = @import("screen/rect.zig");
const resize_mod = @import("screen/resize.zig");
const scroll = @import("screen/scroll.zig");
const style_mod = @import("screen/style.zig");
const tabs = @import("screen/tabs.zig");
const write = @import("screen/write.zig");

const SemanticEvent = semantic_event.SemanticEvent;
const ScreenAction = screen_apply.ScreenAction;
const HistoryLine = history_mod.HistoryLine;

/// Terminal screen state for cursor, cells, margins, and history.
pub const Screen = struct {
    pub const Rgb = color.Rgb;
    pub const Color = color.Color;
    pub const UnderlineStyle = cell.UnderlineStyle;
    pub const CellAttrs = cell.CellAttrs;
    pub const Cell = cell.Cell;
    pub const CursorShape = cursor.CursorShape;
    pub const CursorStyle = cursor.CursorStyle;
    pub const SemanticCursor = cursor.SemanticCursor;
    pub const default_cursor_style = cursor.default_cursor_style;
    pub const default_fg = color.default_fg;
    pub const default_bg = color.default_bg;
    pub const default_underline_color = color.default_underline_color;
    pub const default_cell_attrs = cell.default_cell_attrs;
    pub const default_cell = cell.default_cell;
    pub const isCellContinuation = cell.isCellContinuation;
    pub const DirtyRows = dirty.DirtyRows;
    pub const EraseMode = erase.EraseMode;
    pub const CellPixelSize = struct {
        width: u32,
        height: u32,
    };

    allocator: ?std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor: SemanticCursor,
    wrap_pending: bool,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    left_right_margin_mode: bool,
    left_margin: u16,
    right_margin: u16,
    attr_change_extent_rect: bool,
    view_padding_rows: u16,
    row_origin: u16,
    scroll_top: u16,
    scroll_bottom: u16,
    cells: ?[]Cell,
    row_wraps: ?[]bool,
    history: ?[]Cell,
    history_wraps: ?[]bool,
    history_capacity: u16,
    history_count: u32,
    history_write_idx: u32,
    history_row_base: u32,
    history_lines: std.ArrayListUnmanaged(HistoryLine),
    history_lines_start: u32,
    open_history_line: ?HistoryLine,
    open_history_reuse_slot: ?u32,
    last_graphic_codepoint: ?u21,
    current_attrs: CellAttrs,
    dirty_state: dirty.DirtyState,
    tab_stops: ?[]bool,
    cell_pixel_size: ?CellPixelSize,

    fn cellCount(rows: u16, cols: u16) u32 {
        return @as(u32, rows) * @as(u32, cols);
    }

    fn initBase(
        allocator: ?std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
        cells: ?[]Cell,
        row_wraps: ?[]bool,
        history: ?[]Cell,
        history_wraps: ?[]bool,
        history_capacity: u16,
        dirty_state: dirty.DirtyState,
        tab_stops: ?[]bool,
    ) Screen {
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor = cursor.SemanticCursor.init(cursor_style_default),
            .wrap_pending = false,
            .auto_wrap = true,
            .origin_mode = false,
            .insert_mode = false,
            .left_right_margin_mode = false,
            .left_margin = 0,
            .right_margin = cols -| 1,
            .attr_change_extent_rect = false,
            .view_padding_rows = 0,
            .row_origin = 0,
            .scroll_top = 0,
            .scroll_bottom = rows -| 1,
            .cells = cells,
            .row_wraps = row_wraps,
            .history = history,
            .history_wraps = history_wraps,
            .history_capacity = history_capacity,
            .history_count = 0,
            .history_write_idx = 0,
            .history_row_base = 0,
            .history_lines = .empty,
            .history_lines_start = 0,
            .open_history_line = null,
            .open_history_reuse_slot = null,
            .last_graphic_codepoint = null,
            .current_attrs = default_cell_attrs,
            .dirty_state = dirty_state,
            .tab_stops = tab_stops,
            .cell_pixel_size = null,
        };
    }

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) Screen {
        return initWithDefaultCursorStyle(rows, cols, cursor.default_cursor_style);
    }

    pub fn initWithDefaultCursorStyle(rows: u16, cols: u16, cursor_style_default: CursorStyle) Screen {
        return initBase(null, rows, cols, cursor_style_default, null, null, null, null, 0, .{}, null);
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Screen {
        return initWithCellsAndDefaultCursorStyle(allocator, rows, cols, cursor.default_cursor_style);
    }

    fn initOwnedVisibleGrid(allocator: std.mem.Allocator, rows: u16, cols: u16, cursor_style_default: CursorStyle) !Screen {
        const cell_count = cellCount(rows, cols);
        const cells: ?[]Cell = if (cell_count > 0) blk: {
            const buf = try allocator.alloc(Cell, @intCast(cell_count));
            @memset(buf, default_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_wraps: ?[]bool = if (rows > 0) blk: {
            const buf = try allocator.alloc(bool, rows);
            @memset(buf, false);
            break :blk buf;
        } else null;
        errdefer if (row_wraps) |buf| allocator.free(buf);
        const dirty_cols_start = try dirty.allocDirtyCols(allocator, rows, 0);
        errdefer if (dirty_cols_start) |buf| allocator.free(buf);
        const dirty_cols_end = try dirty.allocDirtyCols(allocator, rows, cols -| 1);
        errdefer if (dirty_cols_end) |buf| allocator.free(buf);
        const tab_stops = try tabs.allocTabStops(allocator, cols);
        errdefer if (tab_stops) |buf| allocator.free(buf);
        return initBase(
            allocator,
            rows,
            cols,
            cursor_style_default,
            cells,
            row_wraps,
            null,
            null,
            0,
            dirty.DirtyState.initFull(rows, dirty_cols_start, dirty_cols_end),
            tab_stops,
        );
    }

    pub fn initWithCellsAndDefaultCursorStyle(allocator: std.mem.Allocator, rows: u16, cols: u16, cursor_style_default: CursorStyle) !Screen {
        return initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Screen {
        return initWithCellsHistoryAndDefaultCursorStyle(allocator, rows, cols, history_capacity, cursor.default_cursor_style);
    }

    pub fn initWithCellsHistoryAndDefaultCursorStyle(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16, cursor_style_default: CursorStyle) !Screen {
        var screen = try initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
        errdefer screen.deinit(allocator);

        const history: ?[]Cell = if (screen.cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(Cell, 0);
            break :blk buf;
        } else null;
        errdefer if (history) |buf| allocator.free(buf);
        const history_wraps: ?[]bool = if (screen.cells != null and history_capacity > 0) blk: {
            const buf = try allocator.alloc(bool, 0);
            break :blk buf;
        } else null;

        screen.history = history;
        screen.history_wraps = history_wraps;
        screen.history_capacity = if (screen.cells != null) history_capacity else 0;
        return screen;
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.row_wraps) |buf| allocator.free(buf);
        self.row_wraps = null;
        self.dirty_state.deinit(allocator);
        if (self.tab_stops) |buf| allocator.free(buf);
        self.tab_stops = null;
        if (self.history) |h| allocator.free(h);
        self.history = null;
        if (self.history_wraps) |buf| allocator.free(buf);
        self.history_wraps = null;
        for (self.history_lines.items) |*line| line.deinit(allocator);
        self.history_lines.deinit(allocator);
        if (self.open_history_line) |*line| line.deinit(allocator);
        self.open_history_line = null;
    }

    /// Replace this screen with a reflowed grid of the requested dimensions.
    ///
    /// Allocation failure leaves this screen unchanged. Successful replacement
    /// preserves logical content and configured cursor defaults, resets margins
    /// to the full new grid, and releases the old owned storage.
    pub fn resize(self: *Screen, allocator: std.mem.Allocator, rows: u16, cols: u16) error{OutOfMemory}!void {
        var replacement = try self.prepareResize(allocator, rows, cols);
        std.mem.swap(Screen, self, &replacement);
        replacement.deinit(allocator);
    }

    /// Build complete reflowed screen state without mutating this screen.
    ///
    /// The caller owns the returned Screen and must call `deinit` unless it
    /// transfers ownership by swapping it into a Screen owner.
    pub fn prepareResize(self: *const Screen, allocator: std.mem.Allocator, rows: u16, cols: u16) error{OutOfMemory}!Screen {
        return resize_mod.prepareResize(self, allocator, rows, cols);
    }

    pub fn storeHistoryRow(self: *Screen, row: u16) void {
        history_mod.storeRow(self, row);
    }

    fn clearHistoryAuthority(self: *Screen, allocator: std.mem.Allocator) void {
        history_mod.clearAuthority(self, allocator);
    }

    /// Reset visible grid state to defaults.
    pub fn reset(self: *Screen) void {
        self.cursor.reset();
        self.wrap_pending = false;
        self.auto_wrap = true;
        self.origin_mode = false;
        self.insert_mode = false;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = self.cols -| 1;
        self.attr_change_extent_rect = false;
        self.view_padding_rows = 0;
        self.row_origin = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.last_graphic_codepoint = null;
        self.current_attrs = default_cell_attrs;
        self.markAllRowsDirty();
        if (self.cells) |c| @memset(c, default_cell);
        if (self.row_wraps) |buf| @memset(buf, false);
        if (self.tab_stops) |stops| tabs.setDefaultTabStops(stops);
    }

    pub fn setDefaultCursorStyle(self: *Screen, style: CursorStyle) void {
        self.cursor.setDefaultStyle(style);
    }

    pub fn peekDirtyRows(self: *const Screen) ?DirtyRows {
        return self.dirty_state.rows;
    }

    pub fn clearDirtyRows(self: *Screen) void {
        self.dirty_state.rows = null;
        if (self.dirty_state.cols_start) |buf| @memset(buf, self.cols);
        if (self.dirty_state.cols_end) |buf| @memset(buf, 0);
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const Screen, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    pub fn cellInfoAt(self: *const Screen, row: u16, col: u16) Cell {
        const c = self.cells orelse return default_cell;
        if (row >= self.rows or col >= self.cols) return default_cell;
        const start = self.rowStart(row);
        return c[@intCast(start + @as(u32, col))];
    }

    pub fn tabStopAt(self: *const Screen, col: u16) bool {
        return tabs.isStop(self, col);
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const Screen, history_idx: u32, col: u16) u21 {
        return @intCast(self.historyCellAt(history_idx, col).codepoint);
    }

    pub fn historyCellAt(self: *const Screen, history_idx: u32, col: u16) Cell {
        const h = self.history orelse return default_cell;
        const bounded_idx: u32 = history_idx;
        if (bounded_idx >= self.history_count or col >= self.cols) return default_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return default_cell;
        return h[@intCast(slot * @as(u32, self.cols) + @as(u32, col))];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const Screen) u32 {
        return self.history_count;
    }

    pub fn historyRowBase(self: *const Screen) u32 {
        return self.history_row_base;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const Screen) u16 {
        return self.history_capacity;
    }

    /// Report whether selection endpoint should be invalidated.
    pub fn shouldInvalidateSelectionEndpoint(self: *const Screen, endpoint_row: i32) bool {
        if (endpoint_row < 0) return true;
        const oldest_row = self.history_row_base;
        const newest_row_exclusive = oldest_row + self.history_count + self.rows;
        if (@as(u32, @intCast(endpoint_row)) < oldest_row) return true;
        if (@as(u32, @intCast(endpoint_row)) >= newest_row_exclusive) return true;
        return false;
    }

    pub fn applyScreen(self: *Screen, event: ScreenAction) void {
        screen_apply.applyScreen(self, event);
    }

    pub const RectBounds = struct {
        top: u16,
        left: u16,
        bottom: u16,
        right: u16,
    };

    pub fn eraseDisplay(self: *Screen, mode: EraseMode, protected: bool) void {
        erase.eraseDisplay(self, mode, protected);
    }

    pub fn setCurrentLinkId(self: *Screen, link_id: u32) void {
        self.current_attrs.link_id = link_id;
    }

    pub fn resolveAbsoluteRow(self: *const Screen, row: u16) u16 {
        return cursor.resolveAbsoluteRow(self, row);
    }

    pub fn resolveAbsoluteCol(self: *const Screen, col: u16) u16 {
        return cursor.resolveAbsoluteCol(self, col);
    }

    pub fn lineHomeCol(self: *const Screen) u16 {
        return cursor.lineHomeCol(self);
    }

    pub fn clearVisibleCells(self: *Screen) void {
        if (self.cells) |cells| @memset(cells, default_cell);
        if (self.row_wraps) |row_wraps| @memset(row_wraps, false);
        self.markAllRowsDirty();
    }

    pub fn resetCursorForAltEntry(self: *Screen) void {
        self.cursor.resetForAltEntry();
        self.wrap_pending = false;
        self.current_attrs = default_cell_attrs;
    }

    pub fn leftBoundary(self: *const Screen) u16 {
        return cursor.leftBoundary(self);
    }

    pub fn rightBoundary(self: *const Screen) u16 {
        return cursor.rightBoundary(self);
    }

    pub fn clearScrollback(self: *Screen) void {
        const allocator = self.allocator orelse return;
        self.history_row_base += self.history_count;
        self.clearHistoryAuthority(allocator);
        self.history_count = 0;
        self.history_write_idx = 0;
        self.markAllRowsDirty();
    }

    pub fn setCellPixelSize(self: *Screen, width: u32, height: u32) void {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        self.cell_pixel_size = .{ .width = width, .height = height };
    }

    pub fn cellPixelSize(self: *const Screen) ?CellPixelSize {
        return self.cell_pixel_size;
    }

    pub fn eraseLine(self: *Screen, mode: EraseMode) void {
        erase.eraseLine(self, mode);
    }

    pub fn eraseChars(self: *Screen, count: u16) void {
        erase.eraseChars(self, count);
    }

    pub fn changeRectAttrs(self: *Screen, area: rect.RectArea, attrs: []const u16, reverse: bool) void {
        rect.changeAttrs(self, area, attrs, reverse);
    }

    pub fn selectiveEraseLine(self: *Screen, mode: EraseMode) void {
        erase.selectiveEraseLine(self, mode);
    }

    pub fn eraseRect(self: *Screen, area: rect.RectArea, selective: bool) void {
        rect.erase(self, area, selective);
    }

    pub fn fillRect(self: *Screen, area: rect.RectArea, ch: u21) void {
        rect.fill(self, area, ch);
    }

    pub fn copyRect(self: *Screen, req: rect.RectCopy) void {
        rect.copy(self, req);
    }

    pub fn insertColumns(self: *Screen, count: u16) void {
        edit.insertColumns(self, count);
    }

    pub fn deleteColumns(self: *Screen, count: u16) void {
        edit.deleteColumns(self, count);
    }

    pub fn shiftColumnsLeft(self: *Screen, count: u16) void {
        edit.shiftColumnsLeft(self, count);
    }

    pub fn shiftColumnsRight(self: *Screen, count: u16) void {
        edit.shiftColumnsRight(self, count);
    }

    pub fn insertChars(self: *Screen, count: u16) void {
        edit.insertChars(self, count);
    }

    pub fn deleteChars(self: *Screen, count: u16) void {
        edit.deleteChars(self, count);
    }

    pub fn writeCell(self: *Screen, cp: u21) void {
        write.writeCell(self, cp);
    }

    pub fn writeText(self: *Screen, text: []const u8) void {
        write.writeText(self, text);
    }

    pub fn repeatPreceding(self: *Screen, count: u16) void {
        write.repeatPreceding(self, count);
    }

    pub fn applySgr(self: *Screen, params: []const i32, separators: parser_mod.CsiSeparatorList) void {
        style_mod.applySgr(self, params, separators);
    }

    pub fn horizontalTabForward(self: *Screen, count: u16) void {
        tabs.horizontalForward(self, count);
    }

    pub fn horizontalTabBack(self: *Screen, count: u16) void {
        tabs.horizontalBack(self, count);
    }

    pub fn setTabStop(self: *Screen) void {
        tabs.setStop(self);
    }

    pub fn clearCurrentTabStop(self: *Screen) void {
        tabs.clearCurrentStop(self);
    }

    pub fn clearAllTabStops(self: *Screen) void {
        tabs.clearAllStops(self);
    }

    pub fn resetDefaultTabStops(self: *Screen) void {
        tabs.resetDefaultStops(self);
    }

    pub fn lineFeed(self: *Screen) void {
        scroll.lineFeed(self);
    }

    pub fn reverseIndex(self: *Screen) void {
        scroll.reverseIndex(self);
    }

    fn scrollUp(self: *Screen) void {
        scroll.scrollUp(self);
    }

    pub fn scrollBottom(self: *const Screen) u16 {
        return if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    }

    pub fn setScrollRegion(self: *Screen, top: u16, bottom: ?u16) void {
        margins.setScrollRegion(self, top, bottom);
    }

    pub fn setLeftRightMarginMode(self: *Screen, enabled: bool) void {
        margins.setLeftRightMode(self, enabled);
    }

    pub fn setLeftRightMargins(self: *Screen, left: u16, right: ?u16) void {
        margins.setLeftRightMargins(self, left, right);
    }

    pub fn insertLines(self: *Screen, count: u16) void {
        scroll.insertLines(self, count);
    }

    pub fn deleteLines(self: *Screen, count: u16) void {
        scroll.deleteLines(self, count);
    }

    pub fn scrollUpRegion(self: *Screen, top: u16, bottom: u16, count: u16) void {
        scroll.scrollUpRegion(self, top, bottom, count);
    }

    pub fn scrollDownRegion(self: *Screen, top: u16, bottom: u16, count: u16) void {
        scroll.scrollDownRegion(self, top, bottom, count);
    }

    pub fn rowStart(self: *const Screen, logical_row: u16) u32 {
        if (self.rows == 0) return 0;
        const physical_row = (self.row_origin + logical_row) % self.rows;
        return @as(u32, physical_row) * @as(u32, self.cols);
    }

    fn rowWrapIndex(self: *const Screen, logical_row: u16) ?u16 {
        _ = self.row_wraps orelse return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (self.row_origin + logical_row) % self.rows;
    }

    pub fn rowWrapped(self: *const Screen, logical_row: u16) bool {
        const wraps = self.row_wraps orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return wraps[@intCast(idx)];
    }

    pub fn setRowWrapped(self: *Screen, logical_row: u16, wrapped: bool) void {
        const wraps = self.row_wraps orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        wraps[@intCast(idx)] = wrapped;
    }

    fn historySlotForLogicalRow(self: *const Screen, logical_row: u32) ?u32 {
        return history_mod.slotForLogicalRow(self, logical_row);
    }

    fn historySlotForRecency(self: *const Screen, history_idx: u32) ?u32 {
        return history_mod.slotForRecency(self, history_idx);
    }

    pub fn historyRowWrapped(self: *const Screen, history_idx: u32) bool {
        return history_mod.rowWrapped(self, history_idx);
    }

    pub fn clearRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) void {
        erase.clearRowRange(self, row, start_col, end_col_exclusive);
    }

    pub fn selectiveClearRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) void {
        erase.selectiveClearRowRange(self, row, start_col, end_col_exclusive);
    }

    pub fn rectBounds(self: *const Screen, area: rect.RectArea) ?RectBounds {
        if (self.rows == 0 or self.cols == 0) return null;
        const row_base: u16 = if (self.origin_mode) self.scroll_top else 0;
        const row_limit: u16 = if (self.origin_mode) self.scrollBottom() else self.rows - 1;
        const row_span = row_limit -| row_base;
        const top = row_base + @min(area.top, row_span);
        const bottom = row_base + @min(area.bottom orelse row_span, row_span);
        const left = @min(area.left, self.cols - 1);
        const right = @min(area.right orelse self.cols - 1, self.cols - 1);
        if (top > bottom or left > right) return null;
        return .{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    pub fn eraseCell(self: *const Screen) Cell {
        return erase.eraseCell(self);
    }

    fn clearFullRow(self: *Screen, row: u16) void {
        erase.clearFullRow(self, row);
    }

    fn copyRow(self: *Screen, dst_row: u16, src_row: u16) void {
        const c = self.cells orelse return;
        const row_len = @as(u32, self.cols);
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        std.mem.copyForwards(Cell, c[@intCast(dst_start)..@intCast(dst_start + row_len)], c[@intCast(src_start)..@intCast(src_start + row_len)]);
        self.setRowWrapped(dst_row, self.rowWrapped(src_row));
    }

    pub fn copyRowRange(self: *Screen, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) void {
        const c = self.cells orelse return;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        const start_col32 = @as(u32, start_col);
        const end_col32 = @as(u32, end_col_exclusive);
        std.mem.copyForwards(Cell, c[@intCast(dst_start + start_col32)..@intCast(dst_start + end_col32)], c[@intCast(src_start + start_col32)..@intCast(src_start + end_col32)]);
        self.setRowWrapped(dst_row, false);
    }

    pub fn markDirtyRow(self: *Screen, row: u16) void {
        dirty.markRow(self, row);
    }

    pub fn markDirtyCols(self: *Screen, row: u16, start_col: u16, end_col: u16) void {
        dirty.markCols(self, row, start_col, end_col);
    }

    pub fn markDirtyRows(self: *Screen, start_row: u16, end_row: u16) void {
        dirty.markRows(self, start_row, end_row);
    }

    pub fn markAllRowsDirty(self: *Screen) void {
        dirty.markAllRows(self);
    }
};
