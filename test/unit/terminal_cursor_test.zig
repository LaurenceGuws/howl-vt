const std = @import("std");
const terminal_mod = @import("../../src/terminal.zig");
const screen_mod = @import("../../src/screen.zig");
const screen_set = @import("../../src/screen_set.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;
const Screen = screen_mod.Screen;
const StreamHarness = stream_harness.Harness;

fn active(terminal: *const Terminal) *const Screen {
    return terminal.screen_state.activeConst();
}

fn view(terminal: *const Terminal) screen_set.View {
    return screen_set.visibleView(&terminal.screen_state, 0);
}

test "terminal cursor: save restore is terminal-owned per active bank" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[2;6H\x1b[4 q\x1b7\x1b[1;1H\x1b[1 q\x1b8");
    try std.testing.expectEqual(@as(u16, 1), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 5), active(&terminal).cursor.col);
    try std.testing.expectEqual(.underline, active(&terminal).cursor.effective_shape);
    try std.testing.expect(!active(&terminal).cursor.blink_intent);
}

test "terminal cursor: restore without prior save homes and clears charset state only" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[?6h\x1b)0\x1b8");
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.col);
    try std.testing.expect(!active(&terminal).origin_mode);
    try std.testing.expectEqual(@as(u8, 0), terminal.gl_index);
    try std.testing.expectEqual(@as(u8, 'B'), terminal.g0_designation);
    try std.testing.expectEqual(@as(u8, 'B'), terminal.g1_designation);
}

test "terminal cursor: alt screen enter resets alt cursor instead of copying primary" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[3;4H\x1b[6 q\x1b[?47h");
    try std.testing.expect(view(&terminal).is_alternate_screen);
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.row);
    try std.testing.expectEqual(@as(u16, 0), active(&terminal).cursor.col);
    try std.testing.expectEqual(.block, active(&terminal).cursor.effective_shape);
    try std.testing.expect(active(&terminal).cursor.blink_intent);
}

test "terminal cursor: decscusr no-shape stays explicit through surface view" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 2, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[7 q");
    const visible = view(&terminal);
    try std.testing.expectEqual(.none, active(&terminal).cursor.effective_shape);
    try std.testing.expectEqual(.none, visible.cursor_shape);
    try std.testing.expect(visible.cursor_visible);
}
