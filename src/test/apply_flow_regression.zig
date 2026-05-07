//! Responsibility: deterministic regression coverage for apply-flow replay semantics.
//! Ownership: vt-core event apply-flow correctness tests.
//! Reason: guard parser and replay edge cases with replayable, build-gated coverage.

const std = @import("std");
const grid_owner = @import("../grid.zig");
const interpret_owner = @import("../interpret.zig");
const vt_mod = @import("vt_core");

const Grid = grid_owner;
const Interpret = interpret_owner;
const ApplyFlow = Interpret.ApplyFlow;

fn feed(flow: *ApplyFlow, screen: *Grid.GridModel, bytes: []const u8) void {
    flow.feedSlice(bytes);
    flow.applyToScreen(screen);
}

fn repaintPromptLine(flow: *ApplyFlow, screen: *Grid.GridModel, prompt: []const u8, command: []const u8) void {
    feed(flow, screen, "\r\x1b[K");
    feed(flow, screen, prompt);
    feed(flow, screen, command);
}

fn expectPromptLine(screen: *Grid.GridModel, prompt: []const u8, command: []const u8) !void {
    const total_len = prompt.len + command.len;
    try std.testing.expect(total_len <= screen.cols);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, @intCast(total_len)), screen.cursor_col);

    var idx: usize = 0;
    while (idx < prompt.len) : (idx += 1) {
        try std.testing.expectEqual(@as(u21, prompt[idx]), screen.cellAt(0, @intCast(idx)));
    }

    var cmd_idx: usize = 0;
    while (cmd_idx < command.len) : (cmd_idx += 1) {
        try std.testing.expectEqual(@as(u21, command[cmd_idx]), screen.cellAt(0, @intCast(prompt.len + cmd_idx)));
    }

    var clear_idx: usize = total_len;
    while (clear_idx < screen.cols) : (clear_idx += 1) {
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, @intCast(clear_idx)));
    }
}
test "apply flow: mixed text and CSI and text" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    flow.feedSlice("hello\x1b[1mworld");
    try std.testing.expectEqual(@as(usize, 3), flow.len());
    try std.testing.expect(flow.events()[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", flow.events()[0].text);
    try std.testing.expect(flow.events()[1] == .style_change);
    try std.testing.expect(flow.events()[2] == .text);
    try std.testing.expectEqualSlices(u8, "world", flow.events()[2].text);
}

test "apply flow: reset clears events and parser state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    flow.feedSlice("abc\x1b[1m");
    try std.testing.expectEqual(@as(usize, 2), flow.len());
    flow.reset();
    try std.testing.expect(flow.isEmpty());
    flow.feedSlice("xyz");
    try std.testing.expectEqual(@as(usize, 1), flow.len());
    try std.testing.expectEqualSlices(u8, "xyz", flow.events()[0].text);
}

test "apply flow: split CSI across feeds" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    flow.feedSlice("\x1b[");
    flow.feedSlice("31m");
    try std.testing.expectEqual(@as(usize, 1), flow.len());
    try std.testing.expect(flow.events()[0] == .style_change);
    try std.testing.expectEqual(@as(i32, 31), flow.events()[0].style_change.params[0]);
}

test "apply flow: stray ESC in OSC dropped, byte appended" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    flow.feedSlice("\x1b]ti\x1btle\x07");
    try std.testing.expectEqual(@as(usize, 1), flow.len());
    try std.testing.expect(flow.events()[0] == .osc);
    try std.testing.expectEqual(.title, flow.events()[0].osc.kind);
    try std.testing.expectEqualSlices(u8, "title", flow.events()[0].osc.payload);
}

test "replay: apply-flow clear drops pending parser events before apply" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    flow.feedSlice("dropped");
    try std.testing.expect(flow.len() > 0);
    flow.clear();
    try std.testing.expect(flow.isEmpty());
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: apply-flow reset clears queued events and partial CSI" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 12, 40);
    defer screen.deinit(gpa);
    screen.cursor_row = 10;
    screen.cursor_col = 0;
    flow.feedSlice("x\x1b[3");
    try std.testing.expectEqual(@as(usize, 1), flow.len());
    flow.reset();
    try std.testing.expect(flow.isEmpty());
    flow.feedSlice("A");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(10, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(10, 1));
}

