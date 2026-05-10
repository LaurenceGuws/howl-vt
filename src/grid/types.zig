//! Responsibility: define terminal grid value types and defaults.
//! Ownership: grid data shape authority.
//! Reason: keep visible cell/cursor/color schema near terminal screen state.

const selection_owner = @import("../selection/selection.zig");

const Selection = selection_owner;

const CursorPos = struct {
    row: usize,
    col: usize,
};

pub const CursorShape = enum {
    block,
    underline,
    bar,
};

pub const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

pub const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

pub const SelectionPos = Selection.SelectionPos;
pub const TerminalSelection = Selection.TerminalSelection;

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

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

pub fn isMultiRowCellRoot(cell: Cell) bool {
    return cell.height > 1 and cell.x == 0 and cell.y == 0;
}

pub const default_fg = Color{ .r = 220, .g = 220, .b = 220 };
pub const default_bg = Color{ .r = 24, .g = 25, .b = 33 };
pub const default_underline_color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

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

pub fn defaultCell() Cell {
    return Cell{
        .codepoint = 0,
        .width = 1,
        .attrs = CellAttrs{
            .fg = default_fg,
            .bg = default_bg,
            .bold = false,
            .blink = false,
            .blink_fast = false,
            .reverse = false,
            .underline = false,
            .underline_style = .straight,
            .underline_color = default_fg,
            .protected = false,
            .link_id = 0,
        },
    };
}
