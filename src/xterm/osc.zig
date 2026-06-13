const std = @import("std");
const events = @import("../action/vocabulary.zig");
const parser_mod = @import("../terminal/parser/main.zig");
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

test "OSC title and hyperlink actions map to semantic events" {
    try std.testing.expectEqualStrings("My Title", process(.{ .title = .{ .command = 0, .payload = "My Title", .term = .bel } }).?.title_set);
    try std.testing.expectEqualStrings("Raw Title", process(.{ .raw_title = .{ .payload = "Raw Title", .term = .bel } }).?.title_set);
    try std.testing.expectEqualStrings("https://example.com", process(.{ .hyperlink = .{ .payload = ";https://example.com", .term = .bel } }).?.hyperlink_set);
    try std.testing.expect(process(.{ .hyperlink = .{ .payload = ";", .term = .bel } }).? == .hyperlink_clear);
}

test "OSC clipboard and color controls preserve payloads" {
    try std.testing.expectEqualStrings("c;Zm9v", process(.{ .clipboard = .{ .command = 52, .payload = "c;Zm9v", .term = .bel } }).?.clipboard_set);

    const kitty_color = process(.{ .kitty_color = .{ .command = 21, .payload = "foreground=?", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 21), kitty_color.color_control.command);
    try std.testing.expectEqualStrings("foreground=?", kitty_color.color_control.payload);

    const xterm_palette = process(.{ .palette_control = .{ .command = 4, .payload = "1;#ff0000", .term = .st } }).?;
    try std.testing.expectEqual(@as(u16, 4), xterm_palette.color_control.command);
    try std.testing.expectEqualStrings("1;#ff0000", xterm_palette.color_control.payload);
}

test "OSC kitty consequence payloads map to semantic events" {
    const shell_mark = process(.{ .shell_mark = .{ .payload = "D;7", .term = .bel } }).?;
    try std.testing.expectEqual(@as(u8, 'D'), shell_mark.kitty_shell_mark.kind);
    try std.testing.expectEqual(@as(?i32, 7), shell_mark.kitty_shell_mark.status);

    const notification = process(.{ .notification = .{ .command = 99, .payload = "i=1:p=body;Hello", .term = .st } }).?;
    try std.testing.expectEqualStrings("i=1:p=body", notification.kitty_notification.metadata);
    try std.testing.expectEqualStrings("Hello", notification.kitty_notification.payload);

    const alias = process(.{ .notification = .{ .command = 9, .payload = "i=2:p=body;Hi", .term = .st } }).?;
    try std.testing.expectEqualStrings("i=2:p=body", alias.kitty_notification.metadata);
    try std.testing.expectEqualStrings("Hi", alias.kitty_notification.payload);

    const pointer = process(.{ .pointer_shape = .{ .payload = ">wait,pointer", .term = .st } }).?;
    try std.testing.expectEqual(@as(u8, '>'), pointer.kitty_pointer_shape.action);
    try std.testing.expectEqualStrings("wait,pointer", pointer.kitty_pointer_shape.names);

    const push = process(.{ .kitty_color_stack_push = .st }).?;
    const pop = process(.{ .kitty_color_stack_pop = .st }).?;
    try std.testing.expect(push.kitty_color_stack == .push);
    try std.testing.expect(pop.kitty_color_stack == .pop);

    const clipboard = process(.{ .kitty_clipboard = .{ .payload = "type=write", .term = .st } }).?;
    try std.testing.expectEqualStrings("type=write", clipboard.clipboard_set);

    const transfer = process(.{ .kitty_file_transfer = .{ .payload = "cmd=data", .term = .st } }).?;
    try std.testing.expectEqualStrings("cmd=data", transfer.kitty_file_transfer);

    const size = process(.{ .kitty_text_size = .{ .payload = "s=2;Big", .term = .st } }).?;
    try std.testing.expectEqualStrings("s=2;Big", size.kitty_text_size);
}
