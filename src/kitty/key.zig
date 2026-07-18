//! Owns the bounded Kitty keyboard-protocol stack and report encoding.

const std = @import("std");
const host_state = @import("../host_state.zig");

const format_output_max_bytes = 16;

/// Stores current Kitty keyboard flags and at most sixteen prior flag sets.
pub const Stack = struct {
    flags: u32 = 0,
    stack: [16]u32 = [_]u32{0} ** 16,
    len: u8 = 0,

    /// Replaces, sets, or clears current keyboard flags according to Kitty mode semantics.
    pub fn set(self: *Stack, flags: u32, mode: u8) void {
        switch (mode) {
            2 => self.flags |= flags,
            3 => self.flags &= ~flags,
            else => self.flags = flags,
        }
    }

    /// Pushes current flags and installs new flags, dropping the oldest entry at capacity.
    pub fn push(self: *Stack, flags: u32) void {
        if (self.len == self.stack.len) {
            std.mem.copyForwards(u32, self.stack[0 .. self.stack.len - 1], self.stack[1..self.stack.len]);
            self.len -= 1;
        }
        self.stack[self.len] = self.flags;
        self.len += 1;
        self.flags = flags;
    }

    /// Restores up to count prior flag sets and clears flags when count exceeds stack depth.
    pub fn pop(self: *Stack, count: u16) void {
        var remaining = count;
        while (remaining > 0 and self.len > 0) : (remaining -= 1) {
            self.len -= 1;
            self.flags = self.stack[self.len];
        }
        if (remaining > 0) self.flags = 0;
    }

    /// Appends the current keyboard flags as one bounded Kitty reply.
    pub fn appendReport(self: *const Stack, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8) host_state.ApplyError!void {
        std.debug.assert(encode_buf.len >= format_output_max_bytes);
        const text = std.fmt.bufPrint(encode_buf, "\x1b[?{d}u", .{self.flags}) catch unreachable;
        try host_state.appendOutput(output, allocator, text);
    }
};
