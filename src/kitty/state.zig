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

    /// Return the current shell mark; its metadata borrows GlobalState storage.
    pub fn shellMark(self: *const GlobalState) ShellMark {
        return self.shell_mark;
    }

    /// Return the bounded number of retained notification requests.
    pub fn notificationCount(self: *const GlobalState) NotificationIndex {
        std.debug.assert(self.notifications.items.len <= std.math.maxInt(NotificationIndex));
        return @intCast(self.notifications.items.len);
    }

    /// Return a notification whose slices borrow GlobalState storage, or null when out of bounds.
    pub fn notificationAt(self: *const GlobalState, idx: NotificationIndex) ?NotificationRequest {
        if (idx >= self.notificationCount()) return null;
        return self.notifications.items[@intCast(idx)];
    }

    /// Borrow the retained file-transfer request until GlobalState mutation.
    pub fn fileTransferRequest(self: *const GlobalState) ?[]const u8 {
        return self.file_transfer_request;
    }

    /// Borrow the retained text-size request until GlobalState mutation.
    pub fn textSizeRequest(self: *const GlobalState) ?[]const u8 {
        return self.text_size_request;
    }

    /// Return the current depth of the bounded terminal-color stack.
    pub fn colorStackDepth(self: *const GlobalState) u16 {
        return self.color_stack_depth;
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

    /// Borrow the active screen's pointer name until its pointer stack mutates.
    pub fn pointerShape(self: *const KittyState, alt_active: bool) []const u8 {
        return self.activeScreenConst(alt_active).pointer.currentName();
    }

    /// Return the active screen's retained multiple-cursor count.
    pub fn multipleCursorCount(self: *const KittyState, alt_active: bool) u16 {
        return self.activeScreenConst(alt_active).multiple_cursor_count;
    }

    pub fn resetTerminalState(self: *KittyState, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.main.pointer.len = 0;
        self.alt.pointer.len = 0;
        self.global.color_stack_depth = 0;
    }
};

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
