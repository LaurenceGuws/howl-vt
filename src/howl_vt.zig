//! Public howl-vt-core package surface.

const lib = @This();
const std = @import("std");
const vt = @import("vt/main.zig");
const ffi = vt.c_api;

pub const Ffi = ffi;
pub const Input = vt.Input;
pub const Grid = vt.Grid;
pub const Parser = vt.Parser;
pub const Snapshot = vt.Snapshot;
pub const Selection = vt.Selection;
pub const VtCore = vt.VtCore;

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
    std.testing.refAllDecls(lib);
}
