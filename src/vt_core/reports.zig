//! Responsibility: own report and query consequences at the vt-core boundary.
//! Ownership: vt-core host-output report surfaces.
//! Reason: keep report encoding and reply state out of the main vt-core facade.

const std = @import("std");
const grid_owner = @import("../grid.zig");
const interpret_owner = @import("../interpret.zig");
const locator_owner = @import("../locator.zig");
const terminal_mode_owner = @import("../terminal_mode.zig");
const terminal_report_owner = @import("../terminal_report.zig");

const ReportAction = interpret_owner.ReportAction;
const GridNs = grid_owner;
const LocatorNs = locator_owner;
const TerminalModeNs = terminal_mode_owner;
const TerminalReportNs = terminal_report_owner;

pub const Context = struct {
    allocator: std.mem.Allocator,
    pending_output: *std.ArrayList(u8),
    encode_buf: []u8,
    active_screen: *const GridNs.GridModel,
    render_view: TerminalReportNs.CursorReportView,
    ansi_modes: TerminalModeNs.AnsiView,
    dec_modes: TerminalModeNs.DecView,
    modify_other_keys: i8,
    key_format: [8]u16,
    xtchecksum_flags: *u16,
    deccir_charset: TerminalReportNs.CharsetReportView,
    color_stack_depth: u8,
};

pub fn apply(ctx: Context, action: ReportAction) void {
    switch (action) {
        .ansi_mode_query => |mode| {
            TerminalReportNs.appendAnsiModeReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, mode, TerminalModeNs.ansiModeStateForView(ctx.ansi_modes, mode));
        },
        .modify_other_keys_query => {
            TerminalReportNs.appendModifyOtherKeysReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.modify_other_keys);
        },
        .key_format_query => |resource| {
            if (isKeyFormatResource(resource)) TerminalReportNs.appendKeyFormatReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, resource, ctx.key_format[resource]);
        },
        .dec_mode_query => |mode| {
            TerminalReportNs.appendDecModeReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, mode, TerminalModeNs.decModeStateForView(ctx.dec_modes, mode));
        },
        .dcs_request_status => |request| appendDecrqssReply(ctx, request),
        .dcs_request_termcap => TerminalReportNs.appendTermcapInvalidReport(ctx.allocator, ctx.pending_output),
        .dcs_request_resource => |request| TerminalReportNs.appendResourceInvalidReport(ctx.allocator, ctx.pending_output, request),
        .device_status_report => {
            appendPendingOutput(ctx, "\x1b[0n");
        },
        .dec_device_status_report => |param| {
            LocatorNs.appendDeviceStatusReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, param);
        },
        .cursor_position_report => {
            TerminalReportNs.appendCursorPositionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.render_view);
        },
        .dec_cursor_position_report => {
            TerminalReportNs.appendDecCursorPositionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.render_view);
        },
        .primary_device_attributes => {
            appendPendingOutput(ctx, "\x1b[?62;22c");
        },
        .secondary_device_attributes => {
            appendPendingOutput(ctx, "\x1b[>1;10;0c");
        },
        .tertiary_device_attributes => {
            appendPendingOutput(ctx, "\x1bP!|00000000\x1b\\");
        },
        .xtversion => {
            TerminalReportNs.appendXtVersionReport(ctx.allocator, ctx.pending_output);
        },
        .xttitlepos => {
            TerminalReportNs.appendTitleStackPositionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, 0, 0);
        },
        .xtchecksum => |flags| {
            ctx.xtchecksum_flags.* = flags;
        },
        .rect_checksum_request => |req| {
            const checksum = TerminalReportNs.computeRectChecksum(ctx.active_screen, ctx.xtchecksum_flags.*, req.page, req.area);
            TerminalReportNs.appendRectChecksumReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, .{ .request_id = req.request_id }, checksum);
        },
        .selected_graphic_rendition_report => |area| {
            TerminalReportNs.appendSelectedGraphicRenditionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.active_screen, area);
        },
        .presentation_state_report => |kind| {
            switch (kind) {
                1 => TerminalReportNs.appendCursorInformationReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, .{
                    .cursor = ctx.render_view,
                    .current_attrs = ctx.active_screen.current_attrs,
                    .origin_mode = ctx.active_screen.origin_mode,
                    .wrap_pending = ctx.active_screen.wrap_pending,
                }, ctx.deccir_charset),
                2 => TerminalReportNs.appendTabStopReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.active_screen),
                else => appendPendingOutput(ctx, "\x1bP0$u\x1b\\"),
            }
        },
        .displayed_extent_report => {
            TerminalReportNs.appendDisplayedExtentReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.render_view);
        },
        .terminal_parameters_report => |kind| {
            TerminalReportNs.appendTerminalParametersReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, kind);
        },
        .xtreportcolors => {
            TerminalReportNs.appendColorStackReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.color_stack_depth);
        },
    }
}

fn isKeyFormatResource(resource: u8) bool {
    return resource <= 4 or resource == 6 or resource == 7;
}

fn appendPendingOutput(ctx: Context, bytes: []const u8) void {
    ctx.pending_output.appendSlice(ctx.allocator, bytes) catch {};
}

fn appendDecrqssReply(ctx: Context, request: []const u8) void {
    if (decrqssPayload(ctx, request)) |payload| {
        ctx.pending_output.appendSlice(ctx.allocator, "\x1bP1$r") catch return;
        ctx.pending_output.appendSlice(ctx.allocator, payload) catch return;
        ctx.pending_output.appendSlice(ctx.allocator, "\x1b\\") catch return;
        return;
    }
    appendPendingOutput(ctx, "\x1bP0$r\x1b\\");
}

fn decrqssPayload(ctx: Context, request: []const u8) ?[]const u8 {
    const screen = ctx.active_screen;
    if (std.mem.eql(u8, request, "r")) {
        const bottom = if (screen.rows == 0) @as(u16, 0) else @min(screen.scroll_bottom, screen.rows - 1);
        return std.fmt.bufPrint(ctx.encode_buf, "{d};{d}r", .{ screen.scroll_top + 1, bottom + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, "s")) {
        const right = if (screen.left_right_margin_mode) screen.right_margin else screen.cols -| 1;
        return std.fmt.bufPrint(ctx.encode_buf, "{d};{d}s", .{ screen.left_margin + 1, right + 1 }) catch null;
    }
    if (std.mem.eql(u8, request, " q")) {
        const style = screen.cursor_style;
        const value: u8 = switch (style.shape) {
            .block => if (style.blink) 1 else 2,
            .underline => if (style.blink) 3 else 4,
            .bar => if (style.blink) 5 else 6,
        };
        return std.fmt.bufPrint(ctx.encode_buf, "{d} q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "\"q")) {
        const value: u8 = if (screen.current_attrs.protected) 1 else 0;
        return std.fmt.bufPrint(ctx.encode_buf, "{d}\"q", .{value}) catch null;
    }
    if (std.mem.eql(u8, request, "*x")) {
        const value: u8 = if (screen.attr_change_extent_rect) 2 else 0;
        return std.fmt.bufPrint(ctx.encode_buf, "{d}*x", .{value}) catch null;
    }
    return null;
}
