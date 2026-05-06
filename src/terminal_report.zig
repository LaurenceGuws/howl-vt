//! Responsibility: own terminal host-output report formatting and checksum helpers.
//! Ownership: terminal report protocol domain owner.
//! Reason: keep host-output-facing report generation out of the vt-core facade.

const std = @import("std");
const interpret_owner = @import("interpret.zig");

const Interpret = interpret_owner.Interpret;

pub const TerminalReport = struct {
    pub fn appendModifyOtherKeysReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, value: i8) void {
        const text = std.fmt.bufPrint(encode_buf, "\x1b[>4;{d}m", .{value}) catch return;
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
};
