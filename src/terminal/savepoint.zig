const screen_mod = @import("../screen.zig");

const Screen = screen_mod.Screen;

pub const Savepoint = struct {
    valid: bool = false,
    row: u16 = 0,
    col: u16 = 0,
    style: Screen.CursorStyle = Screen.default_cursor_style,
    current_attrs: Screen.CellAttrs = Screen.default_cell_attrs,
    origin_mode: bool = false,
    auto_wrap: bool = true,
    gl_index: u8 = 0,
    g0_designation: u8 = 'B',
    g1_designation: u8 = 'B',

    pub fn clear(self: *Savepoint) void {
        self.* = .{};
    }
};
