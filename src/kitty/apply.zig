const std = @import("std");
const kitty_color = @import("color.zig");
const kitty_protocol = @import("protocol.zig");
const kitty_state = @import("state.zig");
const input_encode = @import("../input/encode.zig");
const host_state = @import("../host_state.zig");
const semantic_event = @import("../semantic_event.zig");
const terminal_mod = @import("../terminal.zig");

const KittyNotificationCommand = kitty_protocol.KittyNotificationCommand;
const KittyShellMark = kitty_protocol.KittyShellMark;
const Terminal = terminal_mod.Terminal;
const SemanticEvent = semantic_event.SemanticEvent;

/// Apply one Kitty-directed semantic event to terminal-owned Kitty state.
pub fn apply(vt: *Terminal, event: SemanticEvent) host_state.ApplyError!void {
    var scratch: input_encode.Scratch = .{};
    const allocator = vt.allocator;
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (event) {
        .kitty_keyboard_set => |req| {
            active_screen.keyboard.set(req.flags, req.mode);
        },
        .kitty_keyboard_query => {
            try active_screen_const.keyboard.appendReport(allocator, &vt.host.pending_output, scratch.buf[0..]);
        },
        .kitty_keyboard_push => |flags| {
            active_screen.keyboard.push(flags);
        },
        .kitty_keyboard_pop => |count| {
            active_screen.keyboard.pop(count);
        },
        .kitty_shell_mark => |mark| {
            try setShellMark(allocator, &vt.kitty.global.shell_mark, mark);
        },
        .kitty_notification => |notification| {
            try appendNotification(allocator, &vt.kitty.global.notifications, notification);
        },
        .kitty_pointer_shape => |cmd| {
            switch (cmd.action) {
                '<' => active_screen.pointer.pop(),
                '>' => active_screen.pointer.push(cmd.names),
                '?' => try active_screen_const.pointer.appendQuery(allocator, &vt.host.pending_output, cmd.names),
                else => active_screen.pointer.set(cmd.names),
            }
        },
        .kitty_color_stack => |cmd| {
            switch (cmd) {
                .push => kitty_color.pushState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
                .pop => kitty_color.popState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
            }
        },
        .kitty_multiple_cursor => |cmd| {
            switch (cmd) {
                .support_query => try vt.host.appendPendingOutput("\x1b[>1;2;3;29;30;40;100;101 q"),
                .clear_all => active_screen.multiple_cursor_count = 0,
                .cursor_query => try vt.host.appendPendingOutput("\x1b[>100 q"),
                .color_query => try vt.host.appendPendingOutput("\x1b[>101;30:0;40:0 q"),
            }
        },
        .kitty_file_transfer => |payload| {
            try setOptionalPayload(
                allocator,
                &vt.kitty.global.file_transfer_request,
                payload,
                kitty_state.file_transfer_request_max_bytes,
            );
        },
        .kitty_text_size => |payload| {
            try setOptionalPayload(
                allocator,
                &vt.kitty.global.text_size_request,
                payload,
                kitty_state.text_size_request_max_bytes,
            );
        },
        else => unreachable,
    }
}

pub fn setShellMark(allocator: std.mem.Allocator, current: *kitty_state.ShellMark, mark: KittyShellMark) host_state.ApplyError!void {
    const owned = try replaceOwned(allocator, mark.metadata, kitty_state.shell_mark_max_bytes);
    allocator.free(current.metadata);
    current.* = .{ .kind = mark.kind, .status = mark.status, .metadata = owned };
}

pub fn appendNotification(allocator: std.mem.Allocator, notifications: *std.ArrayList(kitty_state.NotificationRequest), notification: KittyNotificationCommand) host_state.ApplyError!void {
    if (notifications.items.len >= kitty_state.notification_max_count) return error.ConsequenceLimit;
    try ensureRetainedBound(host_state.byteCount(notification.metadata), kitty_state.notification_part_max_bytes);
    try ensureRetainedBound(host_state.byteCount(notification.payload), kitty_state.notification_part_max_bytes);
    const metadata = try allocator.dupe(u8, notification.metadata);
    errdefer allocator.free(metadata);
    const payload = try allocator.dupe(u8, notification.payload);
    errdefer allocator.free(payload);
    try notifications.append(allocator, .{ .metadata = metadata, .payload = payload });
}

