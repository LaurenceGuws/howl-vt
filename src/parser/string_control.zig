//! OSC/APC/DCS/PM byte accumulation.

const std = @import("std");

/// String-control terminator.
pub const Finish = enum {
    bel,
    st,
};

const State = enum {
    idle,
    payload,
    esc,
};

/// Incremental string-control byte buffer.
pub const StringControl = struct {
    allocator: std.mem.Allocator,
    state: State = .idle,
    buffer: std.ArrayList(u8),
    max_len: usize,
    bel_terminates: bool,

    pub fn init(allocator: std.mem.Allocator, capacity: usize, max_len: usize, bel_terminates: bool) !StringControl {
        return .{
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
            .max_len = max_len,
            .bel_terminates = bel_terminates,
        };
    }

    pub fn deinit(self: *StringControl) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *StringControl) void {
        self.state = .idle;
        self.buffer.clearRetainingCapacity();
    }

    pub fn start(self: *StringControl) void {
        self.state = .payload;
        self.buffer.clearRetainingCapacity();
    }

    pub fn active(self: *const StringControl) bool {
        return self.state != .idle;
    }

    pub fn data(self: *const StringControl) []const u8 {
        return self.buffer.items;
    }

    pub fn clearFinished(self: *StringControl) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn feed(self: *StringControl, byte: u8) ?Finish {
        switch (self.state) {
            .idle => return null,
            .payload => {
                if (self.bel_terminates and byte == 0x07) {
                    self.state = .idle;
                    return .bel;
                }
                if (byte == 0x1B) {
                    self.state = .esc;
                    return null;
                }
                self.append(byte);
                return null;
            },
            .esc => {
                if (byte == '\\') {
                    self.state = .idle;
                    return .st;
                }

                // Stray ESC marker is dropped; following byte stays payload.
                self.state = .payload;
                self.append(byte);
                return null;
            },
        }
    }

    fn append(self: *StringControl, byte: u8) void {
        if (self.buffer.items.len < self.max_len) {
            self.buffer.append(self.allocator, byte) catch {};
        }
    }
};
