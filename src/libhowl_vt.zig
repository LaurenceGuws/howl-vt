const ffi = @import("ffi/main.zig");

comptime {
    @export(&ffi.terminalInit, .{ .name = "howl_vt_terminal_init" });
    @export(&ffi.terminalInitWithOptions, .{ .name = "howl_vt_terminal_init_with_options" });
    @export(&ffi.terminalDeinit, .{ .name = "howl_vt_terminal_deinit" });
    @export(&ffi.terminalResize, .{ .name = "howl_vt_terminal_resize" });
    @export(&ffi.terminalSetCellPixelSize, .{ .name = "howl_vt_terminal_set_cell_pixel_size" });
    @export(&ffi.terminalStartSelection, .{ .name = "howl_vt_terminal_start_selection" });
    @export(&ffi.terminalUpdateSelection, .{ .name = "howl_vt_terminal_update_selection" });
    @export(&ffi.terminalFinishSelection, .{ .name = "howl_vt_terminal_finish_selection" });
    @export(&ffi.terminalClearSelection, .{ .name = "howl_vt_terminal_clear_selection" });
    @export(&ffi.terminalFeed, .{ .name = "howl_vt_terminal_feed" });
    @export(&ffi.terminalProgressRuntime, .{ .name = "howl_vt_terminal_progress_runtime" });
    @export(&ffi.terminalQueryVisibleMeta, .{ .name = "howl_vt_terminal_query_visible_meta" });
    @export(&ffi.terminalCopySurface, .{ .name = "howl_vt_terminal_copy_surface" });
    @export(&ffi.terminalQuerySelection, .{ .name = "howl_vt_terminal_query_selection" });
    @export(&ffi.terminalCopySurfaceHyperlink, .{ .name = "howl_vt_terminal_copy_surface_hyperlink" });
    @export(&ffi.terminalCopySelection, .{ .name = "howl_vt_terminal_copy_selection" });
    @export(&ffi.terminalCopyTitle, .{ .name = "howl_vt_terminal_copy_title" });
    @export(&ffi.terminalCopyPendingOutput, .{ .name = "howl_vt_terminal_copy_pending_output" });
    @export(&ffi.terminalDrainPendingClipboard, .{ .name = "howl_vt_terminal_drain_pending_clipboard" });
    @export(&ffi.terminalQueryRuntimeObligation, .{ .name = "howl_vt_terminal_query_runtime_obligation" });
    @export(&ffi.terminalEncodeKey, .{ .name = "howl_vt_terminal_encode_key" });
    @export(&ffi.terminalEncodeFocus, .{ .name = "howl_vt_terminal_encode_focus" });
    @export(&ffi.terminalEncodePasteStart, .{ .name = "howl_vt_terminal_encode_paste_start" });
    @export(&ffi.terminalEncodePasteEnd, .{ .name = "howl_vt_terminal_encode_paste_end" });
    @export(&ffi.terminalEncodeMouse, .{ .name = "howl_vt_terminal_encode_mouse" });
    @export(&ffi.terminalEncodePaste, .{ .name = "howl_vt_terminal_encode_paste" });
    @export(&ffi.terminalAckSurface, .{ .name = "howl_vt_terminal_ack_surface" });
    @export(&ffi.terminalClearPendingOutput, .{ .name = "howl_vt_terminal_clear_pending_output" });
}