test "replay: apply-flow clear preserves partial CHT parser state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    flow.feedSlice("abc");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    flow.feedSlice("\x1b[2");
    flow.clear();
    try std.testing.expect(flow.isEmpty());
    flow.feedSlice("Ix");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 16));
    try std.testing.expect(flow.isEmpty());
}

test "replay: apply-flow clear preserves partial CBT parser state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    flow.feedSlice("a\x1b[2I");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    flow.feedSlice("\x1b[2");
    flow.clear();
    try std.testing.expect(flow.isEmpty());
    flow.feedSlice("Zy");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 0));
    try std.testing.expect(flow.isEmpty());
}

test "replay: apply-flow reset drops partial CHT parser state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    flow.feedSlice("\x1b[2");
    flow.reset();
    try std.testing.expect(flow.isEmpty());
    flow.feedSlice("Iw");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'I'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(0, 1));
}

test "replay: apply-flow reset drops partial CBT parser state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    flow.feedSlice("a\x1b[2I");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    flow.feedSlice("\x1b[2");
    flow.reset();
    try std.testing.expect(flow.isEmpty());
    flow.feedSlice("Zv");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 18), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'v'), screen.cellAt(0, 17));
}

test "replay: applyToScreen drains parser events once repeat apply is no-op" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    flow.feedSlice("\x1b[4C");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expect(flow.isEmpty());
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    flow.feedSlice("z");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u21, 'z'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "replay: CUU moves cursor up" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 10;
    feed(&flow, &screen, "\x1b[3A");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
}

test "replay: CUD moves cursor down" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 5;
    feed(&flow, &screen, "\x1b[4B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "replay: CUF moves cursor forward" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 15), screen.cursor_col);
}

test "replay: CUB moves cursor back" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 20;
    feed(&flow, &screen, "\x1b[6D");
    try std.testing.expectEqual(@as(u16, 14), screen.cursor_col);
}

test "replay: CUD alias 'e' moves cursor down" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 5;
    feed(&flow, &screen, "\x1b[4e");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "replay: CUD alias 'e' zero param defaults to 1" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 5;
    feed(&flow, &screen, "\x1b[e");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
}

test "replay: CUF alias 'a' moves cursor forward" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x1b[5a");
    try std.testing.expectEqual(@as(u16, 15), screen.cursor_col);
}

test "replay: CUF alias 'a' zero param defaults to 1" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x1b[a");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
}

test "replay: CHA alias backtick moves cursor to absolute column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x1b[7`");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "replay: CHA alias backtick zero param defaults to column 0" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x1b[`");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CUD alias 'e' clamps at last row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(5, 20);
    screen.cursor_row = 2;
    feed(&flow, &screen, "\x1b[999e");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "replay: CUF alias 'a' clamps at last column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(10, 5);
    feed(&flow, &screen, "\x1b[999a");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "replay: CHA alias backtick clamps at last column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(5, 20);
    feed(&flow, &screen, "\x1b[999`");
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "replay: CNL moves cursor down and resets column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 20;
    feed(&flow, &screen, "\x1b[3E");
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CPL moves cursor up and resets column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 8;
    screen.cursor_col = 20;
    feed(&flow, &screen, "\x1b[3F");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: split CNL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("Ex");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split CNL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("Ex");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(7, 0));
}

test "replay: split CPL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("Fx");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split CPL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("Fx");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
}

test "replay: CHA moves cursor to absolute column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 6;
    screen.cursor_col = 12;
    feed(&flow, &screen, "\x1b[5G");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "replay: VPA moves cursor to absolute row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 12;
    screen.cursor_col = 9;
    feed(&flow, &screen, "\x1b[7d");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
}

test "replay: VPA default param moves cursor to row zero" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 12;
    screen.cursor_col = 9;
    feed(&flow, &screen, "\x1b[d");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
}

