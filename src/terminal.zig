const std = @import("std");
const mode = @import("control/mode.zig");
const screen = @import("screen.zig");
const host_state = @import("host/state.zig");
const kitty_state = @import("kitty/state.zig");
const parser_mod = @import("parser.zig");
const screen_set = @import("screen_set.zig");
const action = @import("action.zig");

const ScreenNs = screen.Screen;
const TerminalModeNs = mode;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    const HostState = host_state.State;
    const KittyState = kitty_state.State;
    const ParserQueue = parser_mod.Queue;

    const ScreenSet = screen_set.Set;

    allocator: std.mem.Allocator,
    parser: ParserQueue,
    screen_state: ScreenSet,
    modes: TerminalModeNs.State = .{},
    kitty: KittyState = .{},
    xtchecksum_flags: u16 = 0,
    host: HostState,
    dirty_generation: u64 = 1,

    /// Initialize Terminal without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        var parser = try ParserQueue.init(allocator);
        errdefer parser.deinit();
        const state = ScreenNs.init(rows, cols);
        const alt_state = ScreenNs.init(rows, cols);
        return Terminal{
            .allocator = allocator,
            .parser = parser,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        var parser = try ParserQueue.init(allocator);
        errdefer parser.deinit();
        var state = try ScreenNs.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .parser = parser,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Terminal {
        var parser = try ParserQueue.init(allocator);
        errdefer parser.deinit();
        var state = try ScreenNs.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .parser = parser,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Release Terminal resources.
    pub fn deinit(self: *Terminal) void {
        const allocator = self.allocator;
        self.host.deinit(allocator);
        self.kitty.deinit(allocator);
        self.screen_state.deinit(allocator);
        self.parser.deinit();
    }

};

test "terminal tracks synchronized output private mode" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    try vt.parser.feedSlice("\x1b[?2026h");
    action.apply(&vt);
    try std.testing.expect(vt.modes.synchronized_output);

    try vt.parser.feedSlice("\x1b[?2026l");
    action.apply(&vt);
    try std.testing.expect(!vt.modes.synchronized_output);
}

test "terminal visible view projects scrollback rows" {
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();

    try vt.parser.feedSlice("aa\r\nbb\r\ncc");
    action.apply(&vt);

    const live = screen_set.visibleView(&vt.screen_state, .{});
    try std.testing.expectEqual(0, live.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'b'), live.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), live.cellAt(1, 0));

    const scrolled = screen_set.visibleView(&vt.screen_state, .{ .scrollback_offset = 1 });
    try std.testing.expectEqual(1, scrolled.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'a'), scrolled.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), scrolled.cellAt(1, 0));
    try std.testing.expectEqual(2, scrolled.rowDepth(0));
    try std.testing.expectEqual(1, scrolled.rowDepth(1));
}

test {
    _ = @import("test/queue_regression.zig");
    _ = @import("test/pty_feed_record.zig");
    _ = @import("test/terminal_graphics.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/action_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/terminal_end_to_end.zig");
}
