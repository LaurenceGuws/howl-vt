const std = @import("std");
const color_mod = @import("color.zig");
const graphics_mod = @import("graphics.zig");
const key_mod = @import("key.zig");
const pointer_mod = @import("pointer.zig");

pub const Key = key_mod;
pub const Pointer = pointer_mod;
pub const Color = color_mod;
pub const Graphics = graphics_mod;

pub const ScreenState = struct {
    keyboard: Key.Stack = .{},
    pointer: Pointer.Stack = .{},
    multiple_cursor_count: u16 = 0,
    graphics: Graphics.State = .{},

    pub fn deinit(self: *ScreenState, allocator: std.mem.Allocator) void {
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

pub const GlobalState = struct {
    shell_mark: ShellMark = .{},
    notifications: std.ArrayList(NotificationRequest) = .empty,
    color_stack_depth: u16 = 0,
    color_stack: Color.Stack = .{},
    file_transfer_request: ?[]u8 = null,
    text_size_request: ?[]u8 = null,

    pub fn deinit(self: *GlobalState, allocator: std.mem.Allocator) void {
        allocator.free(self.shell_mark.metadata);
        for (self.notifications.items) |notification| {
            allocator.free(notification.metadata);
            allocator.free(notification.payload);
        }
        self.notifications.deinit(allocator);
        if (self.file_transfer_request) |payload| allocator.free(payload);
        if (self.text_size_request) |payload| allocator.free(payload);
    }
};
