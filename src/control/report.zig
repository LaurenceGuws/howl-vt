//! Terminal report formatting and checksums.

const std = @import("std");
const screen_mod = @import("../screen.zig");
const action_mod = @import("../action.zig");
const input = @import("../input.zig");
const locator = @import("locator.zig");
const mode_mod = @import("mode.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const LocatorNs = locator;
const ReportAction = action_mod.ReportAction;
const TerminalModeNs = mode_mod;

const xtversion_text = "howl-vt dev";

pub const CursorReportView = struct {
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
};

pub const CharsetReportView = struct {
    gl_index: u8,
    g0_designation: u8,
    g1_designation: u8,
};

pub const CursorInformationView = struct {
    cursor: CursorReportView,
    current_attrs: Screen.CellAttrs,
    origin_mode: bool,
    wrap_pending: bool,
};

pub const RectChecksumRequest = struct {
    request_id: u16,
};

pub fn apply(vt: anytype, report_action: ReportAction) void {
    var scratch: input.Scratch = .{};
    const active = vt.screen_state.activeConst();
    const deccir_charset = vt.parser_queue.deccirCharsetState();
    const ctx = Context{
        .allocator = vt.parser_queue.getAllocator(),
        .pending_output = &vt.host.pending_output,
        .encode_buf = scratch.buf[0..],
        .active_screen = active,
        .render_view = .{
            .rows = active.rows,
            .cols = active.cols,
            .cursor_row = active.cursor_row,
            .cursor_col = active.cursor_col,
        },
        .ansi_modes = .{
            .keyboard_action_mode = vt.modes.keyboard_action_mode,
            .insert_mode = active.insertMode(),
            .send_receive_mode = vt.modes.send_receive_mode,
            .newline_mode = vt.modes.newline_mode,
        },
        .dec_modes = .{
            .application_cursor_keys = vt.modes.application_cursor_keys,
            .application_keypad = vt.modes.application_keypad,
            .auto_wrap = active.auto_wrap,
            .left_right_margin_mode = active.left_right_margin_mode,
            .cursor_visible = active.cursor_visible,
            .alt_active = vt.screen_state.alt_active,
            .mouse_tracking = vt.modes.mouse_tracking,
            .mouse_protocol = vt.modes.mouse_protocol,
            .focus_reporting = vt.modes.focus_reporting,
            .bracketed_paste = vt.modes.bracketed_paste,
            .synchronized_output = vt.modes.synchronized_output,
            .kitty_clipboard = vt.modes.kitty_clipboard,
        },
        .modify_other_keys = vt.modes.modify_other_keys,
        .key_format = vt.modes.key_format,
        .xtchecksum_flags = &vt.xtchecksum_flags,
        .deccir_charset = .{
            .gl_index = deccir_charset.gl_index,
            .g0_designation = deccir_charset.g0_designation,
            .g1_designation = deccir_charset.g1_designation,
        },
        .color_stack_depth = vt.kitty.global.color_stack.len,
    };
    applyWithContext(ctx, report_action);
}

const Context = struct {
    allocator: std.mem.Allocator,
    pending_output: *std.ArrayList(u8),
    encode_buf: []u8,
    active_screen: *const Screen,
    render_view: CursorReportView,
    ansi_modes: TerminalModeNs.AnsiView,
    dec_modes: TerminalModeNs.DecView,
    modify_other_keys: i8,
    key_format: [8]u16,
    xtchecksum_flags: *u16,
    deccir_charset: CharsetReportView,
    color_stack_depth: u8,
};

fn applyWithContext(ctx: Context, report_action: ReportAction) void {
    switch (report_action) {
        .ansi_mode_query => |mode| appendAnsiModeReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, mode, TerminalModeNs.ansiModeStateForView(ctx.ansi_modes, mode)),
        .modify_other_keys_query => appendModifyOtherKeysReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.modify_other_keys),
        .key_format_query => |resource| if (isKeyFormatResource(resource)) appendKeyFormatReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, resource, ctx.key_format[resource]),
        .dec_mode_query => |mode| appendDecModeReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, mode, TerminalModeNs.decModeStateForView(ctx.dec_modes, mode)),
        .dcs_request_status => |request| appendDecrqssReply(ctx, request),
        .dcs_request_termcap => appendTermcapInvalidReport(ctx.allocator, ctx.pending_output),
        .dcs_request_resource => |request| appendResourceInvalidReport(ctx.allocator, ctx.pending_output, request),
        .device_status_report => appendPendingOutput(ctx, "\x1b[0n"),
        .dec_device_status_report => |param| LocatorNs.appendDeviceStatusReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, param),
        .cursor_position_report => appendCursorPositionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.render_view),
        .dec_cursor_position_report => appendDecCursorPositionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.render_view),
        .primary_device_attributes => appendPendingOutput(ctx, "\x1b[?62;22c"),
        .secondary_device_attributes => appendPendingOutput(ctx, "\x1b[>1;10;0c"),
        .tertiary_device_attributes => appendPendingOutput(ctx, "\x1bP!|00000000\x1b\\"),
        .xtversion => appendXtVersionReport(ctx.allocator, ctx.pending_output),
        .xttitlepos => appendTitleStackPositionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, 0, 0),
        .xtchecksum => |flags| ctx.xtchecksum_flags.* = flags,
        .rect_checksum_request => |req| appendRectChecksumReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, .{ .request_id = req.request_id }, computeRectChecksum(ctx.active_screen, ctx.xtchecksum_flags.*, req.page, req.area)),
        .selected_graphic_rendition_report => |area| appendSelectedGraphicRenditionReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.active_screen, area),
        .presentation_state_report => |kind| {
            switch (kind) {
                1 => appendCursorInformationReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, .{
                    .cursor = ctx.render_view,
                    .current_attrs = ctx.active_screen.current_attrs,
                    .origin_mode = ctx.active_screen.origin_mode,
                    .wrap_pending = ctx.active_screen.wrap_pending,
                }, ctx.deccir_charset),
                2 => appendTabStopReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.active_screen),
                else => appendPendingOutput(ctx, "\x1bP0$u\x1b\\"),
            }
        },
        .displayed_extent_report => appendDisplayedExtentReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.render_view),
        .parameters_report => |kind| appendTerminalParametersReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, kind),
        .xtreportcolors => appendColorStackReport(ctx.allocator, ctx.pending_output, ctx.encode_buf, ctx.color_stack_depth),
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

