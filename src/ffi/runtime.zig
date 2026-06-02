const std = @import("std");
const terminal = @import("../terminal.zig");
const handle = @import("handle.zig");
const status = @import("status.zig");

pub const FfiRuntimeObligation = extern struct {
    pending_now: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    deadline_ns: u64 = 0,
};

pub const FfiRuntimeObligationResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    obligation: FfiRuntimeObligation = .{},
};

pub const FfiRuntimeProgressResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    state_changed: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    obligation: FfiRuntimeObligation = .{},
};

fn boolByte(value: bool) u8 {
    return if (value) 1 else 0;
}

fn runtimeObligationOut(value: terminal.Terminal.RuntimeObligation) FfiRuntimeObligation {
    return .{
        .pending_now = boolByte(value.pending_now),
        .deadline_ns = value.deadline_ns,
    };
}

fn runtimeObligationResult(value: terminal.Terminal.RuntimeObligation) FfiRuntimeObligationResult {
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .obligation = runtimeObligationOut(value),
    };
}

fn runtimeProgressResult(value: terminal.Terminal.RuntimeProgress) FfiRuntimeProgressResult {
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .state_changed = boolByte(value.state_changed),
        .obligation = runtimeObligationOut(value.obligation),
    };
}

pub fn terminalQueryRuntimeObligation(vt_handle: handle.VtHandle, now_ns: u64) callconv(.c) FfiRuntimeObligationResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    return runtimeObligationResult(owned.runtimeObligation(now_ns));
}

pub fn terminalProgressRuntime(vt_handle: handle.VtHandle, now_ns: u64) callconv(.c) FfiRuntimeProgressResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const progress = owned.progressRuntime(now_ns) catch |err| {
        return .{ .status = @intFromEnum(switch (err) {
            error.ConsequenceLimit => status.HowlVtCallStatus.limit_reached,
            error.OutOfMemory => status.HowlVtCallStatus.failed,
        }) };
    };
    return runtimeProgressResult(progress);
}

test "vt ffi runtime obligation query and progress default idle" {
    const lifecycle = @import("lifecycle.zig");
    const vt_handle = lifecycle.terminalInit(3, 16, 4);
    defer lifecycle.terminalDeinit(vt_handle);
    try std.testing.expect(vt_handle != null);

    const obligation = terminalQueryRuntimeObligation(vt_handle, 1234);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), obligation.status);
    try std.testing.expectEqual(@as(u8, 0), obligation.obligation.pending_now);
    try std.testing.expectEqual(@as(u64, 0), obligation.obligation.deadline_ns);

    const progress = terminalProgressRuntime(vt_handle, 1234);
    try std.testing.expectEqual(@as(i32, @intFromEnum(status.HowlVtCallStatus.ok)), progress.status);
    try std.testing.expectEqual(@as(u8, 0), progress.state_changed);
    try std.testing.expectEqual(@as(u8, 0), progress.obligation.pending_now);
    try std.testing.expectEqual(@as(u64, 0), progress.obligation.deadline_ns);
}
