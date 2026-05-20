//! Parser queue/apply regression tests.

const std = @import("std");
const screen_mod = @import("../screen.zig");
const screen_capture = @import("screen_capture.zig");
const screen_set = @import("../screen_set.zig");
const selection = @import("../selection.zig");
const parser_mod = @import("../parser.zig");
const action_root = @import("../action.zig");
const terminal_mod = @import("../terminal.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const Queue = parser_mod.Queue;
const ActionRoot = action_root;
const Terminal = terminal_mod.Terminal;

fn applyQueue(queue: *Queue, screen: *Screen) void {
    while (applyQueueLimit(queue, screen, std.math.maxInt(u32)) != 0) {}
}

fn applyQueueLimit(queue: *Queue, screen: *Screen, max_events: u32) u32 {
    if (max_events == 0) return 0;
    const count = @min(max_events, queue.eventCount());
    var it = queue.iterator();
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) {
        const ev = it.next() orelse unreachable;
        if (ActionRoot.process(ev)) |sem_ev| {
            if (ActionRoot.screenAction(sem_ev)) |screen_ev| screen.applyScreen(screen_ev);
        }
    }
    queue.dropPrefix(count);
    return count;
}

fn captureSnapshot(terminal: *const Terminal) !screen_capture.Capture {
    return screen_capture.Capture.captureFromScreen(
        terminal.allocator,
        terminal.screen_state.activeConst(),
        terminal.screen_state.activeSelectionConst().state(),
    );
}

fn feedByte(terminal: *Terminal, byte: u8) void {
    terminal.parser.feedSlice(&.{byte}) catch unreachable;
}

fn feedSlice(terminal: *Terminal, bytes: []const u8) void {
    terminal.parser.feedSlice(bytes) catch unreachable;
}

fn feedQueueSlice(queue: *Queue, bytes: []const u8) void {
    queue.feedSlice(bytes) catch unreachable;
}

fn collectQueueEvents(allocator: std.mem.Allocator, queue: *const Queue) ![]action_root.Event {
    var out: std.ArrayList(action_root.Event) = .empty;
    defer out.deinit(allocator);
    var it = queue.iterator();
    while (it.next()) |event| try out.append(allocator, event);
    return try out.toOwnedSlice(allocator);
}

fn queueIsEmpty(queue: *const Queue) bool {
    return queue.eventCount() == 0;
}

fn clearQueue(queue: *Queue) void {
    queue.parsed_events.clear();
}

fn resetQueue(queue: *Queue) void {
    queue.parsed_events.resetState();
    queue.parser.reset();
}

fn apply(terminal: *Terminal) void {
    ActionRoot.apply(terminal);
}

fn clear(terminal: *Terminal) void {
    clearQueue(&terminal.parser);
}

fn reset(terminal: *Terminal) void {
    resetQueue(&terminal.parser);
}

fn feed(queue: *Queue, screen: *Screen, bytes: []const u8) void {
    feedQueueSlice(queue, bytes);
    applyQueue(queue, screen);
}

fn repaintPromptLine(queue: *Queue, screen: *Screen, prompt: []const u8, command: []const u8) void {
    feed(queue, screen, "\r\x1b[K");
    feed(queue, screen, prompt);
    feed(queue, screen, command);
}

fn expectPromptLine(screen: *Screen, prompt: []const u8, command: []const u8) !void {
    const total_cols: u16 = @intCast(prompt.len + command.len);
    try std.testing.expect(total_cols <= screen.cols);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(total_cols, screen.cursor_col);

    for (prompt, 0..) |byte, idx| {
        try std.testing.expectEqual(@as(u21, byte), screen.cellAt(0, @intCast(idx)));
    }

    for (command, 0..) |byte, idx| {
        try std.testing.expectEqual(@as(u21, byte), screen.cellAt(0, @intCast(prompt.len + idx)));
    }

    var clear_col = total_cols;
    while (clear_col < screen.cols) : (clear_col += 1) {
        try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, clear_col));
    }
}
test "queue: mixed text and CSI and text" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    feedQueueSlice(&queue, "hello\x1b[1mworld");
    try std.testing.expectEqual(@as(u32, 3), queue.eventCount());
    const events = try collectQueueEvents(gpa, &queue);
    defer gpa.free(events);
    try std.testing.expect(events[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", events[0].text);
    try std.testing.expect(events[1] == .style_change);
    try std.testing.expect(events[2] == .text);
    try std.testing.expectEqualSlices(u8, "world", events[2].text);
}

test "queue: reset clears events and parser state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    feedQueueSlice(&queue, "abc\x1b[1m");
    try std.testing.expectEqual(@as(u32, 2), queue.eventCount());
    resetQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    feedQueueSlice(&queue, "xyz");
    try std.testing.expectEqual(@as(u32, 1), queue.eventCount());
    const events = try collectQueueEvents(gpa, &queue);
    defer gpa.free(events);
    try std.testing.expectEqualSlices(u8, "xyz", events[0].text);
}

test "queue: split CSI across feeds" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    feedQueueSlice(&queue, "\x1b[");
    feedQueueSlice(&queue, "31m");
    try std.testing.expectEqual(@as(u32, 1), queue.eventCount());
    const events = try collectQueueEvents(gpa, &queue);
    defer gpa.free(events);
    try std.testing.expect(events[0] == .style_change);
    try std.testing.expectEqual(@as(i32, 31), events[0].style_change.params[0]);
}

