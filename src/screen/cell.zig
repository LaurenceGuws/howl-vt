//! Grid cell values and defaults.

const color = @import("color.zig");

const Color = color.Color;

pub const UnderlineStyle = enum(u3) {
    straight,
    double,
    curly,
    dotted,
    dashed,
};

pub const CellAttrs = struct {
    fg: Color,
    bg: Color,
    bold: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    underline: bool,
    underline_style: UnderlineStyle,
    underline_color: Color,
    protected: bool,
    link_id: u32,
};

pub const Cell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [2]u32 = .{ 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    attrs: CellAttrs,
};

pub fn isCellContinuation(cell: Cell) bool {
    return cell.x != 0 or cell.y != 0;
}

pub const default_fg = color.default_fg;
pub const default_bg = color.default_bg;
pub const default_underline_color = color.default_underline_color;

pub const default_cell_attrs = CellAttrs{
    .fg = default_fg,
    .bg = default_bg,
    .bold = false,
    .blink = false,
    .blink_fast = false,
    .reverse = false,
    .underline = false,
    .underline_style = .straight,
    .underline_color = default_underline_color,
    .protected = false,
    .link_id = 0,
};

pub const default_cell = Cell{
    .codepoint = 0,
    .attrs = default_cell_attrs,
};
