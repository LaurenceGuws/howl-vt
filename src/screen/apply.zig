const csi_params = @import("../csi_params.zig");
const cursor = @import("cursor.zig");
const erase = @import("erase.zig");
const rect = @import("rect.zig");
const screen_color = @import("color.zig");

pub const ScreenAction = union(enum) {
    cursor_up: u16,
    cursor_down: u16,
    cursor_forward: u16,
    cursor_back: u16,
    cursor_next_line: u16,
    cursor_prev_line: u16,
    cursor_horizontal_absolute: u16,
    cursor_vertical_absolute: u16,
    cursor_position: struct { row: u16, col: u16 },
    write_text: []const u8,
    write_codepoint: u21,
    repeat_preceding: u16,
    line_feed,
    next_line,
    reverse_index,
    carriage_return,
    backspace,
    horizontal_tab,
    horizontal_tab_forward: u16,
    horizontal_tab_back: u16,
    horizontal_tab_set,
    tab_clear_current,
    tab_clear_all,
    cursor_visible: bool,
    cursor_style: cursor.CursorStyleCommand,
    cursor_color: ?screen_color.Rgb,
    cursor_text_color: ?screen_color.Rgb,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    sgr: struct {
        params: []const i32,
        separators: csi_params.CsiSeparatorList,
    },
    insert_lines: u16,
    delete_lines: u16,
    insert_chars: u16,
    delete_chars: u16,
    scroll_up_lines: u16,
    scroll_down_lines: u16,
    set_scroll_region: struct { top: u16, bottom: ?u16 },
    reset_screen,
    erase_display_below: bool,
    erase_display_above: bool,
    erase_display_complete: bool,
    erase_display_scrollback: bool,
    erase_display_scroll_complete: bool,
    erase_line: erase.EraseMode,
    selective_erase_line: erase.EraseMode,
    erase_chars: u16,
    shift_left_columns: u16,
    shift_right_columns: u16,
    character_protection: bool,
    rect_erase: rect.RectArea,
    rect_selective_erase: rect.RectArea,
    rect_fill: struct { area: rect.RectArea, ch: u21 },
    rect_copy: rect.RectCopy,
    rect_attrs_change: struct { area: rect.RectArea, attrs: csi_params.AttrParams, reverse: bool },
    insert_columns: u16,
    delete_columns: u16,
    attr_change_extent_rect: bool,
    left_right_margin_mode: bool,
    set_left_right_margins: struct { left: u16, right: ?u16 },
    reset_default_tab_stops,
};

pub fn applyScreen(self: anytype, event: ScreenAction) void {
    switch (event) {
        .cursor_up,
        .cursor_down,
        .cursor_forward,
        .cursor_back,
        .cursor_next_line,
        .cursor_prev_line,
        .cursor_horizontal_absolute,
        .cursor_vertical_absolute,
        .cursor_position,
        => applyCursorMove(self, event),
        .write_text,
        .write_codepoint,
        .repeat_preceding,
        .sgr,
        => applyRetainedState(self, event),
        .line_feed,
        .next_line,
        .reverse_index,
        .carriage_return,
        .backspace,
        .horizontal_tab,
        .horizontal_tab_forward,
        .horizontal_tab_back,
        => applyFlowMove(self, event),
        .horizontal_tab_set,
        .tab_clear_current,
        .tab_clear_all,
        .reset_default_tab_stops,
        => applyTabState(self, event),
        .cursor_visible,
        .cursor_style,
        .cursor_color,
        .cursor_text_color,
        .auto_wrap,
        .origin_mode,
        .insert_mode,
        .character_protection,
        .attr_change_extent_rect,
        .left_right_margin_mode,
        .set_left_right_margins,
        => applyScreenState(self, event),
        .insert_lines,
        .delete_lines,
        .insert_chars,
        .delete_chars,
        .scroll_up_lines,
        .scroll_down_lines,
        .set_scroll_region,
        .reset_screen,
        => applyLineEdit(self, event),
        .erase_display_below,
        .erase_display_above,
        .erase_display_complete,
        .erase_display_scrollback,
        .erase_display_scroll_complete,
        .erase_line,
        .selective_erase_line,
        .erase_chars,
        .shift_left_columns,
        .shift_right_columns,
        .insert_columns,
        .delete_columns,
        => applyGridEdit(self, event),
        .rect_erase,
        .rect_selective_erase,
        .rect_fill,
        .rect_copy,
        .rect_attrs_change,
        => applyRectEdit(self, event),
    }
}

fn applyCursorMove(self: anytype, event: ScreenAction) void {
    self.wrap_pending = false;
    switch (event) {
        .cursor_up => |n| self.cursor.setRowByClient(self.cursor.row -| n),
        .cursor_down => |n| self.cursor.setRowByClient(@min(self.cursor.row +| n, self.rows -| 1)),
        .cursor_forward => |n| self.cursor.setColByClient(@min(self.cursor.col +| n, self.rightBoundary())),
        .cursor_back => |n| self.cursor.setColByClient(@max(self.cursor.col -| n, self.leftBoundary())),
        .cursor_next_line => |n| {
            self.cursor.setPositionByClient(@min(self.cursor.row +| n, self.rows -| 1), self.lineHomeCol());
        },
        .cursor_prev_line => |n| {
            self.cursor.setPositionByClient(self.cursor.row -| n, self.lineHomeCol());
        },
        .cursor_horizontal_absolute => |col| {
            self.cursor.setColByClient(@min(self.resolveAbsoluteCol(col), self.rightBoundary()));
        },
        .cursor_vertical_absolute => |row| self.cursor.setRowByClient(@min(row, self.rows -| 1)),
        .cursor_position => |pos| {
            self.cursor.setPositionByClient(@min(self.resolveAbsoluteRow(pos.row), self.rows -| 1), @min(self.resolveAbsoluteCol(pos.col), self.rightBoundary()));
        },
        else => unreachable,
    }
}