test "queue: stray ESC in OSC dropped, byte appended" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    feedQueueSlice(&queue, "\x1b]ti\x1btle\x07");
    try std.testing.expectEqual(@as(u32, 1), queue.eventCount());
    const events = try collectQueueEvents(gpa, &queue);
    defer gpa.free(events);
    try std.testing.expect(events[0] == .osc);
    try std.testing.expectEqual(.title, events[0].osc.kind);
    try std.testing.expectEqualSlices(u8, "title", events[0].osc.payload);
}

test "feed/apply: queue clear drops pending parsed events before apply" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Screen.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    feedQueueSlice(&queue, "dropped");
    try std.testing.expect(queue.eventCount() > 0);
    clearQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: queue reset clears queued events and partial CSI" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Screen.initWithCells(gpa, 12, 40);
    defer screen.deinit(gpa);
    screen.cursor_row = 10;
    screen.cursor_col = 0;
    feedQueueSlice(&queue, "x\x1b[3");
    try std.testing.expectEqual(@as(u32, 1), queue.eventCount());
    resetQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    feedQueueSlice(&queue, "A");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(10, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(10, 1));
}

test "feed/apply: queue clear preserves partial CHT parser state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Screen.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feedQueueSlice(&queue, "abc");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[2");
    clearQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    feedQueueSlice(&queue, "Ix");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 16));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: queue clear preserves partial CBT parser state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Screen.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feedQueueSlice(&queue, "a\x1b[2I");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[2");
    clearQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    feedQueueSlice(&queue, "Zy");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 0));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: queue reset drops partial CHT parser state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Screen.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feedQueueSlice(&queue, "\x1b[2");
    resetQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    feedQueueSlice(&queue, "Iw");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'I'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(0, 1));
}

test "feed/apply: queue reset drops partial CBT parser state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Screen.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feedQueueSlice(&queue, "a\x1b[2I");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[2");
    resetQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    feedQueueSlice(&queue, "Zv");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 18), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'v'), screen.cellAt(0, 17));
}

test "feed/apply: queue apply drains parsed events once repeat apply is no-op" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    feedQueueSlice(&queue, "\x1b[4C");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expect(queueIsEmpty(&queue));
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    feedQueueSlice(&queue, "z");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u21, 'z'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "feed/apply: CUU moves cursor up" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 10;
    feed(&queue, &screen, "\x1b[3A");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
}

test "feed/apply: CUD moves cursor down" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 5;
    feed(&queue, &screen, "\x1b[4B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "feed/apply: CUF moves cursor forward" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 15), screen.cursor_col);
}

test "feed/apply: CUB moves cursor back" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 20;
    feed(&queue, &screen, "\x1b[6D");
    try std.testing.expectEqual(@as(u16, 14), screen.cursor_col);
}

test "feed/apply: CUD alias 'e' moves cursor down" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 5;
    feed(&queue, &screen, "\x1b[4e");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "feed/apply: CUD alias 'e' zero param defaults to 1" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 5;
    feed(&queue, &screen, "\x1b[e");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
}

test "feed/apply: CUF alias 'a' moves cursor forward" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x1b[5a");
    try std.testing.expectEqual(@as(u16, 15), screen.cursor_col);
}

test "feed/apply: CUF alias 'a' zero param defaults to 1" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x1b[a");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
}

