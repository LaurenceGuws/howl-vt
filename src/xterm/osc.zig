const std = @import("std");
const events = @import("../action/vocabulary.zig");
const parser_mod = @import("../parser.zig");
const kitty = @import("../kitty/protocol.zig");

const SemanticEvent = events.SemanticEvent;

pub fn process(osc: parser_mod.OscAction) ?SemanticEvent {
    return switch (osc) {
        .raw_title => |v| SemanticEvent{ .title_set = v.payload },
        .title => |v| SemanticEvent{ .title_set = v.payload },
        .pointer_shape => |v| SemanticEvent{ .kitty_pointer_shape = kitty.parsePointerShape(v.payload) },
        .palette_control => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .palette_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .dynamic_reset => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .kitty_color => |v| SemanticEvent{ .color_control = .{ .command = v.command, .payload = v.payload } },
        .notification => |v| if (kitty.parseNotification(v.payload)) |notification| SemanticEvent{ .kitty_notification = notification } else null,
        .shell_mark => |v| if (kitty.parseShellMark(v.payload)) |mark| SemanticEvent{ .kitty_shell_mark = mark } else null,
        .kitty_text_size => |v| SemanticEvent{ .kitty_text_size = v.payload },
        .kitty_clipboard => |v| SemanticEvent{ .clipboard_set = v.payload },
        .kitty_file_transfer => |v| SemanticEvent{ .kitty_file_transfer = v.payload },
        .kitty_color_stack_push => SemanticEvent{ .kitty_color_stack = .push },
        .kitty_color_stack_pop => SemanticEvent{ .kitty_color_stack = .pop },
        .hyperlink => |v| blk: {
            const separator = std.mem.indexOfScalar(u8, v.payload, ';') orelse break :blk null;
            const uri = v.payload[separator + 1 ..];
            if (uri.len == 0) break :blk SemanticEvent.hyperlink_clear;
            break :blk SemanticEvent{ .hyperlink_set = uri };
        },
        .clipboard => |v| SemanticEvent{ .clipboard_set = v.payload },
        else => null,
    };
}

pub fn decodeClipboardSet(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const decoded_len = try decodedClipboardSetSize(raw);
    const out = try allocator.alloc(u8, @intCast(decoded_len));
    errdefer allocator.free(out);
    _ = try decodeClipboardSetInto(raw, out);
    return out;
}

pub fn decodedClipboardSetSize(raw: []const u8) !u64 {
    const data = clipboardData(raw) orelse return error.InvalidOsc52Payload;
    if (std.mem.eql(u8, data, "?")) return error.UnsupportedOsc52Query;
    return @intCast(try std.base64.standard.Decoder.calcSizeForSlice(data));
}

pub fn decodeClipboardSetInto(raw: []const u8, out: []u8) !u64 {
    const data = clipboardData(raw) orelse return error.InvalidOsc52Payload;
    if (std.mem.eql(u8, data, "?")) return error.UnsupportedOsc52Query;
    const decoded_len = try std.base64.standard.Decoder.calcSizeForSlice(data);
    if (out.len < decoded_len) return error.ShortBuffer;
    try std.base64.standard.Decoder.decode(out[0..decoded_len], data);
    return @intCast(decoded_len);
}

fn clipboardData(raw: []const u8) ?[]const u8 {
    const sep = std.mem.indexOfScalar(u8, raw, ';') orelse return null;
    return raw[sep + 1 ..];
}

test "OSC 52 clipboard set payload decodes" {
    const decoded = try decodeClipboardSet(std.testing.allocator, "c;SG93bA==");
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("Howl", decoded);
}

test "OSC 52 clipboard query is unsupported for set drain" {
    try std.testing.expectError(error.UnsupportedOsc52Query, decodeClipboardSet(std.testing.allocator, "c;?"));
}
