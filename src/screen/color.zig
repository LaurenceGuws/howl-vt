pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

pub const Kind = enum(u8) {
    default,
    indexed,
    rgb,
};

pub const Color = struct {
    kind: Kind,
    value: u32,

    pub fn indexed(idx: u8) Color {
        return .{ .kind = .indexed, .value = idx };
    }

    pub fn rgb(rgb_value: Rgb) Color {
        return .{
            .kind = .rgb,
            .value = (@as(u32, rgb_value.r) << 16) | (@as(u32, rgb_value.g) << 8) | @as(u32, rgb_value.b),
        };
    }

    pub fn rgbComponents(r: u8, g: u8, b: u8) Color {
        return rgb(.{ .r = r, .g = g, .b = b });
    }
};

pub const default_fg = Color{ .kind = .default, .value = 0 };
pub const default_bg = Color{ .kind = .default, .value = 0 };
pub const default_underline_color = Color{ .kind = .default, .value = 0 };
