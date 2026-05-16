//! Grid color values and defaults.

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const default_fg = Color{ .r = 220, .g = 220, .b = 220 };
pub const default_bg = Color{ .r = 24, .g = 25, .b = 33 };
pub const default_underline_color = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };
