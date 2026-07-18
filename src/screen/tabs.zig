const std = @import("std");

pub fn allocTabStops(allocator: std.mem.Allocator, cols: u16) !?[]bool {
    if (cols == 0) return null;
    const buf = try allocator.alloc(bool, cols);
    setDefaultTabStops(buf);
    return buf;
}

pub fn setDefaultTabStops(stops: []bool) void {
    @memset(stops, false);
    for (stops, 0..) |*stop, idx| {
        if (idx != 0 and idx % 8 == 0) stop.* = true;
    }
}

pub fn copyTabStops(dst: ?[]bool, src: ?[]const bool) void {
    const d = dst orelse return;
    const s = src orelse return;
    @memcpy(d[0..@min(d.len, s.len)], s[0..@min(d.len, s.len)]);
}