pub fn appendModifyOtherKeysReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, value: i8) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[>4;{d}m", .{value}) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendKeyFormatReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, resource: u8, value: u16) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[>{d};{d}f", .{ resource, value }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendXtVersionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8)) void {
    output.appendSlice(allocator, "\x1bP>|" ++ xtversion_text ++ "\x1b\\") catch {};
}

pub fn appendTermcapInvalidReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8)) void {
    output.appendSlice(allocator, "\x1bP0+r\x1b\\") catch {};
}

pub fn appendResourceInvalidReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), request: []const u8) void {
    output.appendSlice(allocator, "\x1bP0+R") catch return;
    output.appendSlice(allocator, request) catch return;
    output.appendSlice(allocator, "\x1b\\") catch {};
}

pub fn appendTitleStackPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, current: u16, max: u16) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d}#S", .{ current, max }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendCursorPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: CursorReportView) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d}R", .{ render_view.cursor_row + 1, render_view.cursor_col + 1 }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendDecCursorPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: CursorReportView) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[?{d};{d}R", .{ render_view.cursor_row + 1, render_view.cursor_col + 1 }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendDecModeReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, mode: u16, state: u8) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[?{d};{d}$y", .{ mode, state }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendAnsiModeReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, mode: u16, state: u8) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d}$y", .{ mode, state }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendColorStackReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, depth: u8) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d}#Q", .{ depth, depth }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendCursorInformationReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, view: CursorInformationView, charset: CharsetReportView) void {
    const attrs = view.current_attrs;

    var srend_bits: u8 = 0;
    if (attrs.bold) srend_bits |= 1;
    if (attrs.underline) srend_bits |= 2;
    if (attrs.blink) srend_bits |= 4;
    if (attrs.reverse) srend_bits |= 8;
    const srend: u8 = 0x40 + srend_bits;

    const satt: u8 = if (attrs.protected) 0x41 else 0x40;

    var sflag_bits: u8 = 0;
    if (view.origin_mode) sflag_bits |= 1;
    if (view.wrap_pending) sflag_bits |= 8;
    const sflag: u8 = 0x40 + sflag_bits;

    const text = std.fmt.bufPrint(
        encode_buf,
        "\x1bP1$u{d};{d};1;{c};{c};{c};{d};2;@;{c}{c}BB\x1b\\",
        .{
            view.cursor.cursor_row + 1,
            view.cursor.cursor_col + 1,
            srend,
            satt,
            sflag,
            charset.gl_index,
            charset.g0_designation,
            charset.g1_designation,
        },
    ) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendTabStopReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, screen: *const Grid) void {
    output.appendSlice(allocator, "\x1bP2$u") catch return;
    var first = true;
    var col: u16 = 0;
    while (col < screen.cols) : (col += 1) {
        if (!screen.tabStopAt(col)) continue;
        if (!first) output.appendSlice(allocator, "/") catch return;
        first = false;
        const text = std.fmt.bufPrint(encode_buf, "{d}", .{col + 1}) catch return;
        output.appendSlice(allocator, text) catch return;
    }
    output.appendSlice(allocator, "\x1b\\") catch {};
}

