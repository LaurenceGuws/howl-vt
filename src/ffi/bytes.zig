const status = @import("status.zig");

pub const FfiBytesResult = extern struct {
    status: i32 = @intFromEnum(status.HowlVtCallStatus.failed),
    written: u64 = 0,
    needed: u64 = 0,
};

pub const FfiByteSpan = extern struct {
    ptr: [*c]const u8,
    // The shipped C ABI owns architecture-sized span lengths at this boundary.
    len: usize,
};

pub const FfiU16Span = extern struct {
    ptr: [*c]const u16,
    // The shipped C ABI owns architecture-sized span lengths at this boundary.
    len: usize,
};

pub fn bytesIn(ptr: ?[*]const u8, len: usize) ?[]const u8 {
    // C callers provide architecture-sized byte counts; translate immediately to a Zig slice.
    if (ptr == null) {
        if (len != 0) return null;
        return &.{};
    }
    return ptr.?[0..len];
}

pub fn bytesOut(ptr: ?[*]u8, len: usize) ?[]u8 {
    // C callers provide architecture-sized buffer capacities; translate immediately to a Zig slice.
    if (ptr == null) {
        if (len != 0) return null;
        return &.{};
    }
    return ptr.?[0..len];
}

pub fn copyBytes(out: []u8, source_bytes: []const u8) FfiBytesResult {
    if (out.len < source_bytes.len) {
        return .{
            .status = @intFromEnum(status.HowlVtCallStatus.short_buffer),
            .needed = source_bytes.len,
        };
    }
    if (source_bytes.len != 0) @memcpy(out[0..source_bytes.len], source_bytes);
    return .{
        .status = @intFromEnum(status.HowlVtCallStatus.ok),
        .written = source_bytes.len,
        .needed = source_bytes.len,
    };
}