test "replay: VPA clamps at last row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(5, 20);
    feed(&flow, &screen, "\x1b[999d");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: split VPA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("dx");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split VPA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("dx");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(6, 0));
}

test "replay: CHA default param moves cursor to column zero" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 4;
    screen.cursor_col = 33;
    feed(&flow, &screen, "\x1b[G");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CHA clamps at last column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(2, 20);
    feed(&flow, &screen, "\x1b[999G");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "replay: split CHA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("Gx");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: split CHA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("\x1b[7");
    flow.feedSlice("Gx");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "replay: CUP absolute move" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    feed(&flow, &screen, "\x1b[5;20H");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "replay: CUP no params moves to origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 10;
    screen.cursor_col = 40;
    feed(&flow, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: split CSI across multiple feeds" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 10;
    flow.feedSlice("\x1b[");
    flow.feedSlice("2");
    flow.feedSlice("A");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
}

test "replay: clamping at screen boundaries" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    feed(&flow, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&flow, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 23), screen.cursor_row);
    feed(&flow, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 79), screen.cursor_col);
}

test "replay: plain text feed writes to screen cells" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "hello");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'o'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "replay: mixed CSI cursor move then text write" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "\x1b[2;5Hhi");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(1, 4));
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAt(1, 5));
}

test "replay: CR resets column leaving row unchanged" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc\x0Dxy");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 1));
}

test "replay: LF advances row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "ab\x0Acd");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(1, 2));
}

test "replay: CR+LF writes to start of next row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc\x0D\x0Adef");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(1, 0));
}

test "replay: BS moves cursor left without erasing cell" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc\x08");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
}

test "replay: CSI I advances cursor by default tab stops" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "a\x1b[2Ib");
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 16));
}

test "replay: CSI Z moves cursor to previous default tab stop" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "a\x1b[2I\x1b[Zb");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 8));
}

test "replay: UTF-8 codepoint written to cell" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "\xC3\xA9");
    try std.testing.expectEqual(@as(u21, 0xE9), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
}

test "replay: invalid UTF-8 does not corrupt cursor state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x80\xFE");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_col);
}

test "replay: unsupported CSI does not alter cell content or cursor" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "ab");
    feed(&flow, &screen, "\x1b[1m\x1b[0m");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "replay: multi-line text via CR+LF sequence" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "row0\x0D\x0Arow1\x0D\x0Arow2");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, '2'), screen.cellAt(2, 3));
}

test "replay: sequence of moves composes correctly" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    feed(&flow, &screen, "\x1b[10;10H");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
    feed(&flow, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    feed(&flow, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 14), screen.cursor_col);
    feed(&flow, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CSI K erases from cursor to end of line" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "hello");
    screen.cursor_col = 2;
    feed(&flow, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "replay: CSI J erases from cursor to end of screen" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 3, 5);
    defer screen.deinit(gpa);
    screen.cursor_row = 0;
    screen.cursor_col = 0;
    feed(&flow, &screen, "AAAAA");
    screen.cursor_row = 1;
    screen.cursor_col = 0;
    feed(&flow, &screen, "BBBBB");
    screen.cursor_row = 2;
    screen.cursor_col = 0;
    feed(&flow, &screen, "CCCCC");
    screen.cursor_row = 1;
    screen.cursor_col = 2;
    feed(&flow, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(2, 0));
}

test "replay: cursor move then CSI K erase to end of line" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abcdef");
    feed(&flow, &screen, "\x1b[1;4H");
    feed(&flow, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 5));
}

test "replay: CSI @ inserts blanks and preserves suffix" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 8);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "abcdef");
    feed(&flow, &screen, "\x1b[1;3H");
    feed(&flow, &screen, "\x1b[2@");

    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 'e'), screen.cellAt(0, 6));
    try std.testing.expectEqual(@as(u21, 'f'), screen.cellAt(0, 7));
}