test "feed/apply: CHA alias backtick moves cursor to absolute column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x1b[7`");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "feed/apply: CHA alias backtick zero param defaults to column 0" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x1b[`");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: CUD alias 'e' clamps at last row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(5, 20);
    screen.cursor_row = 2;
    feed(&queue, &screen, "\x1b[999e");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "feed/apply: CUF alias 'a' clamps at last column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(10, 5);
    feed(&queue, &screen, "\x1b[999a");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "feed/apply: CHA alias backtick clamps at last column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(5, 20);
    feed(&queue, &screen, "\x1b[999`");
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "feed/apply: CNL moves cursor down and resets column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 20;
    feed(&queue, &screen, "\x1b[3E");
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: CPL moves cursor up and resets column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 8;
    screen.cursor_col = 20;
    feed(&queue, &screen, "\x1b[3F");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: split CNL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "Ex");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'E'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 1));
}

test "feed/apply: split CNL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "Ex");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(7, 0));
}

test "feed/apply: split CPL interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "Fx");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'F'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 1));
}

test "feed/apply: split CPL after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "Fx");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
}

test "feed/apply: CHA moves cursor to absolute column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 6;
    screen.cursor_col = 12;
    feed(&queue, &screen, "\x1b[5G");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "feed/apply: VPA moves cursor to absolute row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 12;
    screen.cursor_col = 9;
    feed(&queue, &screen, "\x1b[7d");
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
}

test "feed/apply: VPA default param moves cursor to row zero" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 12;
    screen.cursor_col = 9;
    feed(&queue, &screen, "\x1b[d");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
}

test "feed/apply: VPA clamps at last row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(5, 20);
    feed(&queue, &screen, "\x1b[999d");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: split VPA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "dx");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 1));
}

test "feed/apply: split VPA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 10, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "dx");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(6, 0));
}

test "feed/apply: CHA default param moves cursor to column zero" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 4;
    screen.cursor_col = 33;
    feed(&queue, &screen, "\x1b[G");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: CHA clamps at last column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(2, 20);
    feed(&queue, &screen, "\x1b[999G");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "feed/apply: split CHA interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "Gx");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'G'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 1));
}

test "feed/apply: split CHA after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "\x1b[7");
    feedQueueSlice(&queue, "Gx");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 6));
}

test "feed/apply: CUP absolute move" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    feed(&queue, &screen, "\x1b[5;20H");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 19), screen.cursor_col);
}

test "feed/apply: CUP no params moves to origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 10;
    screen.cursor_col = 40;
    feed(&queue, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: split CSI across multiple feeds" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 10;
    feedQueueSlice(&queue, "\x1b[");
    feedQueueSlice(&queue, "2");
    feedQueueSlice(&queue, "A");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
}

test "feed/apply: clamping at screen boundaries" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    feed(&queue, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&queue, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 23), screen.cursor_row);
    feed(&queue, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 79), screen.cursor_col);
}

test "feed/apply: plain text feed writes to screen cells" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "hello");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'o'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "feed/apply: mixed CSI cursor move then text write" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "\x1b[2;5Hhi");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(1, 4));
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAt(1, 5));
}

test "feed/apply: CR resets column leaving row unchanged" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc\x0Dxy");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 1));
}

test "feed/apply: LF advances row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "ab\x0Acd");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(1, 2));
}

test "feed/apply: CR+LF writes to start of next row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc\x0D\x0Adef");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(1, 0));
}

test "feed/apply: BS moves cursor left without erasing cell" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc\x08");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
}

test "feed/apply: CSI I advances cursor by default tab stops" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "a\x1b[2Ib");
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 16));
}

test "feed/apply: CSI Z moves cursor to previous default tab stop" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "a\x1b[2I\x1b[Zb");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 8));
}

test "feed/apply: UTF-8 codepoint written to cell" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "\xC3\xA9");
    try std.testing.expectEqual(@as(u21, 0xE9), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
}

test "feed/apply: invalid UTF-8 does not corrupt cursor state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 5;
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x80\xFE");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 10), screen.cursor_col);
}

test "feed/apply: unsupported CSI does not alter cell content or cursor" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "ab");
    feed(&queue, &screen, "\x1b[1m\x1b[0m");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "feed/apply: multi-line text via CR+LF sequence" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "row0\x0D\x0Arow1\x0D\x0Arow2");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'r'), screen.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, '2'), screen.cellAt(2, 3));
}

