const action_vocabulary = @import("../../action/vocabulary.zig");

const ScreenAction = action_vocabulary.ScreenAction;

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
        .save_cursor,
        .restore_cursor,
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
        .erase_display,
        .erase_line,
        .selective_erase_display,
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
        .cursor_up => |n| self.cursor_row = self.cursor_row -| n,
        .cursor_down => |n| self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1),
        .cursor_forward => |n| self.cursor_col = @min(self.cursor_col +| n, self.rightBoundary()),
        .cursor_back => |n| self.cursor_col = @max(self.cursor_col -| n, self.leftBoundary()),
        .cursor_next_line => |n| {
            self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
            self.cursor_col = self.lineHomeCol();
        },
        .cursor_prev_line => |n| {
            self.cursor_row = self.cursor_row -| n;
            self.cursor_col = self.lineHomeCol();
        },
        .cursor_horizontal_absolute => |col| {
            self.cursor_col = @min(self.resolveAbsoluteCol(col), self.rightBoundary());
        },
        .cursor_vertical_absolute => |row| self.cursor_row = @min(row, self.rows -| 1),
        .cursor_position => |pos| {
            self.cursor_row = @min(self.resolveAbsoluteRow(pos.row), self.rows -| 1);
            self.cursor_col = @min(self.resolveAbsoluteCol(pos.col), self.rightBoundary());
        },
        else => unreachable,
    }
}

fn applyRetainedState(self: anytype, event: ScreenAction) void {
    switch (event) {
        .write_text => |s| self.writeText(s),
        .write_codepoint => |cp| self.writeCell(cp),
        .repeat_preceding => |count| self.repeatPreceding(count),
        .save_cursor => self.saveCursor(),
        .restore_cursor => self.restoreCursor(),
        .sgr => |sgr| self.applySgr(sgr.params, sgr.separators),
        else => unreachable,
    }
}

fn applyFlowMove(self: anytype, event: ScreenAction) void {
    self.wrap_pending = false;
    switch (event) {
        .line_feed => {
            self.setRowWrapped(self.cursor_row, false);
            self.lineFeed();
        },
        .next_line => {
            self.setRowWrapped(self.cursor_row, false);
            self.cursor_col = 0;
            self.lineFeed();
        },
        .reverse_index => self.reverseIndex(),
        .carriage_return => self.cursor_col = 0,
        .backspace => self.cursor_col = self.cursor_col -| 1,
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
        .cursor_visible => |visible| self.cursor_visible = visible,
        .cursor_style => |cursor_style| self.cursor_style = cursor_style,
        .auto_wrap => |enabled| {
            self.auto_wrap = enabled;
            if (!enabled) self.wrap_pending = false;
        },
        .origin_mode => |enabled| {
            self.origin_mode = enabled;
            self.wrap_pending = false;
            self.cursor_row = if (enabled) self.scroll_top else 0;
            self.cursor_col = self.lineHomeCol();
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
        .erase_display => |mode| self.eraseDisplay(mode),
        .erase_line => |mode| self.eraseLine(mode),
        .selective_erase_display => |mode| self.selectiveEraseDisplay(mode),
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