fn applyRetainedState(self: anytype, event: ScreenAction) void {
    switch (event) {
        .write_text => |s| self.writeText(s),
        .write_codepoint => |cp| self.writeCell(cp),
        .repeat_preceding => |count| self.repeatPreceding(count),
        .sgr => |sgr| self.applySgr(sgr.params, sgr.separators),
        else => unreachable,
    }
}

fn applyFlowMove(self: anytype, event: ScreenAction) void {
    self.wrap_pending = false;
    switch (event) {
        .line_feed => {
            self.setRowWrapped(self.cursor.row, false);
            self.lineFeed();
        },
        .next_line => {
            self.setRowWrapped(self.cursor.row, false);
            self.cursor.setColByClient(0);
            self.lineFeed();
        },
        .reverse_index => self.reverseIndex(),
        .carriage_return => self.cursor.setColByClient(0),
        .backspace => self.cursor.setColByClient(self.cursor.col -| 1),
        .horizontal_tab => self.horizontalTabForward(1),
        .horizontal_tab_forward => |count| self.horizontalTabForward(count),
        .horizontal_tab_back => |count| self.horizontalTabBack(count),
        else => unreachable,
    }
}

fn applyTabState(self: anytype, event: ScreenAction) void {
    switch (event) {
        .horizontal_tab_set => self.setTabStop(),
        .tab_clear_current => self.clearCurrentTabStop(),
        .tab_clear_all => self.clearAllTabStops(),
        .reset_default_tab_stops => self.resetDefaultTabStops(),
        else => unreachable,
    }
}

fn applyScreenState(self: anytype, event: ScreenAction) void {
    switch (event) {
        .cursor_visible => |visible| self.cursor.visible = visible,
        .cursor_style => |cursor_style| switch (cursor_style) {
            .restore_default => self.cursor.restoreDefaultStyle(),
            .program_override => |style| self.cursor.setProgramStyle(style),
        },
        .cursor_color => |value| self.cursor.cursor_color = value,
        .cursor_text_color => |value| self.cursor.cursor_text_color = value,
        .auto_wrap => |enabled| {
            self.auto_wrap = enabled;
            if (!enabled) self.wrap_pending = false;
        },
        .origin_mode => |enabled| {
            self.origin_mode = enabled;
            self.wrap_pending = false;
            self.cursor.setPositionByClient(if (enabled) self.scroll_top else 0, self.lineHomeCol());
        },
        .insert_mode => |enabled| self.insert_mode = enabled,
        .character_protection => |enabled| self.current_attrs.protected = enabled,
        .attr_change_extent_rect => |enabled| self.attr_change_extent_rect = enabled,
        .left_right_margin_mode => |enabled| self.setLeftRightMarginMode(enabled),
        .set_left_right_margins => |margins| self.setLeftRightMargins(margins.left, margins.right),
        else => unreachable,
    }
}

fn applyLineEdit(self: anytype, event: ScreenAction) void {
    switch (event) {
        .insert_lines => |count| {
            self.wrap_pending = false;
            self.insertLines(count);
        },
        .delete_lines => |count| {
            self.wrap_pending = false;
            self.deleteLines(count);
        },
        .insert_chars => |count| {
            self.wrap_pending = false;
            self.insertChars(count);
        },
        .delete_chars => |count| {
            self.wrap_pending = false;
            self.deleteChars(count);
        },
        .scroll_up_lines => |count| {
            self.wrap_pending = false;
            self.scrollUpRegion(self.scroll_top, self.scrollBottom(), count);
        },
        .scroll_down_lines => |count| {
            self.wrap_pending = false;
            self.scrollDownRegion(self.scroll_top, self.scrollBottom(), count);
        },
        .set_scroll_region => |region| {
            self.wrap_pending = false;
            self.setScrollRegion(region.top, region.bottom);
        },
        .reset_screen => self.reset(),
        else => unreachable,
    }
}

fn applyGridEdit(self: anytype, event: ScreenAction) void {
    self.wrap_pending = false;
    switch (event) {
        .erase_display_below => |protected| self.eraseDisplay(.cursor_to_end, protected),
        .erase_display_above => |protected| self.eraseDisplay(.start_to_cursor, protected),
        .erase_display_complete => |protected| self.eraseDisplay(.all, protected),
        .erase_display_scrollback => |protected| self.eraseDisplay(.scrollback, protected),
        .erase_display_scroll_complete => |protected| self.eraseDisplay(.all, protected),
        .erase_line => |mode| self.eraseLine(mode),
        .selective_erase_line => |mode| self.selectiveEraseLine(mode),
        .erase_chars => |count| self.eraseChars(count),
        .shift_left_columns => |count| self.shiftColumnsLeft(count),
        .shift_right_columns => |count| self.shiftColumnsRight(count),
        .insert_columns => |count| self.insertColumns(count),
        .delete_columns => |count| self.deleteColumns(count),
        else => unreachable,
    }
}

fn applyRectEdit(self: anytype, event: ScreenAction) void {
    self.wrap_pending = false;
    switch (event) {
        .rect_erase => |area| self.eraseRect(area, false),
        .rect_selective_erase => |area| self.eraseRect(area, true),
        .rect_fill => |req| self.fillRect(req.area, req.ch),
        .rect_copy => |req| self.copyRect(req),
        .rect_attrs_change => |req| {
            self.changeRectAttrs(req.area, req.attrs.params[0..req.attrs.param_count], req.reverse);
        },
        else => unreachable,
    }
}
