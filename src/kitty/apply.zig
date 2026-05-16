const std = @import("std");
const input = @import("../input.zig");
const vocabulary = @import("../action/vocabulary.zig");
const types = @import("types.zig");

const KittyNotificationCommand = vocabulary.KittyNotificationCommand;
const KittyShellMark = vocabulary.KittyShellMark;
const KittyAction = vocabulary.KittyAction;

pub fn apply(vt: anytype, action: KittyAction) void {
    var scratch: input.Scratch = .{};
    const allocator = vt.parser_state.getAllocator();
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (action) {
        .kitty_keyboard_set => |req| active_screen.keyboard.set(req.flags, req.mode),
        .kitty_keyboard_query => active_screen_const.keyboard.appendReport(allocator, &vt.host.pending_output, scratch.buf[0..]),
        .kitty_keyboard_push => |flags| active_screen.keyboard.push(flags),
        .kitty_keyboard_pop => |count| active_screen.keyboard.pop(count),
        .kitty_shell_mark => |mark| setShellMark(allocator, &vt.kitty.global.shell_mark, mark),
        .kitty_notification => |notification| appendNotification(allocator, &vt.kitty.global.notifications, notification),
        .kitty_pointer_shape => |cmd| {
            switch (cmd.action) {
                '<' => active_screen.pointer.pop(),
                '>' => active_screen.pointer.push(cmd.names),
                '?' => active_screen_const.pointer.appendQuery(allocator, &vt.host.pending_output, cmd.names),
                else => active_screen.pointer.set(cmd.names),
            }
        },
        .kitty_color_stack => |cmd| {
            switch (cmd) {
                .push => types.Color.pushState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
                .pop => types.Color.popState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
            }
        },
        .kitty_multiple_cursor => |cmd| switch (cmd) {
            .support_query => vt.host.pending_output.appendSlice(allocator, "\x1b[>1;2;3;29;30;40;100;101 q") catch {},
            .clear_all => active_screen.multiple_cursor_count = 0,
            .cursor_query => vt.host.pending_output.appendSlice(allocator, "\x1b[>100 q") catch {},
            .color_query => vt.host.pending_output.appendSlice(allocator, "\x1b[>101;30:0;40:0 q") catch {},
        },
        .kitty_file_transfer => |payload| setOptionalPayload(allocator, &vt.kitty.global.file_transfer_request, payload),
        .kitty_text_size => |payload| setOptionalPayload(allocator, &vt.kitty.global.text_size_request, payload),
        .kitty_graphics => |cmd| {
            const cursor = vt.screen_state.activeConst();
            vt.kitty.global.graphics.handle(allocator, .{
                .row = cursor.cursor_row,
                .col = cursor.cursor_col,
            }, &vt.host.pending_output, scratch.buf[0..], cmd);
        },
    }
}

pub fn setShellMark(allocator: std.mem.Allocator, current: *types.ShellMark, mark: KittyShellMark) void {
    allocator.free(current.metadata);
    const owned = allocator.dupe(u8, mark.metadata) catch {
        current.* = .{};
        return;
    };
    current.* = .{ .kind = mark.kind, .status = mark.status, .metadata = owned };
}

pub fn appendNotification(allocator: std.mem.Allocator, notifications: *std.ArrayList(types.NotificationRequest), notification: KittyNotificationCommand) void {
    const metadata = allocator.dupe(u8, notification.metadata) catch return;
    errdefer allocator.free(metadata);
    const payload = allocator.dupe(u8, notification.payload) catch return;
    notifications.append(allocator, .{ .metadata = metadata, .payload = payload }) catch {
        allocator.free(metadata);
        allocator.free(payload);
    };
}

pub fn setOptionalPayload(allocator: std.mem.Allocator, slot: *?[]u8, payload: []const u8) void {
    if (slot.*) |old| allocator.free(old);
    slot.* = allocator.dupe(u8, payload) catch null;
}
