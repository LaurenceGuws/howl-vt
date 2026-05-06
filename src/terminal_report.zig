//! Responsibility: own terminal host-output report formatting and checksum helpers.
//! Ownership: terminal report protocol domain owner.
//! Reason: keep host-output-facing report generation out of the vt-core facade.

const std = @import("std");
const grid_types = @import("grid/types.zig");
const interpret_owner = @import("interpret.zig");

const GridTypes = grid_types;
const Interpret = interpret_owner.Interpret;

pub const TerminalReport = struct {
    const xtversion_text = "howl-vt-core dev";

    pub fn appendModifyOtherKeysReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, value: i8) void {
        const text = std.fmt.bufPrint(encode_buf, "\x1b[>4;{d}m", .{value}) catch return;
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

    pub fn appendCursorPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: anytype) void {
        const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d}R", .{ render_view.cursor_row + 1, render_view.cursor_col + 1 }) catch return;
        output.appendSlice(allocator, text) catch {};
    }

    pub fn appendDecCursorPositionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: anytype) void {
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

    pub fn appendCursorInformationReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: anytype, charset: anytype) void {
        const attrs = render_view.screen.current_attrs;

        var srend_bits: u8 = 0;
        if (attrs.bold) srend_bits |= 1;
        if (attrs.underline) srend_bits |= 2;
        if (attrs.blink) srend_bits |= 4;
        if (attrs.reverse) srend_bits |= 8;
        const srend: u8 = 0x40 + srend_bits;

        const satt: u8 = if (attrs.protected) 0x41 else 0x40;

        var sflag_bits: u8 = 0;
        if (render_view.screen.origin_mode) sflag_bits |= 1;
        if (render_view.screen.wrap_pending) sflag_bits |= 8;
        const sflag: u8 = 0x40 + sflag_bits;

        const text = std.fmt.bufPrint(
            encode_buf,
            "\x1bP1$u{d};{d};1;{c};{c};{c};{d};2;@;{c}{c}BB\x1b\\",
            .{
                render_view.cursor_row + 1,
                render_view.cursor_col + 1,
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

    pub fn appendTabStopReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, screen: anytype) void {
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

    pub fn appendDisplayedExtentReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, render_view: anytype) void {
        const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d};1;1;1\"w", .{ render_view.rows, render_view.cols }) catch return;
        output.appendSlice(allocator, text) catch {};
    }

    pub fn appendTerminalParametersReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, kind: u16) void {
        if (kind > 1) return;
        const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};1;1;128;128;1;0x", .{kind + 2}) catch return;
        output.appendSlice(allocator, text) catch {};
    }

    pub fn appendRectChecksumReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, req: anytype, checksum: u16) void {
        const text = std.fmt.bufPrint(encode_buf, "\x1bP{d}!~{X:0>4}\x1b\\", .{ req.request_id, checksum }) catch return;
        output.appendSlice(allocator, text) catch {};
    }

    pub fn appendSelectedGraphicRenditionReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, screen: anytype, area: Interpret.SemanticEvent.RectArea) void {
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
        appendColorParam(allocator, output, encode_buf, &first, true, common.fg, GridTypes.default_cell_attrs.fg);
        appendColorParam(allocator, output, encode_buf, &first, false, common.bg, GridTypes.default_cell_attrs.bg);
        if (common.underline and !colorEq(common.underline_color, GridTypes.default_underline_color)) {
            appendExtendedColorParam(allocator, output, encode_buf, &first, 58, common.underline_color);
        }
        output.appendSlice(allocator, "m") catch {};
    }

    pub fn computeRectChecksum(screen: anytype, xtchecksum_flags: u16, page: u16, area: Interpret.SemanticEvent.RectArea) u16 {
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
        underline_style: GridTypes.UnderlineStyle,
        underline_color: GridTypes.Color,
        blink: bool,
        reverse: bool,
        fg: GridTypes.Color,
        bg: GridTypes.Color,
    };

    fn commonAttrsForRect(screen: anytype, area: Interpret.SemanticEvent.RectArea) ?CommonAttrs {
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
                if (!colorEq(attrs.fg, common.fg)) common.fg = GridTypes.default_cell_attrs.fg;
                if (!colorEq(attrs.bg, common.bg)) common.bg = GridTypes.default_cell_attrs.bg;
                if (!colorEq(attrs.underline_color, common.underline_color)) common.underline_color = GridTypes.default_underline_color;
            }
        }
        if (!common.underline) {
            common.underline_style = .straight;
            common.underline_color = GridTypes.default_underline_color;
        }
        return common;
    }

    fn appendSgrParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), first: *bool, text: []const u8) void {
        if (!first.*) output.appendSlice(allocator, ";") catch return;
        first.* = false;
        output.appendSlice(allocator, text) catch {};
    }

    fn underlineStyleParam(style: GridTypes.UnderlineStyle) []const u8 {
        return switch (style) {
            .straight => "4",
            .double => "4:2",
            .curly => "4:3",
            .dotted => "4:4",
            .dashed => "4:5",
        };
    }

    fn appendColorParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, first: *bool, is_fg: bool, color: GridTypes.Color, default_color: GridTypes.Color) void {
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

    fn appendExtendedColorParam(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, first: *bool, prefix: u8, color: GridTypes.Color) void {
        if (indexed256Index(color)) |idx| {
            const text = std.fmt.bufPrint(encode_buf, "{d};5;{d}", .{ prefix, idx }) catch return;
            appendSgrParam(allocator, output, first, text);
            return;
        }
        const text = std.fmt.bufPrint(encode_buf, "{d};2;{d};{d};{d}", .{ prefix, color.r, color.g, color.b }) catch return;
        appendSgrParam(allocator, output, first, text);
    }

    fn ansi16Index(color: GridTypes.Color) ?u8 {
        var idx: u8 = 0;
        while (idx < 16) : (idx += 1) {
            if (colorEq(color, ansi16Color(idx))) return idx;
        }
        return null;
    }

    fn indexed256Index(color: GridTypes.Color) ?u8 {
        var idx: u16 = 0;
        while (idx < 256) : (idx += 1) {
            if (colorEq(color, indexed256Color(@intCast(idx)))) return @intCast(idx);
        }
        return null;
    }

    fn colorEq(a: GridTypes.Color, b: GridTypes.Color) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }

    fn ansi16Color(idx: u8) GridTypes.Color {
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
            else => GridTypes.default_fg,
        };
    }

    fn indexed256Color(idx: u8) GridTypes.Color {
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
};