test "replay: VT FF IND NEL and RI aliases" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 3, 5);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "A\x0bB\x0cC");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 2));

    feed(&flow, &screen, "\x1b[1;5H\x1bE");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);

    feed(&flow, &screen, "\x1bM");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&flow, &screen, "\x1bD");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
}

test "replay: ANSI CSI save and restore cursor aliases" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);

    feed(&flow, &screen, "\x1b[4;5H\x1b[s\x1b[10;10H\x1b[u");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "replay: ESC c resets visible grid state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "abc\x1bc");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: DECSCUSR sets steady bar cursor" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);

    feed(&flow, &screen, "\x1b[6 q");
    try std.testing.expectEqual(.bar, screen.cursor_style.shape);
    try std.testing.expect(!screen.cursor_style.blink);
}

test "replay: REP repeats preceding graphic character" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 8);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "A\x1b[4b");
    var col: u16 = 0;
    while (col < 5) : (col += 1) {
        try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, col));
    }
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "replay: DECSTR resets visible grid state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abcdef");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    feed(&flow, &screen, "\x1b[!p");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
}

test "replay: split CHT interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    flow.feedSlice("\x1b[2");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("Ix");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
    try std.testing.expect(flow.isEmpty());
}

test "replay: split CHT after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abc");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("\x1b[2");
    flow.feedSlice("Ix");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 16));
    try std.testing.expect(flow.isEmpty());
}

test "replay: split CBT interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "a\x1b[2I");
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    flow.feedSlice("\x1b[2");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("Zy");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 19));
    try std.testing.expect(flow.isEmpty());
}

test "replay: split CBT after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "a\x1b[2I");
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("\x1b[2");
    flow.feedSlice("Zy");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 0));
    try std.testing.expect(flow.isEmpty());
}

test "replay: DEC private cursor visibility toggles mode state" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(2, 5);
    try std.testing.expect(screen.cursor_visible);
    feed(&flow, &screen, "\x1b[?25l");
    try std.testing.expect(!screen.cursor_visible);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[?25h");
    try std.testing.expect(screen.cursor_visible);
}

test "replay: interrupted split private cursor mode remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.cursor_visible);
    feed(&flow, &screen, "x");
    flow.feedSlice("\x1b[?2");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("5l");
    flow.applyToScreen(&screen);
    try std.testing.expect(screen.cursor_visible);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 1));
    try std.testing.expect(flow.isEmpty());
}

test "replay: DEC private auto-wrap mode toggles wrap behavior" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.auto_wrap);
    feed(&flow, &screen, "\x1b[?7l");
    try std.testing.expect(!screen.auto_wrap);
    feed(&flow, &screen, "abcdefg");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'g'), screen.cellAt(0, 4));
    feed(&flow, &screen, "\x1b[?7h");
    try std.testing.expect(screen.auto_wrap);
    feed(&flow, &screen, "hi");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAt(1, 0));
}

test "replay: interrupted split private auto-wrap mode remains deterministic" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.auto_wrap);
    feed(&flow, &screen, "x");
    flow.feedSlice("\x1b[?");
    flow.feedSlice("\x1b[!p");
    flow.feedSlice("7l");
    flow.applyToScreen(&screen);
    try std.testing.expect(screen.auto_wrap);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, '!'), screen.cellAt(0, 1));
    try std.testing.expect(flow.isEmpty());
}

test "replay: existing text and cursor paths unaffected by erase additions" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "hello\x0D\x0Aworld");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "replay: CUP alternate final f positions cursor" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    feed(&flow, &screen, "\x1b[4;7f");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "replay: CSI J mode 2 erases full screen" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 4);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "AAAA");
    feed(&flow, &screen, "\x0D\x0A");
    feed(&flow, &screen, "BBBB");
    feed(&flow, &screen, "\x1b[H\x1b[2J");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 3));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CSI J mode 1 erases through cursor inclusive" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 3, 4);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "AAAA");
    feed(&flow, &screen, "\x0D\x0A");
    feed(&flow, &screen, "BBBB");
    feed(&flow, &screen, "\x0D\x0A");
    feed(&flow, &screen, "CCCC");
    screen.cursor_row = 1;
    screen.cursor_col = 2;
    feed(&flow, &screen, "\x1b[1J");
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 2));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "replay: CSI K mode 1 erases line start through cursor" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 6);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "abcdef");
    screen.cursor_col = 2;
    feed(&flow, &screen, "\x1b[1K");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'f'), screen.cellAt(0, 5));
}

