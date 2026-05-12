//! Responsibility: implement the howl-vt-core native ABI constants surface.
//! Ownership: VT input key, modifier, and mouse constants.
//! Reason: keep C consumers on the same backend-agnostic input contract as Zig consumers.

const input = @import("input.zig");

const key_min: u32 = input.key_enter;
const key_max: u32 = input.key_f12;
const mod_mask: u32 = input.mod_shift | input.mod_alt | input.mod_ctrl;

pub fn modIsValid(mods: u32) callconv(.c) u8 {
    return if ((mods & ~mod_mask) == 0) 1 else 0;
}

pub fn modNone() callconv(.c) u32 {
    return input.mod_none;
}

pub fn modShift() callconv(.c) u32 {
    return input.mod_shift;
}

pub fn modAlt() callconv(.c) u32 {
    return input.mod_alt;
}

pub fn modCtrl() callconv(.c) u32 {
    return input.mod_ctrl;
}

pub fn keyEnter() callconv(.c) u32 {
    return input.key_enter;
}

pub fn keyTab() callconv(.c) u32 {
    return input.key_tab;
}

pub fn keyBackspace() callconv(.c) u32 {
    return input.key_backspace;
}

pub fn keyEscape() callconv(.c) u32 {
    return input.key_escape;
}

pub fn keyUp() callconv(.c) u32 {
    return input.key_up;
}

pub fn keyDown() callconv(.c) u32 {
    return input.key_down;
}

pub fn keyLeft() callconv(.c) u32 {
    return input.key_left;
}

pub fn keyRight() callconv(.c) u32 {
    return input.key_right;
}

pub fn keyInsert() callconv(.c) u32 {
    return input.key_insert;
}

pub fn keyDelete() callconv(.c) u32 {
    return input.key_delete;
}

pub fn keyHome() callconv(.c) u32 {
    return input.key_home;
}

pub fn keyEnd() callconv(.c) u32 {
    return input.key_end;
}

pub fn keyPageup() callconv(.c) u32 {
    return input.key_pageup;
}

pub fn keyPagedown() callconv(.c) u32 {
    return input.key_pagedown;
}

pub fn keyF1() callconv(.c) u32 {
    return input.key_f1;
}

pub fn keyF2() callconv(.c) u32 {
    return input.key_f2;
}

pub fn keyF3() callconv(.c) u32 {
    return input.key_f3;
}

pub fn keyF4() callconv(.c) u32 {
    return input.key_f4;
}

pub fn keyF5() callconv(.c) u32 {
    return input.key_f5;
}

pub fn keyF6() callconv(.c) u32 {
    return input.key_f6;
}

pub fn keyF7() callconv(.c) u32 {
    return input.key_f7;
}

pub fn keyF8() callconv(.c) u32 {
    return input.key_f8;
}

pub fn keyF9() callconv(.c) u32 {
    return input.key_f9;
}

pub fn keyF10() callconv(.c) u32 {
    return input.key_f10;
}

pub fn keyF11() callconv(.c) u32 {
    return input.key_f11;
}

pub fn keyF12() callconv(.c) u32 {
    return input.key_f12;
}

pub fn keyIsValid(key: u32) callconv(.c) u8 {
    if (key < key_min) return 0;
    if (key > key_max) return 0;
    return 1;
}

pub fn mouseButtonNone() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_none);
}

pub fn mouseButtonLeft() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_left);
}

pub fn mouseButtonMiddle() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_middle);
}

pub fn mouseButtonRight() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_right);
}

pub fn mouseButtonWheelUp() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_wheel_up);
}

pub fn mouseButtonWheelDown() callconv(.c) u8 {
    return @intFromEnum(input.mouse_button_wheel_down);
}

pub fn mousePress() callconv(.c) u8 {
    return @intFromEnum(input.mouse_press);
}

pub fn mouseRelease() callconv(.c) u8 {
    return @intFromEnum(input.mouse_release);
}

pub fn mouseMove() callconv(.c) u8 {
    return @intFromEnum(input.mouse_move);
}

pub fn mouseWheel() callconv(.c) u8 {
    return @intFromEnum(input.mouse_wheel);
}

pub fn mouseButtonIsValid(button: u8) callconv(.c) u8 {
    return switch (button) {
        @intFromEnum(input.mouse_button_none),
        @intFromEnum(input.mouse_button_left),
        @intFromEnum(input.mouse_button_middle),
        @intFromEnum(input.mouse_button_right),
        @intFromEnum(input.mouse_button_wheel_up),
        @intFromEnum(input.mouse_button_wheel_down),
        => 1,
        else => 0,
    };
}

pub fn mouseEventKindIsValid(kind: u8) callconv(.c) u8 {
    return switch (kind) {
        @intFromEnum(input.mouse_press),
        @intFromEnum(input.mouse_release),
        @intFromEnum(input.mouse_move),
        @intFromEnum(input.mouse_wheel),
        => 1,
        else => 0,
    };
}

test "vt ffi modifier and key vocabulary proves positive and negative space" {
    try @import("std").testing.expectEqual(input.mod_none, modNone());
    try @import("std").testing.expectEqual(input.mod_shift, modShift());
    try @import("std").testing.expectEqual(input.mod_alt, modAlt());
    try @import("std").testing.expectEqual(input.mod_ctrl, modCtrl());
    try @import("std").testing.expectEqual(@as(u8, 1), modIsValid(input.mod_none));
    try @import("std").testing.expectEqual(@as(u8, 1), modIsValid(input.mod_shift | input.mod_alt | input.mod_ctrl));
    try @import("std").testing.expectEqual(@as(u8, 0), modIsValid(8));

    try @import("std").testing.expectEqual(input.key_insert, keyInsert());
    try @import("std").testing.expectEqual(input.key_delete, keyDelete());
    try @import("std").testing.expectEqual(input.key_f12, keyF12());
    try @import("std").testing.expectEqual(@as(u8, 1), keyIsValid(keyEnter()));
    try @import("std").testing.expectEqual(@as(u8, 1), keyIsValid(keyF12()));
    try @import("std").testing.expectEqual(@as(u8, 0), keyIsValid(0));
    try @import("std").testing.expectEqual(@as(u8, 0), keyIsValid(keyF12() + 1));
}

test "vt ffi mouse vocabulary proves positive and negative space" {
    try @import("std").testing.expectEqual(@intFromEnum(input.mouse_button_left), mouseButtonLeft());
    try @import("std").testing.expectEqual(@intFromEnum(input.mouse_wheel), mouseWheel());
    try @import("std").testing.expectEqual(@as(u8, 1), mouseButtonIsValid(mouseButtonWheelDown()));
    try @import("std").testing.expectEqual(@as(u8, 0), mouseButtonIsValid(9));
    try @import("std").testing.expectEqual(@as(u8, 1), mouseEventKindIsValid(mouseMove()));
    try @import("std").testing.expectEqual(@as(u8, 0), mouseEventKindIsValid(9));
}