pub fn appendDisplayedExtentReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: CursorReportView) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d};1;1;1\"w", .{ render_view.rows, render_view.cols }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendTerminalParametersReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, kind: u16) void {
    if (kind > 1) return;
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};1;1;128;128;1;0x", .{kind + 2}) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendRectChecksumReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, req: RectChecksumRequest, checksum: u16) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1bP{d}!~{X:0>4}\x1b\\", .{ req.request_id, checksum }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn appendSelectedGraphicRenditionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, screen: *const Grid, area: action_mod.SemanticEvent.RectArea) void {
    const common = commonAttrsForRect(screen, area) orelse {
        output.appendSlice(allocator, "\x1b[0m") catch {};
        return;
    };

    output.appendSlice(allocator, "\x1b[") catch return;
    var first = true;
    appendSgrParam(allocator, output, &first, "0");
    if (common.bold) appendSgrParam(allocator, output, &first, "1");
    if (common.underline) appendSgrParam(allocator, output, &first, underlineStyleParam(common.underline_style));
    if (common.blink) appendSgrParam(allocator, output, &first, "5");
    if (common.reverse) appendSgrParam(allocator, output, &first, "7");
    appendColorParam(allocator, output, encode_buf, &first, true, common.fg, Grid.default_cell_attrs.fg);
    appendColorParam(allocator, output, encode_buf, &first, false, common.bg, Grid.default_cell_attrs.bg);
    if (common.underline and !colorEq(common.underline_color, Grid.default_underline_color)) {
        appendExtendedColorParam(allocator, output, encode_buf, &first, 58, common.underline_color);
    }
    output.appendSlice(allocator, "m") catch {};
}

pub fn computeRectChecksum(screen: *const Grid, xtchecksum_flags: u16, page: u16, area: action_mod.SemanticEvent.RectArea) u16 {
    if (page != 1) return 0;
    const bounds = screen.rectBoundsForReport(area) orelse return 0;
    var sum: u16 = 0;
    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            const cell = screen.cellInfoAt(row, col);
            const is_blank = cell.codepoint == 0;
            if (is_blank and (xtchecksum_flags & (1 << 2)) == 0) continue;
            var cp: u32 = cell.codepoint;
            if ((xtchecksum_flags & (1 << 4)) == 0) cp &= 0xff;
            sum +%= @intCast(cp & 0xffff);
            if ((xtchecksum_flags & (1 << 1)) == 0) {
                sum +%= if (cell.attrs.bold) 1 else 0;
                sum +%= if (cell.attrs.underline) 2 else 0;
                sum +%= if (cell.attrs.blink) 4 else 0;
                sum +%= if (cell.attrs.reverse) 8 else 0;
            }
        }
    }
    if ((xtchecksum_flags & (1 << 0)) == 0) sum = ~sum;
    return sum;
}

const CommonAttrs = struct {
    bold: bool,
    underline: bool,
    underline_style: Grid.UnderlineStyle,
    underline_color: Grid.Color,
    blink: bool,
    reverse: bool,
    fg: Grid.Color,
    bg: Grid.Color,
};

fn commonAttrsForRect(screen: *const Grid, area: action_mod.SemanticEvent.RectArea) ?CommonAttrs {
    const bounds = screen.rectBoundsForReport(area) orelse return null;
    const first_cell = screen.cellInfoAt(bounds.top, bounds.left);
    var common = CommonAttrs{
        .bold = first_cell.attrs.bold,
        .underline = first_cell.attrs.underline,
        .underline_style = first_cell.attrs.underline_style,
        .underline_color = first_cell.attrs.underline_color,
        .blink = first_cell.attrs.blink,
        .reverse = first_cell.attrs.reverse,
        .fg = first_cell.attrs.fg,
        .bg = first_cell.attrs.bg,
    };

    var row = bounds.top;
    while (row <= bounds.bottom) : (row += 1) {
        var col = bounds.left;
        while (col <= bounds.right) : (col += 1) {
            const attrs = screen.cellInfoAt(row, col).attrs;
            if (attrs.bold != common.bold) common.bold = false;
            if (attrs.underline != common.underline) common.underline = false;
            if (attrs.blink != common.blink) common.blink = false;
            if (attrs.reverse != common.reverse) common.reverse = false;
            if (attrs.underline_style != common.underline_style) common.underline_style = .straight;
            if (!colorEq(attrs.fg, common.fg)) common.fg = Grid.default_cell_attrs.fg;
            if (!colorEq(attrs.bg, common.bg)) common.bg = Grid.default_cell_attrs.bg;
            if (!colorEq(attrs.underline_color, common.underline_color)) common.underline_color = Grid.default_underline_color;
        }
    }
    if (!common.underline) {
        common.underline_style = .straight;
        common.underline_color = Grid.default_underline_color;
    }
    return common;
}

