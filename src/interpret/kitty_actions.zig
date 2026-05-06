//! Responsibility: parse kitty protocol action payloads.
//! Ownership: kitty action mapping helpers.
//! Reason: keep kitty OSC/APC payload parsing out of the top-level action router.

const std = @import("std");
const action_types = @import("action_types.zig");

pub fn parseGraphics(data: []const u8) ?action_types.KittyGraphicsCommand {
    if (data.len == 0 or data[0] != 'G') return null;
    const body = data[1..];
    const separator = std.mem.indexOfScalar(u8, body, ';') orelse body.len;
    const control = body[0..separator];
    const payload = if (separator < body.len) body[separator + 1 ..] else "";
    var cmd = action_types.KittyGraphicsCommand{
        .action = 't',
        .image_id = 0,
        .image_number = 0,
        .placement_id = 0,
        .format = 32,
        .width = 0,
        .height = 0,
        .columns = 0,
        .rows = 0,
        .x = 0,
        .y = 0,
        .z = 0,
        .medium = 'd',
        .more_chunks = false,
        .quiet = false,
        .delete_target = 0,
        .payload = payload,
    };

    var fields = std.mem.splitScalar(u8, control, ',');
    while (fields.next()) |field| {
        if (field.len < 3 or field[1] != '=') continue;
        const key = field[0];
        const value = field[2..];
        switch (key) {
            'a' => {
                if (value.len > 0) cmd.action = value[0];
            },
            'i' => cmd.image_id = parseU32(value),
            'I' => cmd.image_number = parseU32(value),
            'p' => cmd.placement_id = parseU32(value),
            'f' => cmd.format = parseU16(value),
            's' => cmd.width = parseU32(value),
            'v' => cmd.height = parseU32(value),
            'c' => cmd.columns = parseU32(value),
            'r' => cmd.rows = parseU32(value),
            'x' => cmd.x = parseU32(value),
            'y' => cmd.y = parseU32(value),
            'z' => cmd.z = parseI32(value),
            't' => {
                if (value.len > 0) cmd.medium = value[0];
            },
            'm' => cmd.more_chunks = parseU32(value) != 0,
            'q' => cmd.quiet = parseU32(value) != 0,
            'd' => {
                if (value.len > 0) cmd.delete_target = value[0];
            },
            else => {},
        }
    }
    return cmd;
}

pub fn parseShellMark(payload: []const u8) ?action_types.KittyShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    const kind = payload[0];
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D' and metadata.len > 0) std.fmt.parseInt(i32, metadata, 10) catch null else null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

pub fn parseNotification(payload: []const u8) ?action_types.KittyNotificationCommand {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    return .{
        .metadata = payload[0..separator],
        .payload = payload[separator + 1 ..],
    };
}

pub fn parsePointerShape(payload: []const u8) action_types.KittyPointerShapeCommand {
    if (payload.len == 0) return .{ .action = '=', .names = "" };
    const action = switch (payload[0]) {
        '=', '>', '<', '?' => payload[0],
        else => '=',
    };
    const names = if (action == '=') blk: {
        if (payload[0] == '=') break :blk payload[1..];
        break :blk payload;
    } else payload[1..];
    return .{ .action = action, .names = names };
}

fn parseU32(value: []const u8) u32 {
    return std.fmt.parseUnsigned(u32, value, 10) catch 0;
}

fn parseU16(value: []const u8) u16 {
    return std.fmt.parseUnsigned(u16, value, 10) catch 0;
}

fn parseI32(value: []const u8) i32 {
    return std.fmt.parseInt(i32, value, 10) catch 0;
}
