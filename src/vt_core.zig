//! Public howl-vt-core package surface.

const lib = @This();
const std = @import("std");
const ffi = @import("ffi.zig");
const terminal = @import("terminal.zig");

pub const Ffi = ffi;
pub const Input = @import("input.zig");
pub const Grid = @import("grid.zig").Grid;
pub const Parser = @import("parser.zig").Parser;
pub const Snapshot = @import("snapshot.zig");
pub const Selection = @import("selection.zig");
pub const VtCore = terminal.VtCore;

comptime {
    if (@import("root") == lib) {
        @export(&ffi.modNone, .{ .name = "howl_vt_mod_none" });
        @export(&ffi.modShift, .{ .name = "howl_vt_mod_shift" });
        @export(&ffi.modAlt, .{ .name = "howl_vt_mod_alt" });
        @export(&ffi.modCtrl, .{ .name = "howl_vt_mod_ctrl" });
        @export(&ffi.keyEnter, .{ .name = "howl_vt_key_enter" });
        @export(&ffi.keyTab, .{ .name = "howl_vt_key_tab" });
        @export(&ffi.keyBackspace, .{ .name = "howl_vt_key_backspace" });
        @export(&ffi.keyEscape, .{ .name = "howl_vt_key_escape" });
        @export(&ffi.keyUp, .{ .name = "howl_vt_key_up" });
        @export(&ffi.keyDown, .{ .name = "howl_vt_key_down" });
        @export(&ffi.keyLeft, .{ .name = "howl_vt_key_left" });
        @export(&ffi.keyRight, .{ .name = "howl_vt_key_right" });
        @export(&ffi.mouseButtonNone, .{ .name = "howl_vt_mouse_button_none" });
        @export(&ffi.mouseButtonLeft, .{ .name = "howl_vt_mouse_button_left" });
        @export(&ffi.mouseButtonMiddle, .{ .name = "howl_vt_mouse_button_middle" });
        @export(&ffi.mouseButtonRight, .{ .name = "howl_vt_mouse_button_right" });
        @export(&ffi.mouseButtonWheelUp, .{ .name = "howl_vt_mouse_button_wheel_up" });
        @export(&ffi.mouseButtonWheelDown, .{ .name = "howl_vt_mouse_button_wheel_down" });
        @export(&ffi.mousePress, .{ .name = "howl_vt_mouse_press" });
        @export(&ffi.mouseRelease, .{ .name = "howl_vt_mouse_release" });
        @export(&ffi.mouseMove, .{ .name = "howl_vt_mouse_move" });
        @export(&ffi.mouseWheel, .{ .name = "howl_vt_mouse_wheel" });
    }
}

test {
    _ = terminal;
    std.testing.refAllDecls(lib);
}
