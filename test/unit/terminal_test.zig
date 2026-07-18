const std = @import("std");
const screen_set = @import("../../src/screen_set.zig");
const terminal_mod = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;

test "terminal rejects zero dimensions exactly" {
    try std.testing.expectError(error.InvalidDimensions, Terminal.init(std.testing.allocator, 0, 1));
    try std.testing.expectError(error.InvalidDimensions, Terminal.initWithCells(std.testing.allocator, 1, 0));
    try std.testing.expectError(error.InvalidDimensions, Terminal.initWithCellsAndHistory(std.testing.allocator, 0, 0, 8));
}

test "terminal rejects zero resize without changing dimensions" {
    var terminal = try Terminal.initWithCells(std.testing.allocator, 2, 3);
    defer terminal.deinit();

    try std.testing.expectError(error.InvalidDimensions, terminal.resize(0, 3));
    const view = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u16, 2), view.rows);
    try std.testing.expectEqual(@as(u16, 3), view.cols);
}

test "terminal tracks synchronized output private mode" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);
    defer stream.deinit();

    try stream.nextSlice("\x1b[?2026h");
    try std.testing.expect(vt.modes.synchronized_output);

    try stream.nextSlice("\x1b[?2026l");
    try std.testing.expect(!vt.modes.synchronized_output);
}

test "terminal visible view projects scrollback rows" {
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);
    defer stream.deinit();

    try stream.nextSlice("aa\r\nbb\r\ncc");

    const live = screen_set.visibleView(&vt.screen_state, 0);
    try std.testing.expectEqual(0, live.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'b'), live.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), live.cellAt(1, 0));

    const scrolled = screen_set.visibleView(&vt.screen_state, 1);
    try std.testing.expectEqual(1, scrolled.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'a'), scrolled.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), scrolled.cellAt(1, 0));
    try std.testing.expectEqual(2, scrolled.rowDepth(0));
    try std.testing.expectEqual(1, scrolled.rowDepth(1));
}

test "terminal reset screen delegates owner resets" {
    var vt = try Terminal.initWithCells(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);
    defer stream.deinit();

    vt.screen_state.active().writeText("ab");
    vt.kitty.main.pointer.set("pointer");
    vt.host.locator.mode = .continuous;
    vt.host.locator.coordinate_unit = 1;

    try stream.nextSlice("\x1bc");

    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.activeConst().cellAt(0, 0));
    try std.testing.expectEqualStrings("0", vt.kitty.main.pointer.currentName());
    try std.testing.expect(vt.host.locator.mode == .disabled);
    try std.testing.expectEqual(@as(u16, 0), vt.host.locator.coordinate_unit);
}
