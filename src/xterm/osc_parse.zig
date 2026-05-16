//! OSC command classification shared by parser transport and OSC routing.

const std = @import("std");

pub const Kind = enum {
    title,
    clipboard,
    hyperlink,
    other,
};

pub const Parsed = struct {
    kind: Kind,
    command: ?u16,
    payload: []const u8,
};

pub fn parse(data: []const u8) Parsed {
    const separator = std.mem.indexOfScalar(u8, data, ';') orelse data.len;
    const command_text = data[0..separator];
    const payload = if (separator < data.len) data[separator + 1 ..] else "";
    const command = std.fmt.parseUnsigned(u16, command_text, 10) catch return .{
        .kind = if (separator == data.len) .title else .other,
        .command = null,
        .payload = data,
    };
    return .{
        .kind = switch (command) {
            0, 1, 2 => .title,
            8 => .hyperlink,
            52 => .clipboard,
            else => .other,
        },
        .command = command,
        .payload = payload,
    };
}

test "OSC parse: title command strips numeric prefix" {
    const parsed = parse("0;My Title");
    try std.testing.expectEqual(Kind.title, parsed.kind);
    try std.testing.expectEqual(@as(?u16, 0), parsed.command);
    try std.testing.expectEqualStrings("My Title", parsed.payload);
}

test "OSC parse: clipboard command keeps payload" {
    const parsed = parse("52;c;Zm9v");
    try std.testing.expectEqual(Kind.clipboard, parsed.kind);
    try std.testing.expectEqual(@as(?u16, 52), parsed.command);
    try std.testing.expectEqualStrings("c;Zm9v", parsed.payload);
}

test "OSC parse: unknown command stays other" {
    const parsed = parse("777;notify");
    try std.testing.expectEqual(Kind.other, parsed.kind);
    try std.testing.expectEqual(@as(?u16, 777), parsed.command);
    try std.testing.expectEqualStrings("notify", parsed.payload);
}