test "feed/apply: sequence of moves composes correctly" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    feed(&queue, &screen, "\x1b[10;10H");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_col);
    feed(&queue, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    feed(&queue, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 14), screen.cursor_col);
    feed(&queue, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: CSI K erases from cursor to end of line" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "hello");
    screen.cursor_col = 2;
    feed(&queue, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'e'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "feed/apply: CSI J erases from cursor to end of screen" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 3, 5);
    defer screen.deinit(gpa);
    screen.cursor_row = 0;
    screen.cursor_col = 0;
    feed(&queue, &screen, "AAAAA");
    screen.cursor_row = 1;
    screen.cursor_col = 0;
    feed(&queue, &screen, "BBBBB");
    screen.cursor_row = 2;
    screen.cursor_col = 0;
    feed(&queue, &screen, "CCCCC");
    screen.cursor_row = 1;
    screen.cursor_col = 2;
    feed(&queue, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(2, 0));
}

test "feed/apply: cursor move then CSI K erase to end of line" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abcdef");
    feed(&queue, &screen, "\x1b[1;4H");
    feed(&queue, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 5));
}

test "feed/apply: CSI @ inserts blanks and preserves suffix" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 8);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "abcdef");
    feed(&queue, &screen, "\x1b[1;3H");
    feed(&queue, &screen, "\x1b[2@");

    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 'e'), screen.cellAt(0, 6));
    try std.testing.expectEqual(@as(u21, 'f'), screen.cellAt(0, 7));
}

test "feed/apply: VT FF IND NEL and RI aliases" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 3, 5);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "A\x0bB\x0cC");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), screen.cellAt(1, 1));
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 2));

    feed(&queue, &screen, "\x1b[1;5H\x1bE");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);

    feed(&queue, &screen, "\x1bM");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&queue, &screen, "\x1bD");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
}

test "feed/apply: ANSI CSI save and restore cursor aliases" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);

    feed(&queue, &screen, "\x1b[4;5H\x1b[s\x1b[10;10H\x1b[u");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
}

test "feed/apply: ESC c resets visible grid state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "abc\x1bc");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: DECSCUSR sets steady bar cursor" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);

    feed(&queue, &screen, "\x1b[6 q");
    try std.testing.expectEqual(.bar, screen.cursor_style.shape);
    try std.testing.expect(!screen.cursor_style.blink);
}

test "feed/apply: REP repeats preceding graphic character" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 8);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "A\x1b[4b");
    var col: u16 = 0;
    while (col < 5) : (col += 1) {
        try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, col));
    }
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "feed/apply: DECSTR resets visible grid state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abcdef");
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    feed(&queue, &screen, "\x1b[!p");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
}

test "feed/apply: split CHT interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[2");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "Ix");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'I'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 1));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: split CHT after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abc");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "\x1b[2");
    feedQueueSlice(&queue, "Ix");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 17), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'x'), screen.cellAt(0, 16));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: split CBT interrupted by DECSTR bytes remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "a\x1b[2I");
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[2");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "Zy");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'Z'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 1));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: split CBT after DECSTR applies from reset origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "a\x1b[2I");
    try std.testing.expectEqual(@as(u16, 16), screen.cursor_col);
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "\x1b[2");
    feedQueueSlice(&queue, "Zy");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'y'), screen.cellAt(0, 0));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: DEC private cursor visibility toggles mode state" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(2, 5);
    try std.testing.expect(screen.cursor_visible);
    feed(&queue, &screen, "\x1b[?25l");
    try std.testing.expect(!screen.cursor_visible);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[?25h");
    try std.testing.expect(screen.cursor_visible);
}

test "feed/apply: interrupted split private cursor mode remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.cursor_visible);
    feed(&queue, &screen, "x");
    feedQueueSlice(&queue, "\x1b[?2");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "5l");
    applyQueue(&queue, &screen);
    try std.testing.expect(screen.cursor_visible);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, '5'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 1));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: DEC private auto-wrap mode toggles wrap behavior" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.auto_wrap);
    feed(&queue, &screen, "\x1b[?7l");
    try std.testing.expect(!screen.auto_wrap);
    feed(&queue, &screen, "abcdefg");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'g'), screen.cellAt(0, 4));
    feed(&queue, &screen, "\x1b[?7h");
    try std.testing.expect(screen.auto_wrap);
    feed(&queue, &screen, "hi");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'i'), screen.cellAt(1, 0));
}

test "feed/apply: interrupted split private auto-wrap mode remains deterministic" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);
    try std.testing.expect(screen.auto_wrap);
    feed(&queue, &screen, "x");
    feedQueueSlice(&queue, "\x1b[?");
    feedQueueSlice(&queue, "\x1b[!p");
    feedQueueSlice(&queue, "7l");
    applyQueue(&queue, &screen);
    try std.testing.expect(screen.auto_wrap);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, '7'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 1));
    try std.testing.expect(queueIsEmpty(&queue));
}

