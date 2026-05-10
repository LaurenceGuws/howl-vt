//! Responsibility: own the kitty protocol family surface for vt-core.
//! Ownership: kitty protocol domain owner.
//! Reason: keep kitty protocol state and operations behind a specific sibling owner.

const std = @import("std");
const types = @import("../interpret/actions/types.zig");
const actions = @import("../interpret/actions/actions.zig");

const key_mod = @import("key.zig");
const pointer_mod = @import("pointer.zig");
const color_mod = @import("color.zig");
const graphics_mod = @import("graphics.zig");

const KittyNotificationCommand = types.KittyNotificationCommand;
const KittyShellMark = types.KittyShellMark;
const KittyAction = actions.KittyAction;

pub const Key = key_mod;
pub const Pointer = pointer_mod;
pub const Color = color_mod;
pub const Graphics = graphics_mod;

pub fn apply(vt: anytype, action: KittyAction) void {
    const active_screen = vt.kitty.activeScreen(vt.screen_state.alt_active);
    const active_screen_const = vt.kitty.activeScreenConst(vt.screen_state.alt_active);
    switch (action) {
        .kitty_keyboard_set => |req| active_screen.keyboard.set(req.flags, req.mode),
        .kitty_keyboard_query => active_screen_const.keyboard.appendReport(vt.allocator, &vt.host.pending_output, vt.encode.buf[0..]),
        .kitty_keyboard_push => |flags| active_screen.keyboard.push(flags),
        .kitty_keyboard_pop => |count| active_screen.keyboard.pop(count),
        .kitty_shell_mark => |mark| setShellMark(vt.allocator, &vt.kitty.global.shell_mark, mark),
        .kitty_notification => |notification| appendNotification(vt.allocator, &vt.kitty.global.notifications, notification),
        .kitty_pointer_shape => |cmd| {
            switch (cmd.action) {
                '<' => active_screen.pointer.pop(),
                '>' => active_screen.pointer.push(cmd.names),
                '?' => active_screen_const.pointer.appendQuery(vt.allocator, &vt.host.pending_output, cmd.names),
                else => active_screen.pointer.set(cmd.names),
            }
        },
        .kitty_color_stack => |cmd| {
            switch (cmd) {
                .push => Color.pushState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
                .pop => Color.popState(&vt.kitty.global.color_stack, &vt.host.colors, &vt.kitty.global.color_stack_depth),
            }
        },
        .kitty_multiple_cursor => |cmd| switch (cmd) {
            .support_query => vt.host.pending_output.appendSlice(vt.allocator, "\x1b[>1;2;3;29;30;40;100;101 q") catch {},
            .clear_all => active_screen.multiple_cursor_count = 0,
            .cursor_query => vt.host.pending_output.appendSlice(vt.allocator, "\x1b[>100 q") catch {},
            .color_query => vt.host.pending_output.appendSlice(vt.allocator, "\x1b[>101;30:0;40:0 q") catch {},
        },
        .kitty_file_transfer => |payload| setOptionalPayload(vt.allocator, &vt.kitty.global.file_transfer_request, payload),
        .kitty_text_size => |payload| setOptionalPayload(vt.allocator, &vt.kitty.global.text_size_request, payload),
        .kitty_graphics => |cmd| {
            const cursor = vt.screen_state.activeConst();
            vt.kitty.global.graphics.handle(vt.allocator, .{
                .row = cursor.cursor_row,
                .col = cursor.cursor_col,
            }, &vt.host.pending_output, vt.encode.buf[0..], cmd);
        },
    }
}

pub const ScreenState = struct {
    keyboard: Key.Stack = .{},
    pointer: Pointer.Stack = .{},
    multiple_cursor_count: u16 = 0,
};

pub const GlobalState = struct {
    shell_mark: ShellMark = .{},
    notifications: std.ArrayList(NotificationRequest) = .empty,
    color_stack_depth: u16 = 0,
    color_stack: Color.Stack = .{},
    graphics: Graphics.State = .{},
    file_transfer_request: ?[]u8 = null,
    text_size_request: ?[]u8 = null,

    pub fn deinit(self: *GlobalState, allocator: std.mem.Allocator) void {
        allocator.free(self.shell_mark.metadata);
        for (self.notifications.items) |notification| {
            allocator.free(notification.metadata);
            allocator.free(notification.payload);
        }
        self.notifications.deinit(allocator);
        self.graphics.deinit(allocator);
        if (self.file_transfer_request) |payload| allocator.free(payload);
        if (self.text_size_request) |payload| allocator.free(payload);
    }
};

pub const ShellMark = struct {
    kind: u8 = 0,
    status: ?i32 = null,
    metadata: []u8 = &[_]u8{},
};

pub const NotificationRequest = struct {
    metadata: []u8,
    payload: []u8,
};

pub fn setShellMark(allocator: std.mem.Allocator, current: *ShellMark, mark: KittyShellMark) void {
    allocator.free(current.metadata);
    const owned = allocator.dupe(u8, mark.metadata) catch {
        current.* = .{};
        return;
    };
    current.* = .{ .kind = mark.kind, .status = mark.status, .metadata = owned };
}

pub fn appendNotification(allocator: std.mem.Allocator, notifications: *std.ArrayList(NotificationRequest), notification: KittyNotificationCommand) void {
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