test "replay: CSI K mode 2 erases entire current line" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "hello");
    feed(&flow, &screen, "\x1b[2;1H");
    feed(&flow, &screen, "world");
    feed(&flow, &screen, "\x1b[1;1H");
    feed(&flow, &screen, "\x1b[2K");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "replay: CSI J invalid param maps to mode 0 through end of screen" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 4);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "AAAA");
    feed(&flow, &screen, "\x0D\x0A");
    feed(&flow, &screen, "BBBB");
    screen.cursor_row = 0;
    screen.cursor_col = 1;
    feed(&flow, &screen, "\x1b[9J");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
}

test "replay: split CSI erase across parser feeds" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 5);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "hello");
    screen.cursor_col = 2;
    flow.feedSlice("\x1b[");
    flow.feedSlice("1K");
    flow.applyToScreen(&screen);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 3));
}

test "replay: control BEL does not move cursor or alter cells" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    feed(&flow, &screen, "ab\x07c");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
}

test "edge: CUU repeated moves from top clamps at row 0" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_row = 3;
    feed(&flow, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
}

test "edge: CUD repeated moves from bottom clamps at last row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(10, 80);
    screen.cursor_row = 7;
    feed(&flow, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    feed(&flow, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "edge: CUF repeated moves from right clamps at last column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 12);
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
}

test "edge: CUB repeated moves from left clamps at column 0" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(24, 80);
    screen.cursor_col = 3;
    feed(&flow, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: mixed cursor moves (up/down/left/right) maintain saturation at edges" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(8, 8);
    feed(&flow, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&flow, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    feed(&flow, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    feed(&flow, &screen, "\x1b[5A\x1b[2C");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    feed(&flow, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
}

test "edge: CR at column 0 leaves cursor unchanged" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 2;
    screen.cursor_col = 0;
    feed(&flow, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: LF at bottom row clamps at last row" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 5, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 4;
    screen.cursor_col = 5;
    feed(&flow, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    feed(&flow, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "edge: BS at column 0 clamps at column 0" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 1;
    screen.cursor_col = 0;
    feed(&flow, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: CR then LF sequences from edge positions" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 5, 10);
    defer screen.deinit(gpa);
    screen.cursor_col = 9;
    screen.cursor_row = 0;
    feed(&flow, &screen, "\x0D\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    screen.cursor_row = 4;
    feed(&flow, &screen, "\x0D\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "edge: BS then CUB sequence does not corrupt cursor" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_col = 5;
    feed(&flow, &screen, "\x08\x08\x08\x08\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[3D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x08\x08\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: CR does not move row; LF only moves row; BS only moves column" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 8, 15);
    defer screen.deinit(gpa);
    screen.cursor_row = 3;
    screen.cursor_col = 10;
    feed(&flow, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: zero-dimension apply-flow clear and reset are safe" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(0, 0);
    flow.feedSlice("test\x1b[5A");
    flow.clear();
    try std.testing.expect(flow.isEmpty());
    flow.applyToScreen(&screen);
    flow.feedSlice("more\x1b[1B");
    flow.reset();
    try std.testing.expect(flow.isEmpty());
    flow.applyToScreen(&screen);
}

test "zero-dim: rows=0, cols=8: cursor moves saturate, text/erase are safe no-ops" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(0, 8);
    feed(&flow, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x1b[3D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&flow, &screen, "hello");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&flow, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "zero-dim: rows=8, cols=0: cursor moves saturate, text/erase are safe no-ops" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(8, 0);
    feed(&flow, &screen, "\x1b[3B");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "text");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=0: all cursor moves saturate at origin, text/erase safe" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(0, 0);
    feed(&flow, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "xyz");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[2J");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=8: CR/LF/BS control sequence determinism" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(0, 8);
    screen.cursor_col = 5;
    feed(&flow, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[3C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    feed(&flow, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "zero-dim: rows=8, cols=0: CR/LF/BS control sequence determinism" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(8, 0);
    screen.cursor_row = 3;
    feed(&flow, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=0: CUP absolute position saturates at origin" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(0, 0);
    feed(&flow, &screen, "\x1b[999;999H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=10: repeated erase operations remain safe" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(0, 10);
    screen.cursor_col = 5;
    feed(&flow, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x1b[2K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x1b[1J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&flow, &screen, "\x1b[2J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "zero-dim: rows=10, cols=0: repeated text writes remain safe" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = Grid.GridModel.init(10, 0);
    screen.cursor_row = 3;
    feed(&flow, &screen, "test");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "\xC3\xA9");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&flow, &screen, "more");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: tab commands remain safe across all zero-dimension variants" {
    const gpa = std.testing.allocator;

    var pl_rows0 = try ApplyFlow.init(gpa);
    defer pl_rows0.deinit();
    var screen_rows0 = Grid.GridModel.init(0, 8);
    feed(&pl_rows0, &screen_rows0, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 0), screen_rows0.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_rows0.cursor_col);

    var pl_cols0 = try ApplyFlow.init(gpa);
    defer pl_cols0.deinit();
    var screen_cols0 = Grid.GridModel.init(8, 0);
    screen_cols0.cursor_row = 3;
    feed(&pl_cols0, &screen_cols0, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 3), screen_cols0.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_cols0.cursor_col);

    var pl_zero = try ApplyFlow.init(gpa);
    defer pl_zero.deinit();
    var screen_zero = Grid.GridModel.init(0, 0);
    feed(&pl_zero, &screen_zero, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 0), screen_zero.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_zero.cursor_col);
}

test "replay: clear leaves snapshot unchanged" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("ABC");
    vt_core.apply();
    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    vt_core.feedSlice("\x1b[H");
    vt_core.clear();

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
}

test "replay: reset preserves snapshot state" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("HELLO");
    vt_core.apply();
    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    vt_core.feedSlice("\x1b[H");
    vt_core.reset();

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    if (snap_before.cells != null and snap_after.cells != null) {
        const size = @as(usize, snap_before.rows) * @as(usize, snap_before.cols);
        try std.testing.expectEqualSlices(u21, snap_before.cells.?[0..size], snap_after.cells.?[0..size]);
    }
}

test "replay: resetScreen clears cells while preserving history" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCellsAndHistory(gpa, 3, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("LINE1\nLINE2\nLINE3\nLINE4");
    vt_core.apply();
    const hist_before = vt_core.historyCount();

    var snap_before = try vt_core.snapshot();
    defer snap_before.deinit();

    vt_core.resetScreen();

    var snap_after = try vt_core.snapshot();
    defer snap_after.deinit();

    try std.testing.expectEqual(@as(u16, 0), snap_after.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), snap_after.cursor_col);
    try std.testing.expectEqual(hist_before, snap_after.history_count);
    if (snap_after.cells != null) {
        const size = @as(usize, snap_after.rows) * @as(usize, snap_after.cols);
        for (snap_after.cells.?[0..size]) |cell| {
            try std.testing.expectEqual(@as(u21, 0), cell);
        }
    }
}

test "replay: snapshot determinism across feed sequence variations" {
    const gpa = std.testing.allocator;

    var vt_core1 = try vt_mod.VtCore.initWithCells(gpa, 10, 20);
    defer vt_core1.deinit();
    vt_core1.feedSlice("\x1b[2J");
    vt_core1.feedSlice("Line1\nLine2");
    vt_core1.apply();
    var snap1 = try vt_core1.snapshot();
    defer snap1.deinit();

    var vt_core2 = try vt_mod.VtCore.initWithCells(gpa, 10, 20);
    defer vt_core2.deinit();
    vt_core2.feedByte('\x1b');
    vt_core2.feedByte('[');
    vt_core2.feedByte('2');
    vt_core2.feedByte('J');
    vt_core2.feedByte('L');
    vt_core2.feedByte('i');
    vt_core2.feedSlice("ne1\nLine2");
    vt_core2.apply();
    var snap2 = try vt_core2.snapshot();
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
    if (snap1.cells != null and snap2.cells != null) {
        const size = @as(usize, snap1.rows) * @as(usize, snap1.cols);
        try std.testing.expectEqualSlices(u21, snap1.cells.?[0..size], snap2.cells.?[0..size]);
    }
}

test "replay: snapshot reflects mode changes" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("TEST");
    vt_core.apply();
    var snap1 = try vt_core.snapshot();
    defer snap1.deinit();
    try std.testing.expectEqual(true, snap1.cursor_visible);

    vt_core.feedSlice("\x1b[?25l");
    vt_core.apply();
    var snap2 = try vt_core.snapshot();
    defer snap2.deinit();
    try std.testing.expectEqual(false, snap2.cursor_visible);

    vt_core.feedSlice("\x1b[?25h");
    vt_core.apply();
    var snap3 = try vt_core.snapshot();
    defer snap3.deinit();
    try std.testing.expectEqual(true, snap3.cursor_visible);
}

test "replay: snapshot includes active selection endpoints" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();

    vt_core.feedSlice("0123456789");
    vt_core.apply();

    vt_core.selectionStart(0, 2);
    vt_core.selectionUpdate(0, 7);
    vt_core.selectionFinish();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(true, snap.selection != null);
    if (snap.selection) |sel| {
        try std.testing.expectEqual(true, sel.active);
        try std.testing.expectEqual(@as(i32, 0), sel.start.row);
        try std.testing.expectEqual(@as(u16, 2), sel.start.col);
        try std.testing.expectEqual(@as(i32, 0), sel.end.row);
        try std.testing.expectEqual(@as(u16, 7), sel.end.col);
    }
}

test "replay: snapshot parity across direct apply flow" {
    const gpa = std.testing.allocator;
    const test_bytes = "ABC\x1b[1;5HXY";

    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 5, 10);
    defer screen.deinit(gpa);

    flow.feedSlice(test_bytes);
    flow.applyToScreen(&screen);

    var vt_core = try vt_mod.VtCore.initWithCells(gpa, 5, 10);
    defer vt_core.deinit();
    vt_core.feedSlice(test_bytes);
    vt_core.apply();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(screen.cursor_row, snap.cursor_row);
    try std.testing.expectEqual(screen.cursor_col, snap.cursor_col);
    if (snap.cells != null and screen.cells != null) {
        var row: u16 = 0;
        while (row < screen.rows) : (row += 1) {
            var col: u16 = 0;
            while (col < screen.cols) : (col += 1) {
                try std.testing.expectEqual(screen.cellAt(row, col), snap.cellAt(row, col));
            }
        }
    }
}

test "replay: snapshot wraparound history indices after eviction" {
    const gpa = std.testing.allocator;
    var vt_core = try vt_mod.VtCore.initWithCellsAndHistory(gpa, 2, 5, 3);
    defer vt_core.deinit();

    vt_core.feedSlice("A\r\nB\r\nC\r\nD\r\nE");
    vt_core.apply();

    var snap = try vt_core.snapshot();
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 3), snap.history_capacity);
    try std.testing.expectEqual(@as(usize, 3), snap.history_count);

    try std.testing.expect(snap.history != null);
    try std.testing.expectEqual(@as(usize, 15), snap.history.?.len);

    try std.testing.expectEqual(@as(u21, 'C'), snap.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), snap.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'A'), snap.historyRowAt(2, 0));

    var row: usize = 0;
    while (row < snap.history_count) : (row += 1) {
        var col: u16 = 0;
        while (col < snap.cols) : (col += 1) {
            try std.testing.expectEqual(vt_core.historyRowAt(row, col), snap.historyRowAt(row, col));
        }
    }
}

test "replay: prompt redraw clears stale suffix after reset history entry" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 64);
    defer screen.deinit(gpa);

    const prompt = "$ ";

    repaintPromptLine(&flow, &screen, prompt, "ll");
    try expectPromptLine(&screen, prompt, "ll");

    repaintPromptLine(&flow, &screen, prompt, "reset");
    try expectPromptLine(&screen, prompt, "reset");

    repaintPromptLine(&flow, &screen, prompt, "ll");
    try expectPromptLine(&screen, prompt, "ll");

    repaintPromptLine(&flow, &screen, prompt, "reset");
    try expectPromptLine(&screen, prompt, "reset");

    repaintPromptLine(&flow, &screen, prompt, "ll");
    try expectPromptLine(&screen, prompt, "ll");
}

test "replay: prompt redraw fuzz clears stale suffix across random history entries" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 96);
    defer screen.deinit(gpa);

    const prompt = "$ ";
    const commands = [_][]const u8{
        "ll",
        "reset",
        "printf '\\033[3J\\033[H\\033[2J'",
        "git status",
        "zig build run",
        "clear",
        "nvim README.md",
        "cargo test",
        "ls -la",
        "echo short",
    };

    var prng = std.Random.DefaultPrng.init(0xBADC0FFEE0DDF00D);
    const rand = prng.random();

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const command = commands[rand.uintLessThan(usize, commands.len)];
        repaintPromptLine(&flow, &screen, prompt, command);
        try expectPromptLine(&screen, prompt, command);
    }
}

