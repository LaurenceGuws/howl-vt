//! Kitty keyboard protocol state and reports.

const std = @import("std");

pub const Stack = struct {
    flags: u32 = 0,
    stack: [16]u32 = [_]u32{0} ** 16,
    len: u8 = 0,

    pub fn set(self: *Stack, flags: u32, mode: u8) void {
        switch (mode) {
            2 => self.flags |= flags,
            3 => self.flags &= ~flags,
            else => self.flags = flags,
        }
    }

    pub fn push(self: *Stack, flags: u32) void {
        if (self.len == self.stack.len) {
            std.mem.copyForwards(u32, self.stack[0 .. self.stack.len - 1], self.stack[1..self.stack.len]);
            self.len -= 1;
        }
        self.stack[self.len] = self.flags;
        self.len += 1;
        self.flags = flags;
    }

    pub fn pop(self: *Stack, count: u16) void {
        var remaining = count;
        while (remaining > 0 and self.len > 0) : (remaining -= 1) {
            self.len -= 1;
            self.flags = self.stack[self.len];
        }
        if (remaining > 0) self.flags = 0;
    }

    pub fn appendReport(self: *const Stack, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8) void {
        const text = std.fmt.bufPrint(encode_buf, "\x1b[?{d}u", .{self.flags}) catch return;
        output.appendSlice(allocator, text) catch {};
    }
};
