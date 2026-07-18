const std = @import("std");
const screen_set = @import("../../src/screen_set.zig");
const terminal_mod = @import("../../src/terminal.zig");
const stream_harness = @import("../support/stream_harness.zig");

const Terminal = terminal_mod.Terminal;

test "terminal rejects zero dimensions exactly" {
    try std.testing.expectError(error.InvalidDimensions, Terminal.init(std.testing.allocator, 0, 1));
    try std.testing.expectError(error.InvalidDimensions, Terminal.init(std.testing.allocator, 1, 0));
    try std.testing.expectError(error.InvalidDimensions, Terminal.initWithHistory(std.testing.allocator, 0, 0, 8));
}

test "terminal constructors clean up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initTerminal, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, initTerminalWithHistory, .{});
}

fn initTerminal(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 2, 3);
    terminal.deinit();
}

fn initTerminalWithHistory(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 3, 4);
    terminal.deinit();
}

test "terminal resize is transactional in both active-screen modes" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeTerminalTransaction, .{false});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeTerminalTransaction, .{true});
}

fn resizeTerminalTransaction(allocator: std.mem.Allocator, alternate_active: bool) !void {
    var terminal = try Terminal.initWithHistory(allocator, 2, 4, 8);
    defer terminal.deinit();

    terminal.screen_state.primary.writeText("PRIMARY-ROWS");
    terminal.screen_state.alternate.writeText("ALTERNATE");
    terminal.screen_state.alt_active = alternate_active;
    terminal.screen_state.primary.cursor.setDefaultStyle(.{ .shape = .bar, .blink = false });
    terminal.screen_state.alternate.cursor.setDefaultStyle(.{ .shape = .underline, .blink = true });
    terminal.screen_state.primary.left_right_margin_mode = true;
    terminal.screen_state.primary.left_margin = 1;
    terminal.screen_state.primary.right_margin = 2;
    terminal.startSelection(0, 0);
    terminal.finishSelection();

    const primary_history_count = terminal.screen_state.primary.historyCount();
    const primary_history_cell = terminal.screen_state.primary.historyRowAt(0, 0);
    const alternate_cell = terminal.screen_state.alternate.cellAt(0, 0);
    const selection_before = terminal.selectionState();
    const dirty_generation_before = terminal.dirty_generation;

    terminal.resize(3, 3) catch |err| {
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.primary.cols);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.alternate.rows);
        try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.alternate.cols);
        try std.testing.expectEqual(primary_history_count, terminal.screen_state.primary.historyCount());
        try std.testing.expectEqual(primary_history_cell, terminal.screen_state.primary.historyRowAt(0, 0));
        try std.testing.expectEqual(alternate_cell, terminal.screen_state.alternate.cellAt(0, 0));
        try std.testing.expectEqual(alternate_active, terminal.screen_state.alt_active);
        try std.testing.expectEqual(selection_before, terminal.selectionState());
        try std.testing.expectEqual(dirty_generation_before, terminal.dirty_generation);
        try std.testing.expect(terminal.screen_state.primary.left_right_margin_mode);
        try std.testing.expectEqual(@as(u16, 1), terminal.screen_state.primary.left_margin);
        try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.right_margin);
        try std.testing.expectEqual(.bar, terminal.screen_state.primary.cursor.default_style.shape);
        try std.testing.expectEqual(.underline, terminal.screen_state.alternate.cursor.default_style.shape);
        terminal.screen_state.active().writeText("Z");
        return err;
    };

    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.rows);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.primary.cols);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.alternate.rows);
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.alternate.cols);
    try std.testing.expectEqual(alternate_active, terminal.screen_state.alt_active);
    try std.testing.expect(!terminal.screen_state.primary.left_right_margin_mode);
    try std.testing.expectEqual(@as(u16, 0), terminal.screen_state.primary.left_margin);
    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.primary.right_margin);
    try std.testing.expectEqual(.bar, terminal.screen_state.primary.cursor.default_style.shape);
    try std.testing.expectEqual(.underline, terminal.screen_state.alternate.cursor.default_style.shape);
    try std.testing.expectEqual(dirty_generation_before + 1, terminal.dirty_generation);
}

test "selection copy owns exact allocation and codepoint failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, copySelectionAllocation, .{});

    var terminal = try Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    terminal.startSelection(0, 0);
    terminal.finishSelection();

    terminal.screen_state.primary.cells.?[0].codepoint = 0x110000;
    try std.testing.expectError(error.CodepointTooLarge, terminal.copySelection(std.testing.allocator));
    terminal.screen_state.primary.cells.?[0].codepoint = 0xD800;
    try std.testing.expectError(error.Utf8CannotEncodeSurrogateHalf, terminal.copySelection(std.testing.allocator));
}

fn copySelectionAllocation(allocator: std.mem.Allocator) !void {
    var terminal = try Terminal.init(allocator, 1, 4);
    defer terminal.deinit();
    terminal.screen_state.primary.writeText("COPY");
    terminal.startSelection(0, 0);
    terminal.updateSelection(0, 3);
    terminal.finishSelection();

    const copied = terminal.copySelection(allocator) catch |err| {
        try std.testing.expect(terminal.selectionState() != null);
        try std.testing.expectEqual(@as(u21, 'C'), terminal.screen_state.primary.cellAt(0, 0));
        return err;
    };
    defer allocator.free(copied);
    try std.testing.expectEqualStrings("COPY", copied);
}

test "terminal rejects zero resize without changing dimensions" {
    var terminal = try Terminal.init(std.testing.allocator, 2, 3);
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

    try stream.nextSlice("\x1b[?2026h");
    try std.testing.expect(vt.modes.synchronized_output);

    try stream.nextSlice("\x1b[?2026l");
    try std.testing.expect(!vt.modes.synchronized_output);
}

test "terminal visible view projects scrollback rows" {
    var vt = try Terminal.initWithHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

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
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);

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
