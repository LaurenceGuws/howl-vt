const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub fn terminalCopyVisibleHyperlink(vt_handle: handle.VtHandle, scrollback_offset: u64, row: u16, col: u16, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    const uri = owned.visibleCellHyperlinkUriCurrent(scrollback_offset, row, col) orelse &.{};
    return bytes.copyBytes(out, uri);
}
