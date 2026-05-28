const std = @import("std");
const vocabulary = @import("../action/vocabulary.zig");

pub fn parseGraphics(data: []const u8) ?vocabulary.KittyGraphicsCommand {
    if (data.len == 0 or data[0] != 'G') return null;
    const body = data[1..];
    const separator = std.mem.indexOfScalar(u8, body, ';') orelse body.len;
    const control = body[0..separator];
    const payload = if (separator < body.len) body[separator + 1 ..] else "";
    var cmd = vocabulary.KittyGraphicsCommand{
        .action = 't',
        .unicode_placement = false,
        .image_id = 0,
        .image_number = 0,
        .placement_id = 0,
        .parent_image_id = 0,
        .parent_placement_id = 0,
        .format = 32,
        .width = 0,
        .height = 0,
        .data_size = 0,
        .data_offset = 0,
        .source_width = 0,
        .source_height = 0,
        .columns = 0,
        .rows = 0,
        .current_frame_number = 0,
        .edit_frame_number = 0,
        .base_frame_number = 0,
        .x = 0,
        .y = 0,
        .parent_offset_cols = 0,
        .parent_offset_rows = 0,
        .cell_x_offset = 0,
        .cell_y_offset = 0,
        .compose_mode = 0,
        .background_rgba = 0,
        .animation_state = 0,
        .loop_count = 0,
        .z = 0,
        .medium = 'd',
        .compression = 0,
        .more_chunks = false,
        .quiet = false,
        .delete_target = 0,
        .payload = payload,
    };

    if (control.len != 0) {
        var fields = std.mem.splitScalar(u8, control, ',');
        while (fields.next()) |field| {
            if (field.len == 0 or field.len < 3 or field[1] != '=') return null;
            const key = field[0];
            const value = field[2..];
            switch (key) {
                'a' => {
                    cmd.action = parseFlag(value, "Tacdfpqt") orelse return null;
                },
                'i' => cmd.image_id = parseU32(value) orelse return null,
                'I' => cmd.image_number = parseU32(value) orelse return null,
                'p' => cmd.placement_id = parseU32(value) orelse return null,
                'P' => cmd.parent_image_id = parseU32(value) orelse return null,
                'Q' => cmd.parent_placement_id = parseU32(value) orelse return null,
                'f' => cmd.format = parseU16(value) orelse return null,
                's' => {
                    const parsed = parseU32(value) orelse return null;
                    cmd.width = parsed;
                    cmd.animation_state = parsed;
                },
                'v' => {
                    const parsed = parseU32(value) orelse return null;
                    cmd.height = parsed;
                    cmd.loop_count = parsed;
                },
                'S' => cmd.data_size = parseU32(value) orelse return null,
                'w' => cmd.source_width = parseU32(value) orelse return null,
                'h' => cmd.source_height = parseU32(value) orelse return null,
                'c' => {
                    const parsed = parseU32(value) orelse return null;
                    cmd.columns = parsed;
                    cmd.current_frame_number = parsed;
                    cmd.base_frame_number = parsed;
                },
                'r' => {
                    const parsed = parseU32(value) orelse return null;
                    cmd.rows = parsed;
                    cmd.edit_frame_number = parsed;
                },
                'O' => cmd.data_offset = parseU32(value) orelse return null,
                'H' => cmd.parent_offset_cols = parseI32(value) orelse return null,
                'V' => cmd.parent_offset_rows = parseI32(value) orelse return null,
                'x' => cmd.x = parseU32(value) orelse return null,
                'y' => cmd.y = parseU32(value) orelse return null,
                'X' => {
                    const parsed = parseU32(value) orelse return null;
                    cmd.cell_x_offset = parsed;
                    cmd.compose_mode = parsed;
                },
                'Y' => {
                    const parsed = parseU32(value) orelse return null;
                    cmd.cell_y_offset = parsed;
                    cmd.background_rgba = parsed;
                },
                'C' => cmd.no_move_cursor = (parseU32(value) orelse return null) != 0,
                'z' => cmd.z = parseI32(value) orelse return null,
                'o' => {
                    cmd.compression = parseFlag(value, "z") orelse return null;
                },
                't' => {
                    cmd.medium = parseFlag(value, "dfst") orelse return null;
                },
                'U' => cmd.unicode_placement = (parseU32(value) orelse return null) != 0,
                'm' => cmd.more_chunks = (parseU32(value) orelse return null) != 0,
                'q' => cmd.quiet = (parseU32(value) orelse return null) != 0,
                'd' => {
                    cmd.delete_target = parseFlag(value, "ACFINPQRXYZacfinpqryz") orelse return null;
                },
                else => return null,
            }
        }
    }
    return cmd;
}

pub fn parseShellMark(payload: []const u8) ?vocabulary.KittyShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    const kind = payload[0];
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D' and metadata.len > 0) std.fmt.parseInt(i32, metadata, 10) catch null else null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

pub fn parseNotification(payload: []const u8) ?vocabulary.KittyNotificationCommand {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    return .{
        .metadata = payload[0..separator],
        .payload = payload[separator + 1 ..],
    };
}

pub fn parsePointerShape(payload: []const u8) vocabulary.KittyPointerShapeCommand {
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

fn parseFlag(value: []const u8, allowed: []const u8) ?u8 {
    if (value.len != 1) return null;
    if (std.mem.indexOfScalar(u8, allowed, value[0]) == null) return null;
    return value[0];
}

fn parseU32(value: []const u8) ?u32 {
    if (value.len == 0) return null;
    for (value) |byte| {
        if (byte < '0' or byte > '9') return null;
    }
    return std.fmt.parseUnsigned(u32, value, 10) catch null;
}

fn parseU16(value: []const u8) ?u16 {
    if (value.len == 0) return null;
    for (value) |byte| {
        if (byte < '0' or byte > '9') return null;
    }
    return std.fmt.parseUnsigned(u16, value, 10) catch null;
}

fn parseI32(value: []const u8) ?i32 {
    if (value.len == 0) return null;
    const digits = if (value[0] == '-') value[1..] else value;
    if (digits.len == 0) return null;
    for (digits) |byte| {
        if (byte < '0' or byte > '9') return null;
    }
    return std.fmt.parseInt(i32, value, 10) catch null;
}
