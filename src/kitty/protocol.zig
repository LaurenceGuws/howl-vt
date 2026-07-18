//! Parses Kitty OSC payloads into typed semantic command values.

const std = @import("std");

/// Borrows one parsed shell-integration mark and its optional exit status.
pub const KittyShellMark = struct {
    kind: u8,
    status: ?i32,
    metadata: []const u8,
};

/// Borrows parsed notification metadata and payload slices.
pub const KittyNotificationCommand = struct {
    metadata: []const u8,
    payload: []const u8,
};

/// Borrows a pointer-shape action byte and comma-separated names.
pub const KittyPointerShapeCommand = struct {
    action: u8,
    names: []const u8,
};

/// Selects a Kitty terminal-color stack push or pop.
pub const KittyColorStackCommand = enum {
    push,
    pop,
};

/// Selects one supported Kitty multiple-cursor request.
pub const KittyMultipleCursorCommand = enum {
    support_query,
    clear_all,
    cursor_query,
    color_query,
};

/// Parses a shell mark from borrowed OSC 133 payload bytes.
pub fn parseShellMark(payload: []const u8) ?KittyShellMark {
    if (payload.len == 0) return null;
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse payload.len;
    const kind = payload[0];
    const metadata = if (separator < payload.len) payload[separator + 1 ..] else "";
    const status = if (kind == 'D' and metadata.len > 0) std.fmt.parseInt(i32, metadata, 10) catch null else null;
    return .{ .kind = kind, .status = status, .metadata = metadata };
}

/// Splits one borrowed OSC 99 payload into metadata and body.
pub fn parseNotification(payload: []const u8) ?KittyNotificationCommand {
    const separator = std.mem.indexOfScalar(u8, payload, ';') orelse return null;
    return .{
        .metadata = payload[0..separator],
        .payload = payload[separator + 1 ..],
    };
}

/// Separates one OSC 22 action byte from its borrowed names.
pub fn parsePointerShape(payload: []const u8) KittyPointerShapeCommand {
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
