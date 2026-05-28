const std = @import("std");
const input = @import("../input.zig");
const vocabulary = @import("../action/vocabulary.zig");
const types = @import("types.zig");
const host_state = @import("../host/state.zig");

const KittyNotificationCommand = vocabulary.KittyNotificationCommand;
const KittyShellMark = vocabulary.KittyShellMark;
const KittyAction = vocabulary.KittyAction;

pub fn apply(vt: anytype, action: KittyAction) host_state.ApplyError!bool {
    var scratch: input.Scratch = .{};
    const allocator = vt.allocator;
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (action) {
        .kitty_keyboard_set => |req| {
            active_screen.keyboard.set(req.flags, req.mode);
            return true;
        },
        .kitty_keyboard_query => {
            try active_screen_const.keyboard.appendReport(allocator, &vt.host.pending_output, scratch.buf[0..]);
            return true;
        },
        .kitty_keyboard_push => |flags| {
            active_screen.keyboard.push(flags);
            return true;
        },
        .kitty_keyboard_pop => |count| {
            active_screen.keyboard.pop(count);
            return true;
        },
        .kitty_shell_mark => |mark| {
            try setShellMark(allocator, &vt.kitty.global.shell_mark, mark);
            return true;
        },
        .kitty_notification => |notification| {
            try appendNotification(allocator, &vt.kitty.global.notifications, notification);
            return true;
        },
        .kitty_pointer_shape => |cmd| {
            switch (cmd.action) {
                '<' => active_screen.pointer.pop(),
                '>' => active_screen.pointer.push(cmd.names),
                '?' => try active_screen_const.pointer.appendQuery(allocator, &vt.host.pending_output, cmd.names),
                else => active_screen.pointer.set(cmd.names),
            }
            return true;
        },
        .kitty_color_stack => |cmd| {
            switch (cmd) {
                .push => types.Color.pushState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
                .pop => types.Color.popState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
            }
            return true;
        },
        .kitty_multiple_cursor => |cmd| {
            switch (cmd) {
                .support_query => try host_state.appendPendingOutput(vt, "\x1b[>1;2;3;29;30;40;100;101 q"),
                .clear_all => active_screen.multiple_cursor_count = 0,
                .cursor_query => try host_state.appendPendingOutput(vt, "\x1b[>100 q"),
                .color_query => try host_state.appendPendingOutput(vt, "\x1b[>101;30:0;40:0 q"),
            }
            return true;
        },
        .kitty_file_transfer => |payload| {
            try setOptionalPayload(allocator, &vt.kitty.global.file_transfer_request, payload);
            return true;
        },
        .kitty_text_size => |payload| {
            try setOptionalPayload(allocator, &vt.kitty.global.text_size_request, payload);
            return true;
        },
        .kitty_graphics => |cmd| {
            const cursor = vt.screen_state.activeConst();
            const graphics = vt.kitty.activeGraphics(vt.screen_state.alt_active);
            const result = try graphics.handle(allocator, cursor, .{
                .row = cursor.cursor_row,
                .col = cursor.cursor_col,
                .screen_rows = cursor.rows,
            }, cursor.cellPixelSize(), &vt.host.pending_output, scratch.buf[0..], cmd);
            if (result.move) |move| {
                applyPlacementCursorMove(vt.screen_state.active(), move.cols, move.rows);
            }
            return result.changed;
        },
    }
}

fn applyPlacementCursorMove(screen: anytype, cols: u32, rows: u32) void {
    screen.wrap_pending = false;
    screen.cursor_col = @intCast(@min(@as(u32, screen.rightBoundary()), @as(u32, screen.cursor_col) + cols));
    screen.cursor_row = @intCast(@min(@as(u32, screen.rows -| 1), @as(u32, screen.cursor_row) + rows));
}

pub fn setShellMark(allocator: std.mem.Allocator, current: *types.ShellMark, mark: KittyShellMark) host_state.ApplyError!void {
    const owned = try replaceOwned(allocator, mark.metadata, host_state.retained_metadata_max_bytes);
    allocator.free(current.metadata);
    current.* = .{ .kind = mark.kind, .status = mark.status, .metadata = owned };
}

pub fn appendNotification(allocator: std.mem.Allocator, notifications: *std.ArrayList(types.NotificationRequest), notification: KittyNotificationCommand) host_state.ApplyError!void {
    try ensureRetainedBound(host_state.count32(notification.metadata), host_state.retained_metadata_max_bytes);
    try ensureRetainedBound(host_state.count32(notification.payload), host_state.retained_metadata_max_bytes);
    const metadata = try allocator.dupe(u8, notification.metadata);
    errdefer allocator.free(metadata);
    const payload = try allocator.dupe(u8, notification.payload);
    errdefer allocator.free(payload);
    try notifications.append(allocator, .{ .metadata = metadata, .payload = payload });
}

pub fn setOptionalPayload(allocator: std.mem.Allocator, slot: *?[]u8, payload: []const u8) host_state.ApplyError!void {
    const owned = try replaceOwned(allocator, payload, host_state.retained_payload_max_bytes);
    if (slot.*) |old| allocator.free(old);
    slot.* = owned;
}

fn replaceOwned(allocator: std.mem.Allocator, next: []const u8, max_len: u32) host_state.ApplyError![]u8 {
    try ensureRetainedBound(host_state.count32(next), max_len);
    const owned = try allocator.dupe(u8, next);
    return owned;
}

fn ensureRetainedBound(len: u32, max_len: u32) host_state.ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}
