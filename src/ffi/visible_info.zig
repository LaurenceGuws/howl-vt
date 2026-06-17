const handle = @import("handle.zig");
const status = @import("status.zig");

pub const FfiVisibleInfo = extern struct {
    rows: u32 = 0,
    cols: u32 = 0,
    history_count: u64 = 0,
    is_alternate_screen: u8 = 0,
    reserved0: u8 = 0,
    reserved1: u16 = 0,
    snapshot_seq: u64 = 0,
    dirty_generation: u64 = 0,
};

pub const FfiVisibleInfoResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    reserved0: u32 = 0,
    info: FfiVisibleInfo = .{},
};

pub fn terminalQueryVisibleInfo(vt_handle: handle.VtHandle, scrollback_offset: u64) callconv(.c) FfiVisibleInfoResult {
    const owned = handle.vtFromHandle(vt_handle) orelse return .{ .status = @intFromEnum(status.HowlVtCallStatus.missing_handle) };
    const meta = owned.visibleMeta(scrollback_offset);
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .info = .{
            .rows = meta.rows,
            .cols = meta.cols,
            .history_count = meta.history_count,
            .is_alternate_screen = @intFromBool(meta.is_alternate_screen),
            .snapshot_seq = meta.snapshot_seq,
            .dirty_generation = meta.dirty_generation,
        },
    };
}
