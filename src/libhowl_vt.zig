
const ffi = @import("ffi.zig");

comptime {
    @export(&ffi.terminalInit, .{ .name = "howl_vt_terminal_init" });
    @export(&ffi.terminalDeinit, .{ .name = "howl_vt_terminal_deinit" });
    @export(&ffi.terminalFeed, .{ .name = "howl_vt_terminal_feed" });
    @export(&ffi.terminalApply, .{ .name = "howl_vt_terminal_apply" });
    @export(&ffi.terminalResize, .{ .name = "howl_vt_terminal_resize" });
    @export(&ffi.terminalClearDirtyRows, .{ .name = "howl_vt_terminal_clear_dirty_rows" });
    @export(&ffi.terminalCopySurface, .{ .name = "howl_vt_terminal_copy_surface" });
    @export(&ffi.terminalCopyVisible, .{ .name = "howl_vt_terminal_copy_visible" });
    @export(&ffi.terminalCopyDirty, .{ .name = "howl_vt_terminal_copy_dirty" });
    @export(&ffi.terminalCopyPendingOutput, .{ .name = "howl_vt_terminal_copy_pending_output" });
    @export(&ffi.terminalClearPendingOutput, .{ .name = "howl_vt_terminal_clear_pending_output" });
    @export(&ffi.terminalDrainPendingClipboard, .{ .name = "howl_vt_terminal_drain_pending_clipboard" });
    @export(&ffi.terminalEncodeKey, .{ .name = "howl_vt_terminal_encode_key" });
    @export(&ffi.terminalEncodeFocus, .{ .name = "howl_vt_terminal_encode_focus" });
    @export(&ffi.terminalEncodeMouse, .{ .name = "howl_vt_terminal_encode_mouse" });
    @export(&ffi.terminalEncodePaste, .{ .name = "howl_vt_terminal_encode_paste" });
}
