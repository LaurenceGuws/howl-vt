//! Grid text style and SGR color decoding.

const cell_mod = @import("cell.zig");
const color_mod = @import("color.zig");

const CellAttrs = cell_mod.CellAttrs;
const Color = color_mod.Color;
const default_cell_attrs = cell_mod.default_cell_attrs;
const default_underline_color = color_mod.default_underline_color;

pub fn applySgr(self: anytype, params: []const i32, separators: []const u8) void {
    if (params.len == 0) {
        self.current_attrs = default_cell_attrs;
        return;
    }

    var i: usize = 0;
    while (i < params.len) : (i += 1) {
        const p = params[i];
        switch (p) {
            0 => self.current_attrs = default_cell_attrs,
            1 => self.current_attrs.bold = true,
            4 => {
                if (i + 1 < params.len and separators[i + 1] == ':') {
                    switch (params[i + 1]) {
                        0 => self.current_attrs.underline = false,
                        1 => {
                            self.current_attrs.underline = true;
                            self.current_attrs.underline_style = .straight;
                        },
                        2 => {
                            self.current_attrs.underline = true;
                            self.current_attrs.underline_style = .double;
                        },
                        3 => {
                            self.current_attrs.underline = true;
                            self.current_attrs.underline_style = .curly;
                        },
                        4 => {
                            self.current_attrs.underline = true;
                            self.current_attrs.underline_style = .dotted;
                        },
                        5 => {
                            self.current_attrs.underline = true;
                            self.current_attrs.underline_style = .dashed;
                        },
                        else => {},
                    }
                    i += 1;
                } else {
                    self.current_attrs.underline = true;
                    self.current_attrs.underline_style = .straight;
                }
            },
            5, 6 => self.current_attrs.blink = true,
            7 => self.current_attrs.reverse = true,
            22 => self.current_attrs.bold = false,
            24 => {
                self.current_attrs.underline = false;
                self.current_attrs.underline_style = .straight;
            },
            25 => {
                self.current_attrs.blink = false;
                self.current_attrs.blink_fast = false;
            },
            27 => self.current_attrs.reverse = false,
            30...37 => self.current_attrs.fg = ansi16Color(@intCast(p - 30)),
            39 => self.current_attrs.fg = default_cell_attrs.fg,
            40...47 => self.current_attrs.bg = ansi16Color(@intCast(p - 40)),
            49 => self.current_attrs.bg = default_cell_attrs.bg,
            90...97 => self.current_attrs.fg = ansi16Color(@intCast((p - 90) + 8)),
            100...107 => self.current_attrs.bg = ansi16Color(@intCast((p - 100) + 8)),
            38, 48 => {
                const is_fg = p == 38;
                if (i + 1 >= params.len) break;
                const mode = params[i + 1];
                if (mode == 5) {
                    if (i + 2 >= params.len) break;
                    const color = indexed256Color(clampByte(params[i + 2]));
                    if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
                    i += 2;
                } else if (mode == 2) {
                    if (i + 4 >= params.len) break;
                    const color = Color{
                        .r = clampByte(params[i + 2]),
                        .g = clampByte(params[i + 3]),
                        .b = clampByte(params[i + 4]),
                    };
                    if (is_fg) self.current_attrs.fg = color else self.current_attrs.bg = color;
                    i += 4;
                }
            },
            58 => {
                if (i + 1 >= params.len) break;
                const mode = params[i + 1];
                if (mode == 5) {
                    if (i + 2 >= params.len) break;
                    self.current_attrs.underline_color = indexed256Color(clampByte(params[i + 2]));
                    i += 2;
                } else if (mode == 2) {
                    if (i + 4 >= params.len) break;
                    self.current_attrs.underline_color = .{
                        .r = clampByte(params[i + 2]),
                        .g = clampByte(params[i + 3]),
                        .b = clampByte(params[i + 4]),
                    };
                    i += 4;
                }
            },
            59 => self.current_attrs.underline_color = default_underline_color,
            else => {},
        }
    }
}

pub fn applyRectAttrOps(target: *CellAttrs, attrs: []const u16, reverse: bool) void {
    for (attrs) |attr| {
        switch (attr) {
            0 => if (!reverse) {
                target.bold = false;
                target.underline = false;
                target.underline_style = .straight;
                target.blink = false;
                target.blink_fast = false;
                target.reverse = false;
            },
            1 => {
                if (reverse) target.bold = !target.bold else target.bold = true;
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
            22 => {
                if (!reverse) target.bold = false;
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
            else => {},
        }
    }
}

fn clampByte(v: i32) u8 {
    return @intCast(@max(0, @min(255, v)));
}

fn ansi16Color(idx: u8) Color {
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
        else => default_cell_attrs.fg,
    };
}

fn indexed256Color(idx: u8) Color {
    if (idx < 16) return ansi16Color(idx);
    if (idx < 232) {
        const i: u32 = idx - 16;
        return .{
            .r = @intCast((i / 36) * 51),
            .g = @intCast(((i / 6) % 6) * 51),
            .b = @intCast((i % 6) * 51),
        };
    }
    const gray: u8 = @intCast((@as(u32, idx) - 232) * 10 + 8);
    return .{ .r = gray, .g = gray, .b = gray };
}