test "feed/apply: existing text and cursor paths unaffected by erase additions" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "hello\x0D\x0Aworld");
    try std.testing.expectEqual(@as(u21, 'h'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "feed/apply: CUP alternate final f positions cursor" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    feed(&queue, &screen, "\x1b[4;7f");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 6), screen.cursor_col);
}

test "feed/apply: CSI J mode 2 erases full screen" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 4);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "AAAA");
    feed(&queue, &screen, "\x0D\x0A");
    feed(&queue, &screen, "BBBB");
    feed(&queue, &screen, "\x1b[H\x1b[2J");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 3));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: CSI J mode 1 erases through cursor inclusive" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 3, 4);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "AAAA");
    feed(&queue, &screen, "\x0D\x0A");
    feed(&queue, &screen, "BBBB");
    feed(&queue, &screen, "\x0D\x0A");
    feed(&queue, &screen, "CCCC");
    screen.cursor_row = 1;
    screen.cursor_col = 2;
    feed(&queue, &screen, "\x1b[1J");
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(2, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 2));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "feed/apply: CSI K mode 1 erases line start through cursor" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 6);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "abcdef");
    screen.cursor_col = 2;
    feed(&queue, &screen, "\x1b[1K");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'd'), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 'f'), screen.cellAt(0, 5));
}

test "feed/apply: CSI K mode 2 erases entire current line" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 5);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "hello");
    feed(&queue, &screen, "\x1b[2;1H");
    feed(&queue, &screen, "world");
    feed(&queue, &screen, "\x1b[1;1H");
    feed(&queue, &screen, "\x1b[2K");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'w'), screen.cellAt(1, 0));
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "feed/apply: CSI J invalid param maps to mode 0 through end of screen" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 4);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "AAAA");
    feed(&queue, &screen, "\x0D\x0A");
    feed(&queue, &screen, "BBBB");
    screen.cursor_row = 0;
    screen.cursor_col = 1;
    feed(&queue, &screen, "\x1b[9J");
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(1, 0));
}

test "feed/apply: split CSI erase across parser feeds" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 5);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "hello");
    screen.cursor_col = 2;
    feedQueueSlice(&queue, "\x1b[");
    feedQueueSlice(&queue, "1K");
    applyQueue(&queue, &screen);
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 3));
}

test "feed/apply: control BEL does not move cursor or alter cells" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 8);
    defer screen.deinit(gpa);
    feed(&queue, &screen, "ab\x07c");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    try std.testing.expectEqual(@as(u21, 'a'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), screen.cellAt(0, 2));
}

test "edge: CUU repeated moves from top clamps at row 0" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_row = 3;
    feed(&queue, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
}

test "edge: CUD repeated moves from bottom clamps at last row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(10, 80);
    screen.cursor_row = 7;
    feed(&queue, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 8), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
    feed(&queue, &screen, "\x1b[1B");
    try std.testing.expectEqual(@as(u16, 9), screen.cursor_row);
}

test "edge: CUF repeated moves from right clamps at last column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 12);
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1C");
    try std.testing.expectEqual(@as(u16, 11), screen.cursor_col);
}

