//! Responsibility: implement the howl-vt-core native ABI constants surface.
//! Ownership: VT input key, modifier, and mouse constants.
//! Reason: keep C consumers on the same backend-agnostic input contract as Zig consumers.

const vt = @import("vt_core.zig");

pub fn modNone() callconv(.c) u32 {
    return vt.Input.mod_none;
}

pub fn modShift() callconv(.c) u32 {
    return vt.Input.mod_shift;
}

pub fn modAlt() callconv(.c) u32 {
    return vt.Input.mod_alt;
}

pub fn modCtrl() callconv(.c) u32 {
    return vt.Input.mod_ctrl;
}

pub fn keyEnter() callconv(.c) u32 {
    return vt.Input.key_enter;
}

pub fn keyTab() callconv(.c) u32 {
    return vt.Input.key_tab;
}

pub fn keyBackspace() callconv(.c) u32 {
    return vt.Input.key_backspace;
}

pub fn keyEscape() callconv(.c) u32 {
    return vt.Input.key_escape;
}

pub fn keyUp() callconv(.c) u32 {
    return vt.Input.key_up;
}

pub fn keyDown() callconv(.c) u32 {
    return vt.Input.key_down;
}

pub fn keyLeft() callconv(.c) u32 {
    return vt.Input.key_left;
}

pub fn keyRight() callconv(.c) u32 {
    return vt.Input.key_right;
}

pub fn mouseButtonNone() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_button_none);
}

pub fn mouseButtonLeft() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_button_left);
}

pub fn mouseButtonMiddle() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_button_middle);
}

pub fn mouseButtonRight() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_button_right);
}

pub fn mouseButtonWheelUp() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_button_wheel_up);
}

pub fn mouseButtonWheelDown() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_button_wheel_down);
}

pub fn mousePress() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_press);
}

pub fn mouseRelease() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_release);
}

pub fn mouseMove() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_move);
}

pub fn mouseWheel() callconv(.c) u8 {
    return @intFromEnum(vt.Input.mouse_wheel);
}
