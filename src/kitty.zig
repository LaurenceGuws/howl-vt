//! Responsibility: own the kitty protocol family surface for vt-core.
//! Ownership: kitty protocol domain owner.
//! Reason: keep kitty protocol state and operations behind a specific sibling owner.

const std = @import("std");
const action_types = @import("interpret/action_types.zig");

const key_mod = @import("kitty/key.zig");
const pointer_mod = @import("kitty/pointer.zig");
const color_mod = @import("kitty/color.zig");
const graphics_mod = @import("kitty/graphics.zig");

const KittyNotificationCommand = action_types.KittyNotificationCommand;
const KittyShellMark = action_types.KittyShellMark;

pub const Kitty = struct {
    pub const Key = key_mod.Key;
    pub const Pointer = pointer_mod.Pointer;
    pub const Color = color_mod.Color;
    pub const Graphics = graphics_mod.Graphics;

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
};