test "edge: CUB repeated moves from left clamps at column 0" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(24, 80);
    screen.cursor_col = 3;
    feed(&queue, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: mixed cursor moves (up/down/left/right) maintain saturation at edges" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(8, 8);
    feed(&queue, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    feed(&queue, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_row);
    feed(&queue, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    feed(&queue, &screen, "\x1b[5A\x1b[2C");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 7), screen.cursor_col);
    feed(&queue, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
}

test "edge: CR at column 0 leaves cursor unchanged" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 2;
    screen.cursor_col = 0;
    feed(&queue, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: LF at bottom row clamps at last row" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 5, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 4;
    screen.cursor_col = 5;
    feed(&queue, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    feed(&queue, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "edge: BS at column 0 clamps at column 0" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_row = 1;
    screen.cursor_col = 0;
    feed(&queue, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: CR then LF sequences from edge positions" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 5, 10);
    defer screen.deinit(gpa);
    screen.cursor_col = 9;
    screen.cursor_row = 0;
    feed(&queue, &screen, "\x0D\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    screen.cursor_row = 4;
    feed(&queue, &screen, "\x0D\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
}

test "edge: BS then CUB sequence does not corrupt cursor" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 4, 20);
    defer screen.deinit(gpa);
    screen.cursor_col = 5;
    feed(&queue, &screen, "\x08\x08\x08\x08\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[3D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x08\x08\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: CR does not move row; LF only moves row; BS only moves column" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 8, 15);
    defer screen.deinit(gpa);
    screen.cursor_row = 3;
    screen.cursor_col = 10;
    feed(&queue, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "edge: zero-dimension queue clear and reset are safe" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(0, 0);
    feedQueueSlice(&queue, "test\x1b[5A");
    clearQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    applyQueue(&queue, &screen);
    feedQueueSlice(&queue, "more\x1b[1B");
    resetQueue(&queue);
    try std.testing.expect(queueIsEmpty(&queue));
    applyQueue(&queue, &screen);
}

test "zero-dim: rows=0, cols=8: cursor moves saturate, text/erase are safe no-ops" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(0, 8);
    feed(&queue, &screen, "\x1b[5C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x1b[3D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&queue, &screen, "hello");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
    feed(&queue, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "zero-dim: rows=8, cols=0: cursor moves saturate, text/erase are safe no-ops" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(8, 0);
    feed(&queue, &screen, "\x1b[3B");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "text");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u16, 1), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=0: all cursor moves saturate at origin, text/erase safe" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(0, 0);
    feed(&queue, &screen, "\x1b[999A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[999B");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[999C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[999D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "xyz");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[2J");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=8: CR/LF/BS control sequence determinism" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(0, 8);
    screen.cursor_col = 5;
    feed(&queue, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[3C");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_col);
    feed(&queue, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_col);
}

test "zero-dim: rows=8, cols=0: CR/LF/BS control sequence determinism" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(8, 0);
    screen.cursor_row = 3;
    feed(&queue, &screen, "\x0A");
    try std.testing.expectEqual(@as(u16, 4), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[2A");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x0D");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x08");
    try std.testing.expectEqual(@as(u16, 2), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=0: CUP absolute position saturates at origin" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(0, 0);
    feed(&queue, &screen, "\x1b[999;999H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\x1b[H");
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: rows=0, cols=10: repeated erase operations remain safe" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(0, 10);
    screen.cursor_col = 5;
    feed(&queue, &screen, "\x1b[K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x1b[2K");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x1b[J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x1b[1J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
    feed(&queue, &screen, "\x1b[2J");
    try std.testing.expectEqual(@as(u16, 5), screen.cursor_col);
}

test "zero-dim: rows=10, cols=0: repeated text writes remain safe" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = Grid.init(10, 0);
    screen.cursor_row = 3;
    feed(&queue, &screen, "test");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "\xC3\xA9");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
    feed(&queue, &screen, "more");
    try std.testing.expectEqual(@as(u16, 3), screen.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor_col);
}

test "zero-dim: tab commands remain safe across all zero-dimension variants" {
    const gpa = std.testing.allocator;

    var pl_rows0 = try Queue.init(gpa);
    defer pl_rows0.deinit();
    var screen_rows0 = Grid.init(0, 8);
    feed(&pl_rows0, &screen_rows0, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 0), screen_rows0.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_rows0.cursor_col);

    var pl_cols0 = try Queue.init(gpa);
    defer pl_cols0.deinit();
    var screen_cols0 = Grid.init(8, 0);
    screen_cols0.cursor_row = 3;
    feed(&pl_cols0, &screen_cols0, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 3), screen_cols0.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_cols0.cursor_col);

    var pl_zero = try Queue.init(gpa);
    defer pl_zero.deinit();
    var screen_zero = Grid.init(0, 0);
    feed(&pl_zero, &screen_zero, "\x09\x1b[2I\x1b[3Z");
    try std.testing.expectEqual(@as(u16, 0), screen_zero.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), screen_zero.cursor_col);
}

test "feed/apply: clear leaves snapshot unchanged" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "ABC");
    apply(&terminal);
    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    feedSlice(&terminal, "\x1b[H");
    clear(&terminal);

    var snap_after = try captureSnapshot(&terminal);
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
}

test "feed/apply: reset preserves snapshot state" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "HELLO");
    apply(&terminal);
    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    feedSlice(&terminal, "\x1b[H");
    reset(&terminal);

    var snap_after = try captureSnapshot(&terminal);
    defer snap_after.deinit();

    try std.testing.expectEqual(snap_before.cursor_col, snap_after.cursor_col);
    try std.testing.expectEqual(snap_before.cursor_row, snap_after.cursor_row);
    if (snap_before.cells != null and snap_after.cells != null) {
        const cell_count: u32 = @as(u32, snap_before.rows) * @as(u32, snap_before.cols);
        try std.testing.expectEqualSlices(u21, snap_before.cells.?[0..@intCast(cell_count)], snap_after.cells.?[0..@intCast(cell_count)]);
    }
}

test "feed/apply: resetScreen clears cells while preserving history" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(gpa, 3, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "LINE1\nLINE2\nLINE3\nLINE4");
    apply(&terminal);
    const hist_before = screen_set.visibleView(&terminal.screen_state, .{}).history_count;

    var snap_before = try captureSnapshot(&terminal);
    defer snap_before.deinit();

    terminal.screen_state.active().reset();

    var snap_after = try captureSnapshot(&terminal);
    defer snap_after.deinit();

    try std.testing.expectEqual(@as(u16, 0), snap_after.cursor_row);
    try std.testing.expectEqual(@as(u16, 0), snap_after.cursor_col);
    try std.testing.expectEqual(hist_before, snap_after.history_count);
    if (snap_after.cells != null) {
        const cell_count: u32 = @as(u32, snap_after.rows) * @as(u32, snap_after.cols);
        for (snap_after.cells.?[0..@intCast(cell_count)]) |cell| {
            try std.testing.expectEqual(@as(u21, 0), cell);
        }
    }
}

test "feed/apply: snapshot determinism across feed sequence variations" {
    const gpa = std.testing.allocator;

    var vt_core1 = try Terminal.initWithCells(gpa, 10, 20);
    defer vt_core1.deinit();
    feedSlice(&vt_core1, "\x1b[2J");
    feedSlice(&vt_core1, "Line1\nLine2");
    apply(&vt_core1);
    var snap1 = try captureSnapshot(&vt_core1);
    defer snap1.deinit();

    var vt_core2 = try Terminal.initWithCells(gpa, 10, 20);
    defer vt_core2.deinit();
    feedByte(&vt_core2, '\x1b');
    feedByte(&vt_core2, '[');
    feedByte(&vt_core2, '2');
    feedByte(&vt_core2, 'J');
    feedByte(&vt_core2, 'L');
    feedByte(&vt_core2, 'i');
    feedSlice(&vt_core2, "ne1\nLine2");
    apply(&vt_core2);
    var snap2 = try captureSnapshot(&vt_core2);
    defer snap2.deinit();

    try std.testing.expectEqual(snap1.cursor_row, snap2.cursor_row);
    try std.testing.expectEqual(snap1.cursor_col, snap2.cursor_col);
    if (snap1.cells != null and snap2.cells != null) {
        const cell_count: u32 = @as(u32, snap1.rows) * @as(u32, snap1.cols);
        try std.testing.expectEqualSlices(u21, snap1.cells.?[0..@intCast(cell_count)], snap2.cells.?[0..@intCast(cell_count)]);
    }
}

test "feed/apply: snapshot reflects mode changes" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "TEST");
    apply(&terminal);
    var snap1 = try captureSnapshot(&terminal);
    defer snap1.deinit();
    try std.testing.expectEqual(true, snap1.cursor_visible);

    feedSlice(&terminal, "\x1b[?25l");
    apply(&terminal);
    var snap2 = try captureSnapshot(&terminal);
    defer snap2.deinit();
    try std.testing.expectEqual(false, snap2.cursor_visible);

    feedSlice(&terminal, "\x1b[?25h");
    apply(&terminal);
    var snap3 = try captureSnapshot(&terminal);
    defer snap3.deinit();
    try std.testing.expectEqual(true, snap3.cursor_visible);
}

