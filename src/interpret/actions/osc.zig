//! Responsibility: map OSC parser events into typed terminal actions.
//! Ownership: interpret OSC action mapping.
//! Reason: keep string-protocol meaning separate from the top-level action router.

const std = @import("std");
const types = @import("types.zig");
const parser_events = @import("../parser_events.zig");
const kitty = @import("kitty.zig");

const SemanticEvent = types.SemanticEvent;

pub fn process(kind: parser_events.OscKind, command: ?u16, payload: []const u8) ?SemanticEvent {
    if (command) |cmd| switch (cmd) {
        22 => return SemanticEvent{ .kitty_pointer_shape = kitty.parsePointerShape(payload) },
        4, 10, 11, 12, 21, 104, 110, 111, 112 => return SemanticEvent{ .color_control = .{ .command = cmd, .payload = payload } },
        9, 99 => if (kitty.parseNotification(payload)) |notification| return SemanticEvent{ .kitty_notification = notification },
        133 => if (kitty.parseShellMark(payload)) |mark| return SemanticEvent{ .kitty_shell_mark = mark },
        66 => return SemanticEvent{ .kitty_text_size = payload },
        5522 => return SemanticEvent{ .clipboard_set = payload },
        5113 => return SemanticEvent{ .kitty_file_transfer = payload },
        30001 => return SemanticEvent{ .kitty_color_stack = .push },
        30101 => return SemanticEvent{ .kitty_color_stack = .pop },
        else => {},
    };
    return switch (kind) {
        .hyperlink => blk: {
            const separator = std.mem.indexOfScalar(u8, payload, ';') orelse break :blk null;
            const uri = payload[separator + 1 ..];
            if (uri.len == 0) break :blk SemanticEvent.hyperlink_clear;
            break :blk SemanticEvent{ .hyperlink_set = uri };
        },
        .clipboard => SemanticEvent{ .clipboard_set = payload },
        else => null,
    };
}

pub fn decodeClipboardSet(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const sep = std.mem.indexOfScalar(u8, raw, ';') orelse return error.InvalidOsc52Payload;
    const data = raw[sep + 1 ..];
    if (std.mem.eql(u8, data, "?")) return error.UnsupportedOsc52Query;
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(data);
    const out = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(out);
    try std.base64.standard.Decoder.decode(out, data);
    return out;
}

test "OSC 52 clipboard set payload decodes" {
    const decoded = try decodeClipboardSet(std.testing.allocator, "c;SG93bA==");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("Howl", decoded);
}

test "OSC 52 clipboard query is unsupported for set drain" {
    try std.testing.expectError(error.UnsupportedOsc52Query, decodeClipboardSet(std.testing.allocator, "c;?"));
}
