const std = @import("std");
const parser_mod = @import("../parser/main.zig");
const cell_mod = @import("cell.zig");
const color_mod = @import("color.zig");

const CellAttrs = cell_mod.CellAttrs;
const Color = color_mod.Color;
const default_cell_attrs = cell_mod.default_cell_attrs;
const default_underline_color = color_mod.default_underline_color;

pub fn applySgr(self: anytype, params: []const i32, separators: parser_mod.CsiSeparatorList) void {
    if (params.len == 0) {
        self.current_attrs = default_cell_attrs;
        return;
    }

    std.debug.assert(params.len <= std.math.maxInt(u8));
    const param_len: u8 = @intCast(params.len);
    var i: u8 = 0;
    while (i < param_len) : (i += 1) {
        const p = params[idxOf(i)];
        switch (p) {
            4 => applyUnderlineStyle(self, params, separators, &i),
            38 => applyExtendedColor(self, params, &i, true),
            48 => applyExtendedColor(self, params, &i, false),
            58 => applyUnderlineColor(self, params, &i),
            else => applyBasicSgr(self, p),
        }
    }
}

fn applyBasicSgr(self: anytype, param: i32) void {
    switch (param) {
        0 => self.current_attrs = default_cell_attrs,
        1 => self.current_attrs.bold = true,
        2 => self.current_attrs.dim = true,
        3 => self.current_attrs.italic = true,
        5, 6 => self.current_attrs.blink = true,
        7 => self.current_attrs.reverse = true,
        8 => self.current_attrs.invisible = true,
        9 => self.current_attrs.strikethrough = true,
        22 => {
            self.current_attrs.bold = false;
            self.current_attrs.dim = false;
        },
        23 => self.current_attrs.italic = false,
        24 => clearUnderline(self),
        25 => clearBlink(self),
        27 => self.current_attrs.reverse = false,
        28 => self.current_attrs.invisible = false,
        29 => self.current_attrs.strikethrough = false,
        30...37 => self.current_attrs.fg = ansi16Color(@intCast(param - 30)),
        39 => self.current_attrs.fg = default_cell_attrs.fg,
        40...47 => self.current_attrs.bg = ansi16Color(@intCast(param - 40)),
        49 => self.current_attrs.bg = default_cell_attrs.bg,
        59 => self.current_attrs.underline_color = default_underline_color,
        90...97 => self.current_attrs.fg = ansi16Color(@intCast((param - 90) + 8)),
        100...107 => self.current_attrs.bg = ansi16Color(@intCast((param - 100) + 8)),
        else => {},
    }
}

fn applyUnderlineStyle(self: anytype, params: []const i32, separators: parser_mod.CsiSeparatorList, idx: *u8) void {
    const next = idx.* + 1;
    if (next < params.len and separators.isSet(idx.*)) {
        setUnderlineStyle(self, params[idxOf(next)]);
        idx.* += 1;
        return;
    }
    self.current_attrs.underline = true;
    self.current_attrs.underline_style = .straight;
}

fn setUnderlineStyle(self: anytype, value: i32) void {
    switch (value) {
        0 => clearUnderline(self),
        1 => setUnderline(self, .straight),
        2 => setUnderline(self, .double),
        3 => setUnderline(self, .curly),
        4 => setUnderline(self, .dotted),
        5 => setUnderline(self, .dashed),
        else => {},
    }
}

fn setUnderline(self: anytype, style: cell_mod.UnderlineStyle) void {
    self.current_attrs.underline = true;
    self.current_attrs.underline_style = style;
}

fn clearUnderline(self: anytype) void {
    self.current_attrs.underline = false;
    self.current_attrs.underline_style = .straight;
}

fn clearBlink(self: anytype) void {
    self.current_attrs.blink = false;
    self.current_attrs.blink_fast = false;
}

fn applyExtendedColor(self: anytype, params: []const i32, idx: *u8, is_fg: bool) void {
    const color = decodeExtendedColor(params, idx) orelse return;
    if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
}

fn applyUnderlineColor(self: anytype, params: []const i32, idx: *u8) void {
    const color = decodeExtendedColor(params, idx) orelse return;
    self.current_attrs.underline_color = color;
}

fn decodeExtendedColor(params: []const i32, idx: *u8) ?Color {
    const next = idx.* + 1;
    if (next >= params.len) return null;
    const mode = params[idxOf(next)];
    if (mode == 5) {
        if (idx.* + 2 >= params.len) return null;
        idx.* += 2;
        return .indexed(clampByte(params[idxOf(idx.*)]));
    }
    if (mode == 2) {
        if (idx.* + 4 >= params.len) return null;
        idx.* += 4;
        return Color.rgb(.{
            .r = clampByte(params[idxOf(idx.* - 2)]),
            .g = clampByte(params[idxOf(idx.* - 1)]),
            .b = clampByte(params[idxOf(idx.*)]),
        });
    }
    return null;
}

fn idxOf(value: u8) usize {
    return @intCast(value);
}

pub fn applyRectAttrOps(target: *CellAttrs, attrs: []const u16, reverse: bool) void {
    for (attrs) |attr| {
        switch (attr) {
            0 => if (!reverse) {
                target.bold = false;
                target.dim = false;
                target.italic = false;
                target.underline = false;
                target.underline_style = .straight;
                target.blink = false;
                target.blink_fast = false;
                target.reverse = false;
                target.invisible = false;
                target.strikethrough = false;
            },
            1 => {
                if (reverse) target.bold = !target.bold else target.bold = true;
            },
            2 => {
                if (reverse) target.dim = !target.dim else target.dim = true;
            },
            3 => {
                if (reverse) target.italic = !target.italic else target.italic = true;
            },
            4 => {
                if (reverse) {
                    target.underline = !target.underline;
                    if (target.underline) target.underline_style = .straight;
                } else {
                    target.underline = true;
                    target.underline_style = .straight;
                }
            },
            5 => {
                if (reverse) target.blink = !target.blink else target.blink = true;
            },
            7 => {
                if (reverse) target.reverse = !target.reverse else target.reverse = true;
            },
            8 => {
                if (reverse) target.invisible = !target.invisible else target.invisible = true;
            },
            9 => {
                if (reverse) target.strikethrough = !target.strikethrough else target.strikethrough = true;
            },
            22 => {
                if (!reverse) {
                    target.bold = false;
                    target.dim = false;
                }
            },
            23 => {
                if (!reverse) target.italic = false;
            },
            24 => {
                if (!reverse) {
                    target.underline = false;
                    target.underline_style = .straight;
                }
            },
            25 => {
                if (!reverse) {
                    target.blink = false;
                    target.blink_fast = false;
                }
            },
            27 => {
                if (!reverse) target.reverse = false;
            },
            28 => {
                if (!reverse) target.invisible = false;
            },
            29 => {
                if (!reverse) target.strikethrough = false;
            },
            else => {},
        }
    }
}

fn clampByte(v: i32) u8 {
    return @intCast(@max(0, @min(255, v)));
}

fn ansi16Color(idx: u8) Color {
    return switch (idx) {
        0...15 => .indexed(idx),
        else => default_cell_attrs.fg,
    };
}

fn indexed256Color(idx: u8) Color {
    return .indexed(idx);
}
