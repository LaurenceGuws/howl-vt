const host_state = @import("../host/state.zig");
const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub fn terminalCopyPendingOutput(vt_handle: handle.VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    return switch (host_state.copyPendingOutputInto(owned, out)) {
        .copied => |written| .{
            .status = @intFromEnum(status.HowlVtCallStatus.ok),
            .written = written,
            .needed = written,
        },
        .short => |needed| .{
            .status = @intFromEnum(status.HowlVtCallStatus.short_buffer),
            .needed = needed,
        },
    };
}

pub fn terminalClearPendingOutput(vt_handle: handle.VtHandle) callconv(.c) void {
    const owned = handle.vtFromHandle(vt_handle) orelse return;
    host_state.clearPendingOutput(owned);
}

pub fn terminalDrainPendingClipboard(vt_handle: handle.VtHandle, ptr: ?[*]u8, cap: usize) callconv(.c) bytes.FfiBytesResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const out = bytes.bytesOut(ptr, cap) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    return switch (host_state.drainPendingClipboardSetInto(owned, out)) {
        .none => .{ .status = @intFromEnum(status.HowlVtCallStatus.ok) },
        .copied => |written| .{
            .status = @intFromEnum(status.HowlVtCallStatus.ok),
            .written = written,
            .needed = written,
        },
        .short => |needed| .{
            .status = @intFromEnum(status.HowlVtCallStatus.short_buffer),
            .needed = needed,
        },
        .failed => .{ .status = @intFromEnum(status.HowlVtCallStatus.failed) },
    };
}