test "replay: bash history redraw with DCH clears reset suffix" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 64);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "reset");
    feed(&flow, &screen, "\x08\x08\x08\x08\x08\x1b[3Pll");

    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 4));
}

test "replay: neovim colored empty cells through EL and ECH" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 10);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "\x1b[38;2;40;44;52m\x1b[48;2;40;44;52m~\x1b[K");
    feed(&flow, &screen, "\x1b[2;3H\x1b[6X");

    const el_cell = screen.cellInfoAt(0, 1);
    try std.testing.expectEqual(@as(u21, 0), @as(u21, @intCast(el_cell.codepoint)));
    try std.testing.expectEqual(@as(u8, 40), el_cell.attrs.bg.r);
    try std.testing.expectEqual(@as(u8, 44), el_cell.attrs.bg.g);
    try std.testing.expectEqual(@as(u8, 52), el_cell.attrs.bg.b);

    const ech_cell = screen.cellInfoAt(1, 2);
    try std.testing.expectEqual(@as(u21, 0), @as(u21, @intCast(ech_cell.codepoint)));
    try std.testing.expectEqual(@as(u8, 40), ech_cell.attrs.bg.r);
    try std.testing.expectEqual(@as(u8, 44), ech_cell.attrs.bg.g);
    try std.testing.expectEqual(@as(u8, 52), ech_cell.attrs.bg.b);
}

test "replay: DEC special graphics renders box drawing cells" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 8);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "\x1b(0lqkxmj\x1b(Bq");

    try std.testing.expectEqual(@as(u21, 0x250C), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0x2500), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0x2510), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0x2502), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0x2514), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 0x2518), screen.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 'q'), screen.cellAt(0, 6));
}

test "replay: DEC special graphics G1 via SO SI" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 1, 4);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "\x1b)0\x0eq\x0fq");

    try std.testing.expectEqual(@as(u21, 0x2500), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'q'), screen.cellAt(0, 1));
}

test "replay: SL SR and DECST8C execute from CSI syntax" {
    const gpa = std.testing.allocator;
    var flow = try ApplyFlow.init(gpa);
    defer flow.deinit();
    var screen = try Grid.GridModel.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);

    feed(&flow, &screen, "ABCDE\x1b[2 @");
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'E'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));

    feed(&flow, &screen, "\x1b[1;1HABCDE\x1b[1 A");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'D'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'E'), screen.cellAt(0, 5));

    feed(&flow, &screen, "\x1b[3g\x1b[?5W");
    try std.testing.expect(screen.tabStopAt(8));
    try std.testing.expect(screen.tabStopAt(16));
}