pub fn setOptionalPayload(allocator: std.mem.Allocator, slot: *?[]u8, payload: []const u8, max_len: u32) host_state.ApplyError!void {
    const owned = try replaceOwned(allocator, payload, max_len);
    if (slot.*) |old| allocator.free(old);
    slot.* = owned;
}

fn replaceOwned(allocator: std.mem.Allocator, next: []const u8, max_len: u32) host_state.ApplyError![]u8 {
    try ensureRetainedBound(host_state.byteCount(next), max_len);
    const owned = try allocator.dupe(u8, next);
    return owned;
}

fn ensureRetainedBound(len: u32, max_len: u32) host_state.ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}

test "Kitty retained payloads enforce their protocol boundaries" {
    const allocator = std.testing.allocator;
    var state: kitty_state.GlobalState = .{};
    defer state.deinit(allocator);

    const metadata = try allocator.alloc(u8, kitty_state.notification_part_max_bytes + 1);
    defer allocator.free(metadata);
    @memset(metadata, 'm');

    try setShellMark(allocator, &state.shell_mark, .{
        .kind = 'a',
        .status = null,
        .metadata = metadata[0 .. kitty_state.shell_mark_max_bytes - 1],
    });
    try setShellMark(allocator, &state.shell_mark, .{
        .kind = 'A',
        .status = null,
        .metadata = metadata[0..kitty_state.shell_mark_max_bytes],
    });
    try std.testing.expectError(
        error.ConsequenceLimit,
        setShellMark(allocator, &state.shell_mark, .{
            .kind = 'B',
            .status = null,
            .metadata = metadata,
        }),
    );
    try std.testing.expectEqual(@as(u8, 'A'), state.shell_mark.kind);

    try appendNotification(allocator, &state.notifications, .{
        .metadata = metadata[0 .. kitty_state.notification_part_max_bytes - 1],
        .payload = "",
    });
    try appendNotification(allocator, &state.notifications, .{
        .metadata = metadata[0..kitty_state.notification_part_max_bytes],
        .payload = "",
    });
    try appendNotification(allocator, &state.notifications, .{
        .metadata = "",
        .payload = metadata[0..kitty_state.notification_part_max_bytes],
    });
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendNotification(allocator, &state.notifications, .{
            .metadata = metadata,
            .payload = "",
        }),
    );
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendNotification(allocator, &state.notifications, .{
            .metadata = "",
            .payload = metadata,
        }),
    );
    try std.testing.expectEqual(@as(usize, 3), state.notifications.items.len);

    const chunk = try allocator.alloc(u8, kitty_state.file_transfer_request_max_bytes + 1);
    defer allocator.free(chunk);
    @memset(chunk, 'c');
    try expectOptionalPayloadBoundary(
        allocator,
        &state.file_transfer_request,
        chunk,
        kitty_state.file_transfer_request_max_bytes,
    );
    try expectOptionalPayloadBoundary(
        allocator,
        &state.text_size_request,
        metadata,
        kitty_state.text_size_request_max_bytes,
    );
}

fn expectOptionalPayloadBoundary(
    allocator: std.mem.Allocator,
    slot: *?[]u8,
    bytes: []const u8,
    max_len: u32,
) !void {
    try setOptionalPayload(allocator, slot, bytes[0 .. max_len - 1], max_len);
    try setOptionalPayload(allocator, slot, bytes[0..max_len], max_len);
    try std.testing.expectError(
        error.ConsequenceLimit,
        setOptionalPayload(allocator, slot, bytes[0 .. max_len + 1], max_len),
    );
    try std.testing.expectEqual(max_len, host_state.byteCount(slot.*.?));
}

test "Kitty notification retention stops at Howl's local count bound" {
    const allocator = std.testing.allocator;
    var state: kitty_state.GlobalState = .{};
    defer state.deinit(allocator);

    var count: u32 = 0;
    while (count < kitty_state.notification_max_count) : (count += 1) {
        try appendNotification(allocator, &state.notifications, .{
            .metadata = "",
            .payload = "",
        });
    }
    try std.testing.expectError(
        error.ConsequenceLimit,
        appendNotification(allocator, &state.notifications, .{
            .metadata = "",
            .payload = "",
        }),
    );
    try std.testing.expectEqual(kitty_state.notification_max_count, state.notificationCount());
}