fn appendSgrParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), first: *bool, text: []const u8) void {
    if (!first.*) output.appendSlice(allocator, ";") catch return;
    first.* = false;
    output.appendSlice(allocator, text) catch {};
}

fn underlineStyleParam(style: Grid.UnderlineStyle) []const u8 {
    return switch (style) {
        .straight => "4",
        .double => "4:2",
        .curly => "4:3",
        .dotted => "4:4",
        .dashed => "4:5",
    };
}

fn appendColorParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, first: *bool, is_fg: bool, color: Grid.Color, default_color: Grid.Color) void {
    if (colorEq(color, default_color)) return;
    if (ansi16Index(color)) |idx| {
        const code: u16 = if (is_fg)
            (if (idx < 8) 30 + idx else 90 + (idx - 8))
        else
            (if (idx < 8) 40 + idx else 100 + (idx - 8));
        const text = std.fmt.bufPrint(encode_buf, "{d}", .{code}) catch return;
        appendSgrParam(allocator, output, first, text);
        return;
    }
    appendExtendedColorParam(allocator, output, encode_buf, first, if (is_fg) 38 else 48, color);
}

fn appendExtendedColorParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, first: *bool, prefix: u8, color: Grid.Color) void {
    if (indexed256Index(color)) |idx| {
        const text = std.fmt.bufPrint(encode_buf, "{d};5;{d}", .{ prefix, idx }) catch return;
        appendSgrParam(allocator, output, first, text);
        return;
    }
    const text = std.fmt.bufPrint(encode_buf, "{d};2;{d};{d};{d}", .{ prefix, color.r, color.g, color.b }) catch return;
    appendSgrParam(allocator, output, first, text);
}

fn ansi16Index(color: Grid.Color) ?u8 {
    var idx: u8 = 0;
    while (idx < 16) : (idx += 1) {
        if (colorEq(color, ansi16Color(idx))) return idx;
    }
    return null;
}

fn indexed256Index(color: Grid.Color) ?u8 {
    var idx: u16 = 0;
    while (idx < 256) : (idx += 1) {
        if (colorEq(color, indexed256Color(@intCast(idx)))) return @intCast(idx);
    }
    return null;
}

fn colorEq(a: Grid.Color, b: Grid.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

fn ansi16Color(idx: u8) Grid.Color {
    return switch (idx) {
        0 => .{ .r = 0, .g = 0, .b = 0 },
        1 => .{ .r = 170, .g = 0, .b = 0 },
        2 => .{ .r = 0, .g = 170, .b = 0 },
        3 => .{ .r = 170, .g = 85, .b = 0 },
        4 => .{ .r = 0, .g = 0, .b = 170 },
        5 => .{ .r = 170, .g = 0, .b = 170 },
        6 => .{ .r = 0, .g = 170, .b = 170 },
        7 => .{ .r = 170, .g = 170, .b = 170 },
        8 => .{ .r = 85, .g = 85, .b = 85 },
        9 => .{ .r = 255, .g = 85, .b = 85 },
        10 => .{ .r = 85, .g = 255, .b = 85 },
        11 => .{ .r = 255, .g = 255, .b = 85 },
        12 => .{ .r = 85, .g = 85, .b = 255 },
        13 => .{ .r = 255, .g = 85, .b = 255 },
        14 => .{ .r = 85, .g = 255, .b = 255 },
        15 => .{ .r = 255, .g = 255, .b = 255 },
        else => Grid.default_fg,
    };
}

fn indexed256Color(idx: u8) Grid.Color {
    if (idx < 16) return ansi16Color(idx);
    if (idx < 232) {
        const n: u32 = idx - 16;
        return .{
            .r = @intCast((n / 36) * 51),
            .g = @intCast(((n / 6) % 6) * 51),
            .b = @intCast((n % 6) * 51),
        };
    }
    const gray: u8 = 8 + (idx - 232) * 10;
    return .{ .r = gray, .g = gray, .b = gray };
}
