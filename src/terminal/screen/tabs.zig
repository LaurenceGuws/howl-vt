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

pub fn horizontalForward(self: anytype, count: u16) void {
    if (self.cols == 0) return;
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) {
        if (self.cursor_col >= self.cols - 1) break;
        var col = self.cursor_col + 1;
        while (col < self.cols and !isStop(self, col)) : (col += 1) {}
        self.cursor_col = if (col < self.cols) col else self.cols - 1;
    }
}

pub fn horizontalBack(self: anytype, count: u16) void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) {
        if (self.cursor_col == 0) break;
        var col = self.cursor_col - 1;
        while (col > 0 and !isStop(self, col)) : (col -= 1) {}
        self.cursor_col = if (isStop(self, col)) col else 0;
    }
}

pub fn isStop(self: anytype, col: u16) bool {
    if (self.tab_stops) |stops| {
        if (col < stops.len) return stops[col];
    }
    return col != 0 and col % 8 == 0;
}

pub fn setStop(self: anytype) void {
    if (self.tab_stops) |stops| {
        if (self.cursor_col < stops.len) stops[self.cursor_col] = true;
    }
}

pub fn clearCurrentStop(self: anytype) void {
    if (self.tab_stops) |stops| {
        if (self.cursor_col < stops.len) stops[self.cursor_col] = false;
    }
}

pub fn clearAllStops(self: anytype) void {
    if (self.tab_stops) |stops| @memset(stops, false);
}

pub fn resetDefaultStops(self: anytype) void {
    if (self.tab_stops) |stops| setDefaultTabStops(stops);
}