test "feed/apply: snapshot includes active selection endpoints" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();

    feedSlice(&terminal, "0123456789");
    apply(&terminal);

    selection.terminalStart(&terminal, 0, 2);
    selection.terminalUpdate(&terminal, 0, 7);
    selection.terminalFinish(&terminal);

    var snap = try captureSnapshot(&terminal);
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

test "feed/apply: snapshot parity across direct queue" {
    const gpa = std.testing.allocator;
    const test_bytes = "ABC\x1b[1;5HXY";

    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 5, 10);
    defer screen.deinit(gpa);

    feedQueueSlice(&queue, test_bytes);
    applyQueue(&queue, &screen);

    var terminal = try Terminal.initWithCells(gpa, 5, 10);
    defer terminal.deinit();
    feedSlice(&terminal, test_bytes);
    apply(&terminal);

    var snap = try captureSnapshot(&terminal);
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

test "feed/apply: snapshot wraparound history indices after eviction" {
    const gpa = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(gpa, 2, 5, 3);
    defer terminal.deinit();

    feedSlice(&terminal, "A\r\nB\r\nC\r\nD\r\nE");
    apply(&terminal);

    var snap = try captureSnapshot(&terminal);
    defer snap.deinit();

    try std.testing.expectEqual(@as(u16, 3), snap.history_capacity);
    try std.testing.expectEqual(3, snap.history_count);

    try std.testing.expect(snap.history != null);
    try std.testing.expectEqual(15, snap.history.?.len);

    try std.testing.expectEqual(@as(u21, 'C'), snap.historyRowAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), snap.historyRowAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'A'), snap.historyRowAt(2, 0));

    const history_count: u16 = @intCast(snap.history_count);
    var row: u16 = 0;
    while (row < history_count) : (row += 1) {
        var col: u16 = 0;
        while (col < snap.cols) : (col += 1) {
            try std.testing.expectEqual(screen_set.historyRowAt(&terminal.screen_state, row, col), snap.historyRowAt(row, col));
        }
    }
}

