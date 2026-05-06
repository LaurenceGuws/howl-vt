//! Responsibility: own report and query consequences at the vt-core boundary.
//! Ownership: vt-core host-output report surfaces.
//! Reason: keep report encoding and reply state out of the main vt-core facade.

const std = @import("std");
const grid_owner = @import("../grid.zig");
const interpret_owner = @import("../interpret.zig");
const locator_owner = @import("../locator.zig");
const terminal_mode_owner = @import("../terminal_mode.zig");
const terminal_report_owner = @import("../terminal_report.zig");

const ReportAction = interpret_owner.Interpret.ReportAction;
const GridNs = grid_owner.Grid;
const LocatorNs = locator_owner.Locator;
const TerminalModeNs = terminal_mode_owner.TerminalMode;
const TerminalReportNs = terminal_report_owner.TerminalReport;

pub const VtCoreReports = struct {
    pub fn apply(self: anytype, action: ReportAction) void {
        switch (action) {
            .ansi_mode_query => |mode| {
                TerminalReportNs.appendAnsiModeReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], mode, TerminalModeNs.ansiModeState(self, mode));
            },
            .modify_other_keys_query => {
                TerminalReportNs.appendModifyOtherKeysReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], self.modes.modify_other_keys);
            },
            .dec_mode_query => |mode| {
                TerminalReportNs.appendDecModeReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], mode, TerminalModeNs.decModeState(self, mode));
            },
            .dcs_request_status => |request| appendDecrqssReply(self, request),
            .dcs_request_termcap => TerminalReportNs.appendTermcapInvalidReport(self.allocator, &self.host.pending_output),
            .dcs_request_resource => |request| TerminalReportNs.appendResourceInvalidReport(self.allocator, &self.host.pending_output, request),
            .device_status_report => {
                appendPendingOutput(self, "\x1b[0n");
            },
            .dec_device_status_report => |param| {
                LocatorNs.appendDeviceStatusReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], param);
            },
            .cursor_position_report => {
                TerminalReportNs.appendCursorPositionReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], self.renderView());
            },
            .dec_cursor_position_report => {
                TerminalReportNs.appendDecCursorPositionReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], self.renderView());
            },
            .primary_device_attributes => {
                appendPendingOutput(self, "\x1b[?62;22c");
            },
            .secondary_device_attributes => {
                appendPendingOutput(self, "\x1b[>1;10;0c");
            },
            .tertiary_device_attributes => {
                appendPendingOutput(self, "\x1bP!|00000000\x1b\\");
            },
            .xtversion => {
                TerminalReportNs.appendXtVersionReport(self.allocator, &self.host.pending_output);
            },
            .xttitlepos => {
                TerminalReportNs.appendTitleStackPositionReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], 0, 0);
            },
            .xtchecksum => |flags| {
                self.xtchecksum_flags = flags;
            },
            .rect_checksum_request => |req| {
                const checksum = TerminalReportNs.computeRectChecksum(activeState(self), self.xtchecksum_flags, req.page, req.area);
                TerminalReportNs.appendRectChecksumReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], req, checksum);
            },
            .selected_graphic_rendition_report => |area| {
                TerminalReportNs.appendSelectedGraphicRenditionReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], activeState(self), area);
            },
            .presentation_state_report => |kind| {
                switch (kind) {
                    1 => TerminalReportNs.appendCursorInformationReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], self.renderView(), self.apply_flow.deccirCharsetState()),
                    2 => TerminalReportNs.appendTabStopReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], activeState(self)),
                    else => appendPendingOutput(self, "\x1bP0$u\x1b\\"),
                }
            },
            .displayed_extent_report => {
                TerminalReportNs.appendDisplayedExtentReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], self.renderView());
            },
            .terminal_parameters_report => |kind| {
                TerminalReportNs.appendTerminalParametersReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], kind);
            },
            .xtreportcolors => {
                TerminalReportNs.appendColorStackReport(self.allocator, &self.host.pending_output, self.encode.buf[0..], self.kitty.global.color_stack.len);
            },
        }
    }

    fn activeState(self: anytype) *const GridNs.GridModel {
        return self.screen_state.activeConst();
    }

    fn appendPendingOutput(self: anytype, bytes: []const u8) void {
        self.host.pending_output.appendSlice(self.allocator, bytes) catch {};
    }

    fn appendDecrqssReply(self: anytype, request: []const u8) void {
        if (decrqssPayload(self, request)) |payload| {
            self.host.pending_output.appendSlice(self.allocator, "\x1bP1$r") catch return;
            self.host.pending_output.appendSlice(self.allocator, payload) catch return;
            self.host.pending_output.appendSlice(self.allocator, "\x1b\\") catch return;
            return;
        }
        appendPendingOutput(self, "\x1bP0$r\x1b\\");
    }

    fn decrqssPayload(self: anytype, request: []const u8) ?[]const u8 {
        const screen = activeState(self);
        if (std.mem.eql(u8, request, "r")) {
            const bottom = if (screen.rows == 0) @as(u16, 0) else @min(screen.scroll_bottom, screen.rows - 1);
            return std.fmt.bufPrint(self.encode.buf[0..], "{d};{d}r", .{ screen.scroll_top + 1, bottom + 1 }) catch null;
        }
        if (std.mem.eql(u8, request, "s")) {
            const right = if (screen.left_right_margin_mode) screen.right_margin else screen.cols -| 1;
            return std.fmt.bufPrint(self.encode.buf[0..], "{d};{d}s", .{ screen.left_margin + 1, right + 1 }) catch null;
        }
        if (std.mem.eql(u8, request, " q")) {
            const style = screen.cursor_style;
            const value: u8 = switch (style.shape) {
                .block => if (style.blink) 1 else 2,
                .underline => if (style.blink) 3 else 4,
                .bar => if (style.blink) 5 else 6,
            };
            return std.fmt.bufPrint(self.encode.buf[0..], "{d} q", .{value}) catch null;
        }
        if (std.mem.eql(u8, request, "\"q")) {
            const value: u8 = if (screen.current_attrs.protected) 1 else 0;
            return std.fmt.bufPrint(self.encode.buf[0..], "{d}\"q", .{value}) catch null;
        }
        if (std.mem.eql(u8, request, "*x")) {
            const value: u8 = if (screen.attr_change_extent_rect) 2 else 0;
            return std.fmt.bufPrint(self.encode.buf[0..], "{d}*x", .{value}) catch null;
        }
        return null;
    }
};
