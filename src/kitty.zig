//! Responsibility: own the kitty protocol family surface for vt-core.
//! Ownership: kitty protocol domain owner.
//! Reason: keep kitty protocol state and operations behind a specific sibling owner.

const std = @import("std");

const key_mod = @import("kitty/key.zig");
const pointer_mod = @import("kitty/pointer.zig");
const color_mod = @import("kitty/color.zig");
const graphics_mod = @import("kitty/graphics.zig");

pub const Kitty = struct {
    pub const Key = key_mod.Key;
    pub const Pointer = pointer_mod.Pointer;
    pub const Color = color_mod.Color;
    pub const Graphics = graphics_mod.Graphics;

    pub const ScreenState = struct {
        keyboard: Key.Stack = .{},
        pointer: Pointer.Stack = .{},
    };

    pub const GlobalState = struct {
        shell_mark: ShellMark = .{},
        notifications: std.ArrayList(NotificationRequest) = .empty,
        color_stack_depth: u16 = 0,
        color_stack: Color.Stack = .{},
        graphics: Graphics.State = .{},

        pub fn deinit(self: *GlobalState, allocator: std.mem.Allocator) void {
            allocator.free(self.shell_mark.metadata);
            for (self.notifications.items) |notification| {
                allocator.free(notification.metadata);
                allocator.free(notification.payload);
            }
            self.notifications.deinit(allocator);
            self.graphics.deinit(allocator);
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

    pub fn setShellMark(allocator: std.mem.Allocator, current: *ShellMark, mark: anytype) void {
        allocator.free(current.metadata);
        const owned = allocator.dupe(u8, mark.metadata) catch {
            current.* = .{};
            return;
        };
        current.* = .{ .kind = mark.kind, .status = mark.status, .metadata = owned };
    }

    pub fn appendNotification(allocator: std.mem.Allocator, notifications: *std.ArrayList(NotificationRequest), notification: anytype) void {
        const metadata = allocator.dupe(u8, notification.metadata) catch return;
        errdefer allocator.free(metadata);
        const payload = allocator.dupe(u8, notification.payload) catch return;
        notifications.append(allocator, .{ .metadata = metadata, .payload = payload }) catch {
            allocator.free(metadata);
            allocator.free(payload);
        };
    }
};
