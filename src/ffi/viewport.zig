const terminal = @import("../terminal.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub const FfiScrollViewportResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    changed: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
};

pub fn terminalScrollViewport(vt_handle: handle.VtHandle, kind: u8, value: i64) callconv(.c) FfiScrollViewportResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const behavior = behaviorIn(kind, value) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.invalid_argument) };
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .changed = @intFromBool(owned.scrollViewport(behavior)),
    };
}

fn behaviorIn(kind: u8, value: i64) ?terminal.Terminal.ScrollViewport {
    return switch (kind) {
        0 => .top,
        1 => .bottom,
        2 => .{ .delta = value },
        3 => if (value >= 0) .{ .absolute = @intCast(value) } else null,
        else => null,
    };
}
