//! Responsibility: define the howl-vt ABI export root.
//! Ownership: export `howl_vt_*` symbols only.
//! Reason: keep the shipped boundary on the C ABI instead of a Zig root.

const ffi = @import("ffi.zig");

comptime {
    @export(&ffi.modNone, .{ .name = "howl_vt_mod_none" });
    @export(&ffi.modShift, .{ .name = "howl_vt_mod_shift" });
    @export(&ffi.modAlt, .{ .name = "howl_vt_mod_alt" });
    @export(&ffi.modCtrl, .{ .name = "howl_vt_mod_ctrl" });
    @export(&ffi.modIsValid, .{ .name = "howl_vt_mod_is_valid" });
    @export(&ffi.keyEnter, .{ .name = "howl_vt_key_enter" });
    @export(&ffi.keyTab, .{ .name = "howl_vt_key_tab" });
    @export(&ffi.keyBackspace, .{ .name = "howl_vt_key_backspace" });
    @export(&ffi.keyEscape, .{ .name = "howl_vt_key_escape" });
    @export(&ffi.keyUp, .{ .name = "howl_vt_key_up" });
    @export(&ffi.keyDown, .{ .name = "howl_vt_key_down" });
    @export(&ffi.keyLeft, .{ .name = "howl_vt_key_left" });
    @export(&ffi.keyRight, .{ .name = "howl_vt_key_right" });
    @export(&ffi.keyInsert, .{ .name = "howl_vt_key_insert" });
    @export(&ffi.keyDelete, .{ .name = "howl_vt_key_delete" });
    @export(&ffi.keyHome, .{ .name = "howl_vt_key_home" });
    @export(&ffi.keyEnd, .{ .name = "howl_vt_key_end" });
    @export(&ffi.keyPageup, .{ .name = "howl_vt_key_pageup" });
    @export(&ffi.keyPagedown, .{ .name = "howl_vt_key_pagedown" });
    @export(&ffi.keyF1, .{ .name = "howl_vt_key_f1" });
    @export(&ffi.keyF2, .{ .name = "howl_vt_key_f2" });
    @export(&ffi.keyF3, .{ .name = "howl_vt_key_f3" });
    @export(&ffi.keyF4, .{ .name = "howl_vt_key_f4" });
    @export(&ffi.keyF5, .{ .name = "howl_vt_key_f5" });
    @export(&ffi.keyF6, .{ .name = "howl_vt_key_f6" });
    @export(&ffi.keyF7, .{ .name = "howl_vt_key_f7" });
    @export(&ffi.keyF8, .{ .name = "howl_vt_key_f8" });
    @export(&ffi.keyF9, .{ .name = "howl_vt_key_f9" });
    @export(&ffi.keyF10, .{ .name = "howl_vt_key_f10" });
    @export(&ffi.keyF11, .{ .name = "howl_vt_key_f11" });
    @export(&ffi.keyF12, .{ .name = "howl_vt_key_f12" });
    @export(&ffi.keyIsValid, .{ .name = "howl_vt_key_is_valid" });
    @export(&ffi.mouseButtonNone, .{ .name = "howl_vt_mouse_button_none" });
    @export(&ffi.mouseButtonLeft, .{ .name = "howl_vt_mouse_button_left" });
    @export(&ffi.mouseButtonMiddle, .{ .name = "howl_vt_mouse_button_middle" });
    @export(&ffi.mouseButtonRight, .{ .name = "howl_vt_mouse_button_right" });
    @export(&ffi.mouseButtonWheelUp, .{ .name = "howl_vt_mouse_button_wheel_up" });
    @export(&ffi.mouseButtonWheelDown, .{ .name = "howl_vt_mouse_button_wheel_down" });
    @export(&ffi.mouseButtonIsValid, .{ .name = "howl_vt_mouse_button_is_valid" });
    @export(&ffi.mousePress, .{ .name = "howl_vt_mouse_press" });
    @export(&ffi.mouseRelease, .{ .name = "howl_vt_mouse_release" });
    @export(&ffi.mouseMove, .{ .name = "howl_vt_mouse_move" });
    @export(&ffi.mouseWheel, .{ .name = "howl_vt_mouse_wheel" });
    @export(&ffi.mouseEventKindIsValid, .{ .name = "howl_vt_mouse_event_kind_is_valid" });
    @export(&ffi.terminalInit, .{ .name = "howl_vt_terminal_init" });
    @export(&ffi.terminalDeinit, .{ .name = "howl_vt_terminal_deinit" });
    @export(&ffi.terminalFeed, .{ .name = "howl_vt_terminal_feed" });
    @export(&ffi.terminalQueuedEventCount, .{ .name = "howl_vt_terminal_queued_event_count" });
    @export(&ffi.terminalApply, .{ .name = "howl_vt_terminal_apply" });
    @export(&ffi.terminalResize, .{ .name = "howl_vt_terminal_resize" });
    @export(&ffi.terminalHistoryCount, .{ .name = "howl_vt_terminal_history_count" });
    @export(&ffi.terminalIsAlternateScreen, .{ .name = "howl_vt_terminal_is_alternate_screen" });
    @export(&ffi.terminalClearDirtyRows, .{ .name = "howl_vt_terminal_clear_dirty_rows" });
    @export(&ffi.terminalCopyVisible, .{ .name = "howl_vt_terminal_copy_visible" });
    @export(&ffi.terminalCopyPendingOutput, .{ .name = "howl_vt_terminal_copy_pending_output" });
    @export(&ffi.terminalClearPendingOutput, .{ .name = "howl_vt_terminal_clear_pending_output" });
    @export(&ffi.terminalDrainPendingClipboard, .{ .name = "howl_vt_terminal_drain_pending_clipboard" });
    @export(&ffi.terminalEncodeKey, .{ .name = "howl_vt_terminal_encode_key" });
    @export(&ffi.terminalEncodeFocus, .{ .name = "howl_vt_terminal_encode_focus" });
    @export(&ffi.terminalEncodeMouse, .{ .name = "howl_vt_terminal_encode_mouse" });
    @export(&ffi.terminalEncodePaste, .{ .name = "howl_vt_terminal_encode_paste" });
}
