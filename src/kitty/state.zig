const std = @import("std");
const KittyNs = @import("types.zig");

const NotificationIndex = u32;

pub const State = struct {
    main: KittyNs.ScreenState = .{},
    alt: KittyNs.ScreenState = .{},
    global: KittyNs.GlobalState = .{},

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        self.global.deinit(allocator);
    }

    pub fn activeScreen(self: *State, alt_active: bool) *KittyNs.ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    pub fn activeScreenConst(self: *const State, alt_active: bool) *const KittyNs.ScreenState {
        return if (alt_active) &self.alt else &self.main;
    }

    pub fn resetTerminalState(self: *State) void {
        self.main.pointer.len = 0;
        self.alt.pointer.len = 0;
        self.global.color_stack_depth = 0;
    }
};

pub fn shellMark(vt: anytype) KittyNs.ShellMark {
    return vt.kitty.global.shell_mark;
}

pub fn notificationCount(vt: anytype) NotificationIndex {
    std.debug.assert(vt.kitty.global.notifications.items.len <= std.math.maxInt(NotificationIndex));
    return @intCast(vt.kitty.global.notifications.items.len);
}

pub fn notificationAt(vt: anytype, idx: NotificationIndex) ?KittyNs.NotificationRequest {
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

pub fn graphicsImageCount(vt: anytype) KittyNs.Graphics.Count {
    return vt.kitty.global.graphics.imageCount();
}

pub fn graphicsImageAt(vt: anytype, idx: KittyNs.Graphics.Index) ?KittyNs.Graphics.Image {
    return vt.kitty.global.graphics.imageAt(idx);
}

pub fn graphicsPlacementCount(vt: anytype) KittyNs.Graphics.Count {
    return vt.kitty.global.graphics.placementCount();
}

pub fn graphicsPlacementAt(vt: anytype, idx: KittyNs.Graphics.Index) ?KittyNs.Graphics.Placement {
    return vt.kitty.global.graphics.placementAt(idx);
}

pub fn graphicsFrameCount(vt: anytype) KittyNs.Graphics.Count {
    return vt.kitty.global.graphics.frameCount();
}

pub fn graphicsFrameAt(vt: anytype, idx: KittyNs.Graphics.Index) ?KittyNs.Graphics.Frame {
    return vt.kitty.global.graphics.frameAt(idx);
}
