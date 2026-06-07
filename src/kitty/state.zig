const std = @import("std");
const color = @import("color.zig");
const key = @import("key.zig");
const pointer = @import("pointer.zig");

const NotificationIndex = u32;

pub const ScreenState = struct {
    keyboard: key.Stack = .{},
    pointer: pointer.Stack = .{},
    multiple_cursor_count: u16 = 0,
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
    color_stack: color.Stack = .{},
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

pub const KittyState = struct {
    main: ScreenState = .{},
    alt: ScreenState = .{},
    global: GlobalState = .{},

    pub fn deinit(self: *KittyState, allocator: std.mem.Allocator) void {
        self.global.deinit(allocator);
    }

    pub fn activeScreen(self: *KittyState, alt_active: bool) *ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    pub fn activeScreenConst(self: *const KittyState, alt_active: bool) *const ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    pub fn resetTerminalState(self: *KittyState, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.main.pointer.len = 0;
        self.alt.pointer.len = 0;
        self.global.color_stack_depth = 0;
    }
};

pub fn shellMark(vt: anytype) ShellMark {
    return vt.kitty.global.shell_mark;
}

pub fn notificationCount(vt: anytype) NotificationIndex {
    std.debug.assert(vt.kitty.global.notifications.items.len <= std.math.maxInt(NotificationIndex));
    return @intCast(vt.kitty.global.notifications.items.len);
}

pub fn notificationAt(vt: anytype, idx: NotificationIndex) ?NotificationRequest {
    if (idx >= notificationCount(vt)) return null;
    return vt.kitty.global.notifications.items[@intCast(idx)];
}

pub fn fileTransferRequest(vt: anytype) ?[]const u8 {
    return vt.kitty.global.file_transfer_request;
}

pub fn textSizeRequest(vt: anytype) ?[]const u8 {
    return vt.kitty.global.text_size_request;
}

pub fn pointerShape(vt: anytype) []const u8 {
    return vt.kitty.activeScreenConst(vt.screen_state.alt_active).pointer.currentName();
}

pub fn multipleCursorCount(vt: anytype) u16 {
    return vt.kitty.activeScreenConst(vt.screen_state.alt_active).multiple_cursor_count;
}

pub fn colorStackDepth(vt: anytype) u16 {
    return vt.kitty.global.color_stack_depth;
}

test "global state deinit releases notification storage" {
    const allocator = std.testing.allocator;
    var state: GlobalState = .{};
    defer state.deinit(allocator);

    const metadata = try allocator.dupe(u8, "meta");
    errdefer allocator.free(metadata);
    const payload = try allocator.dupe(u8, "payload");
    errdefer allocator.free(payload);
    try state.notifications.append(allocator, .{
        .metadata = metadata,
        .payload = payload,
    });

    try std.testing.expectEqual(@as(usize, 1), state.notifications.items.len);
}
