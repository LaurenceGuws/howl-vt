//! Responsibility: buffer OSC/APC/DCS/PM string-control payloads until terminator.
//! Ownership: parser string-control syntax helper.
//! Reason: keep string-control transport buffering separate from the main byte-state machine.

const std = @import("std");

/// String-control terminator style.
pub const Finish = enum {
    bel,
    st,
};

const State = enum {
    idle,
    payload,
    esc,
};

/// Incremental string-control payload buffer.
pub const StringControl = struct {
    allocator: std.mem.Allocator,
    state: State = .idle,
    buffer: std.ArrayList(u8),
    max_len: usize,
    bel_terminates: bool,

    /// Initialize string-control state and storage.
    pub fn init(allocator: std.mem.Allocator, capacity: usize, max_len: usize, bel_terminates: bool) !StringControl {
        return .{
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
            .max_len = max_len,
            .bel_terminates = bel_terminates,
        };
    }

    /// Release owned payload storage.
    pub fn deinit(self: *StringControl) void {
        self.buffer.deinit(self.allocator);
    }

    /// Reset parser state and buffered payload.
    pub fn reset(self: *StringControl) void {
        self.state = .idle;
        self.buffer.clearRetainingCapacity();
    }

    /// Start a fresh string-control payload.
    pub fn start(self: *StringControl) void {
        self.state = .payload;
        self.buffer.clearRetainingCapacity();
    }

    /// Return whether a payload is currently open.
    pub fn active(self: *const StringControl) bool {
        return self.state != .idle;
    }

    /// Return the completed payload bytes.
    pub fn data(self: *const StringControl) []const u8 {
        return self.buffer.items;
    }

    /// Clear bytes after the caller emits them.
    pub fn clearFinished(self: *StringControl) void {
        self.buffer.clearRetainingCapacity();
    }

    /// Feed one byte and return a terminator when complete.
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
