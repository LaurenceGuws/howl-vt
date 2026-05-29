const std = @import("std");

pub const Encoded = struct {
    allocator: ?std.mem.Allocator = null,
    bytes: []const u8 = "",

    pub fn deinit(self: *Encoded) void {
        if (self.allocator) |allocator| allocator.free(self.bytes);
        self.* = .{};
    }
};

test "encoded owner deinit releases owned buffer" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.dupe(u8, "payload");
    var encoded: Encoded = .{ .allocator = allocator, .bytes = bytes };

    encoded.deinit();

    try std.testing.expectEqual(@as(?std.mem.Allocator, null), encoded.allocator);
    try std.testing.expectEqualStrings("", encoded.bytes);
}
