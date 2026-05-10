//! Ground-state stream byte classification.

const std = @import("std");
const utf8 = @import("utf8.zig");

/// Stream event union for parser sink input.
pub const StreamEvent = union(enum) {
    codepoint: u21,
    control: u8,
    invalid,
};

/// Stream decoder for text/control classification.
pub const Stream = struct {
    decoder: utf8.Utf8Decoder = .{},

    /// Reset stream decoder state.
    pub fn reset(self: *Stream) void {
        self.decoder.reset();
    }

    /// Feed one byte and emit stream event when available.
    pub fn feed(self: *Stream, byte: u8) ?StreamEvent {
        if (self.decoder.needed == 0 and (byte < 0x20 or byte == 0x7f)) {
            return .{ .control = byte };
        }

        const res = self.decoder.feed(byte);
        return switch (res) {
            .codepoint => |cp| .{ .codepoint = cp },
            .invalid => .invalid,
            .incomplete => null,
        };
    }
};

test "Stream: control vs codepoint distinction" {
    var str = Stream{};
    const event_ctrl = str.feed(0x07);
    try std.testing.expect(event_ctrl.?.control == 0x07);
    str.reset();
    const event_text = str.feed('X');
    try std.testing.expect(event_text.?.codepoint == 'X');
}
