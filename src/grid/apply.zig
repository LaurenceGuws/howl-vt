//! Responsibility: route screen actions to Grid mutation owners.
//! Ownership: terminal grid screen-action dispatch concern.
//! Reason: keep action dispatch separate from screen state fields and lifecycle.

const interpret = @import("../interpret.zig");

const ScreenAction = interpret.ScreenAction;

pub fn applyScreen(self: anytype, event: ScreenAction) void {
    switch (event) {
        .cursor_up => |n| {
            self.wrap_pending = false;
            self.cursor_row = self.cursor_row -| n;
        },
        .cursor_down => |n| {
            self.wrap_pending = false;
            self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
        },
        .cursor_forward => |n| {
            self.wrap_pending = false;
            self.cursor_col = @min(self.cursor_col +| n, self.rightBoundary());
        },
        .cursor_back => |n| {
            self.wrap_pending = false;
            self.cursor_col = @max(self.cursor_col -| n, self.leftBoundary());
        },
        .cursor_next_line => |n| {
            self.wrap_pending = false;
            self.cursor_row = @min(self.cursor_row +| n, self.rows -| 1);
            self.cursor_col = self.lineHomeCol();
        },
        .cursor_prev_line => |n| {
            self.wrap_pending = false;
            self.cursor_row = self.cursor_row -| n;
            self.cursor_col = self.lineHomeCol();
        },
        .cursor_horizontal_absolute => |col| {
            self.wrap_pending = false;
            self.cursor_col = @min(self.resolveAbsoluteCol(col), self.rightBoundary());
        },
        .cursor_vertical_absolute => |row| {
            self.wrap_pending = false;
            self.cursor_row = @min(row, self.rows -| 1);
        },
        .cursor_position => |pos| {
            self.wrap_pending = false;
            self.cursor_row = @min(self.resolveAbsoluteRow(pos.row), self.rows -| 1);
            self.cursor_col = @min(self.resolveAbsoluteCol(pos.col), self.rightBoundary());
        },
        .write_text => |s| self.writeText(s),
        .write_codepoint => |cp| self.writeCell(cp),
        .repeat_preceding => |count| self.repeatPreceding(count),
        .line_feed => {
            self.wrap_pending = false;
            self.setRowWrapped(self.cursor_row, false);
            self.lineFeed();
        },
        .next_line => {
            self.wrap_pending = false;
            self.setRowWrapped(self.cursor_row, false);
            self.cursor_col = 0;
            self.lineFeed();
        },
        .reverse_index => {
            self.wrap_pending = false;
            self.reverseIndex();
        },
        .carriage_return => {
            self.wrap_pending = false;
            self.cursor_col = 0;
        },
        .backspace => {
            self.wrap_pending = false;
            self.cursor_col = self.cursor_col -| 1;
        },
        .horizontal_tab => {
            self.wrap_pending = false;
            self.horizontalTabForward(1);
        },
        .horizontal_tab_forward => |count| {
            self.wrap_pending = false;
            self.horizontalTabForward(count);
        },
        .horizontal_tab_back => |count| {
            self.wrap_pending = false;
            self.horizontalTabBack(count);
        },
        .horizontal_tab_set => self.setTabStop(),
        .tab_clear_current => self.clearCurrentTabStop(),
        .tab_clear_all => self.clearAllTabStops(),
        .cursor_visible => |visible| self.cursor_visible = visible,
        .cursor_style => |cursor_style| self.cursor_style = .{
            .shape = switch (cursor_style.shape) {
                .block => .block,
                .underline => .underline,
                .bar => .bar,
            },
            .blink = cursor_style.blink,
        },
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
        .save_cursor => self.saveCursor(),
        .restore_cursor => self.restoreCursor(),
        .sgr => |sgr| self.applySgr(sgr.params[0..sgr.param_count], sgr.separators[0..sgr.param_count]),
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
        .erase_display => |mode| {
            self.wrap_pending = false;
            self.eraseDisplay(mode);
        },
        .erase_line => |mode| {
            self.wrap_pending = false;
            self.eraseLine(mode);
        },
        .selective_erase_display => |mode| {
            self.wrap_pending = false;
            self.selectiveEraseDisplay(mode);
        },
        .selective_erase_line => |mode| {
            self.wrap_pending = false;
            self.selectiveEraseLine(mode);
        },
        .erase_chars => |count| {
            self.wrap_pending = false;
            self.eraseChars(count);
        },
        .shift_left_columns => |count| {
            self.wrap_pending = false;
            self.shiftColumnsLeft(count);
        },
        .shift_right_columns => |count| {
            self.wrap_pending = false;
            self.shiftColumnsRight(count);
        },
        .character_protection => |enabled| self.current_attrs.protected = enabled,
        .attr_change_extent_rect => |enabled| self.attr_change_extent_rect = enabled,
        .left_right_margin_mode => |enabled| self.setLeftRightMarginMode(enabled),
        .set_left_right_margins => |margins| self.setLeftRightMargins(margins.left, margins.right),
        .reset_default_tab_stops => self.resetDefaultTabStops(),
        .rect_erase => |area| {
            self.wrap_pending = false;
            self.eraseRect(area, false);
        },
        .rect_selective_erase => |area| {
            self.wrap_pending = false;
            self.eraseRect(area, true);
        },
        .rect_fill => |req| {
            self.wrap_pending = false;
            self.fillRect(req.area, req.ch);
        },
        .rect_copy => |req| {
            self.wrap_pending = false;
            self.copyRect(req);
        },
        .rect_attrs_change => |req| {
            self.wrap_pending = false;
            self.changeRectAttrs(req.area, req.attrs.params[0..req.attrs.param_count], req.reverse);
        },
        .insert_columns => |count| {
            self.wrap_pending = false;
            self.insertColumns(count);
        },
        .delete_columns => |count| {
            self.wrap_pending = false;
            self.deleteColumns(count);
        },
    }
}