test "feed/apply: prompt redraw clears stale suffix after reset history entry" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 64);
    defer screen.deinit(gpa);

    const prompt = "$ ";

    repaintPromptLine(&queue, &screen, prompt, "ll");
    try expectPromptLine(&screen, prompt, "ll");

    repaintPromptLine(&queue, &screen, prompt, "reset");
    try expectPromptLine(&screen, prompt, "reset");

    repaintPromptLine(&queue, &screen, prompt, "ll");
    try expectPromptLine(&screen, prompt, "ll");

    repaintPromptLine(&queue, &screen, prompt, "reset");
    try expectPromptLine(&screen, prompt, "reset");

    repaintPromptLine(&queue, &screen, prompt, "ll");
    try expectPromptLine(&screen, prompt, "ll");
}

test "feed/apply: prompt redraw fuzz clears stale suffix across random history entries" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 96);
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

    var i: u8 = 0;
    while (i < 20) : (i += 1) {
        const command = commands[rand.uintLessThan(u8, commands.len)];
        repaintPromptLine(&queue, &screen, prompt, command);
        try expectPromptLine(&screen, prompt, command);
    }
}

test "feed/apply: bash history redraw with DCH clears reset suffix" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 64);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "reset");
    feed(&queue, &screen, "\x08\x08\x08\x08\x08\x1b[3Pll");

    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'l'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 4));
}

test "feed/apply: neovim colored empty cells through EL and ECH" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 10);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "\x1b[38;2;40;44;52m\x1b[48;2;40;44;52m~\x1b[K");
    feed(&queue, &screen, "\x1b[2;3H\x1b[6X");

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

test "feed/apply: DEC special graphics renders box drawing cells" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 8);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "\x1b(0lqkxmj\x1b(Bq");

    try std.testing.expectEqual(@as(u21, 0x250C), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 0x2500), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 0x2510), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0x2502), screen.cellAt(0, 3));
    try std.testing.expectEqual(@as(u21, 0x2514), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 0x2518), screen.cellAt(0, 5));
    try std.testing.expectEqual(@as(u21, 'q'), screen.cellAt(0, 6));
}

test "feed/apply: DEC special graphics G1 via SO SI" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 1, 4);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "\x1b)0\x0eq\x0fq");

    try std.testing.expectEqual(@as(u21, 0x2500), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'q'), screen.cellAt(0, 1));
}

test "feed/apply: SL SR and DECST8C execute from CSI syntax" {
    const gpa = std.testing.allocator;
    var queue = try Queue.init(gpa);
    defer queue.deinit();
    var screen = try Grid.initWithCells(gpa, 2, 20);
    defer screen.deinit(gpa);

    feed(&queue, &screen, "ABCDE\x1b[2 @");
    try std.testing.expectEqual(@as(u21, 'C'), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'D'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'E'), screen.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 3));

    feed(&queue, &screen, "\x1b[1;1HABCDE\x1b[1 A");
    try std.testing.expectEqual(@as(u21, 0), screen.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'A'), screen.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'D'), screen.cellAt(0, 4));
    try std.testing.expectEqual(@as(u21, 'E'), screen.cellAt(0, 5));

    feed(&queue, &screen, "\x1b[3g\x1b[?5W");
    try std.testing.expect(screen.tabStopAt(8));
    try std.testing.expect(screen.tabStopAt(16));
}
