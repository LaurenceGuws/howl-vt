//! Parser feed and parsed-event queue.

const std = @import("std");
const parser_mod = @import("../parser.zig");
const parsed_events_mod = @import("events.zig");

const ParserApi = parser_mod.Parser;

const Event = parsed_events_mod.Event;

const FeedError = error{
    OutOfMemory,
    ParsedEventLimit,
    StringControlLimit,
};

/// Stateful parser feed and parsed-event queue owner.
pub const Queue = struct {
    allocator: std.mem.Allocator,
    parsed_events: parsed_events_mod.ParsedEvents,
    parser_action_arena: std.heap.ArenaAllocator,
    parser_actions: std.ArrayList(parser_mod.Action),
    parser: ParserApi,

    pub fn init(allocator: std.mem.Allocator) !Queue {
        var parsed_events = parsed_events_mod.ParsedEvents.init(allocator);
        errdefer parsed_events.deinit();

        var parser = try ParserApi.init(allocator);
        errdefer parser.deinit();

        var parser_actions = try std.ArrayList(parser_mod.Action).initCapacity(allocator, 16);
        errdefer parser_actions.deinit(allocator);
        return .{
            .allocator = allocator,
            .parsed_events = parsed_events,
            .parser_action_arena = std.heap.ArenaAllocator.init(allocator),
            .parser_actions = parser_actions,
            .parser = parser,
        };
    }

    pub fn deinit(self: *Queue) void {
        self.parser_actions.deinit(self.allocator);
        self.parser_action_arena.deinit();
        self.parser.deinit();
        self.parsed_events.deinit();
    }

    pub fn getAllocator(self: *const Queue) std.mem.Allocator {
        return self.allocator;
    }

    // Repo-local tests still use the convenience entrypoints below. The
    // shipped feed seam must use the checked variants so allocation failure
    // surfaces explicitly instead of dropping parser work.
    pub fn feedByte(self: *Queue, byte: u8) void {
        self.feedByteChecked(byte) catch unreachable;
    }

    pub fn feedByteChecked(self: *Queue, byte: u8) FeedError!void {
        self.clearParserActions();
        try appendOwnedPhases(self.allocator, self.parser_action_arena.allocator(), &self.parser_actions, try self.nextPhasesChecked(byte));
        try self.parsed_events.appendParserActions(self.parser_actions.items);
    }

    pub fn feedSlice(self: *Queue, bytes: []const u8) void {
        self.feedSliceChecked(bytes) catch unreachable;
    }

    pub fn feedSliceChecked(self: *Queue, bytes: []const u8) FeedError!void {
        self.clearParserActions();
        for (bytes) |byte| {
            try appendOwnedPhases(self.allocator, self.parser_action_arena.allocator(), &self.parser_actions, try self.nextPhasesChecked(byte));
        }
        try self.parsed_events.appendParserActions(self.parser_actions.items);
    }

    pub fn events(self: *const Queue) []const Event {
        return self.parsed_events.events.items;
    }

    pub fn eventCount(self: *const Queue) u32 {
        const count = self.parsed_events.len();
        std.debug.assert(count <= std.math.maxInt(u32));
        return @intCast(count);
    }

    pub fn prefix(self: *const Queue, count: u32) []const Event {
        std.debug.assert(count <= self.eventCount());
        return self.events()[0..@intCast(count)];
    }

    pub fn isEmpty(self: *const Queue) bool {
        return self.parsed_events.isEmpty();
    }

    /// Clear queued events without resetting parser state.
    pub fn clear(self: *Queue) void {
        self.parsed_events.clear();
    }

    pub fn dropPrefix(self: *Queue, count: u32) void {
        std.debug.assert(count <= self.eventCount());
        self.parsed_events.dropPrefix(count);
    }

    pub fn reset(self: *Queue) void {
        self.parsed_events.resetState();
        self.parser.reset();
    }

    pub fn deccirCharsetState(self: *const Queue) @TypeOf(self.parsed_events.deccirCharsetState()) {
        return self.parsed_events.deccirCharsetState();
    }

    fn clearParserActions(self: *Queue) void {
        self.parser_actions.clearRetainingCapacity();
        _ = self.parser_action_arena.reset(.retain_capacity);
    }

    fn nextPhasesChecked(self: *Queue, byte: u8) FeedError!parser_mod.PhaseActions {
        const phases = self.parser.next(byte);
        const failure = self.parser.takeStringControlFailed() orelse return phases;

        // No parsed events from the current feed call were published yet, so
        // drop the partial parser state and fail the whole feed explicitly.
        self.parser.reset();
        self.clearParserActions();
        return failure;
    }

};

pub fn appendOwnedPhases(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    actions: *std.ArrayList(parser_mod.Action),
    phases: parser_mod.PhaseActions,
) error{OutOfMemory}!void {
    for (phases) |phase| {
        if (phase) |action| try appendOwnedAction(allocator, arena, actions, action);
    }
}

fn appendOwnedAction(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    actions: *std.ArrayList(parser_mod.Action),
    action: parser_mod.Action,
) error{OutOfMemory}!void {
    switch (action) {
        .osc_dispatch => |osc| {
            const owned = try arena.dupe(u8, osc.data);
            try actions.append(allocator, .{ .osc_dispatch = .{ .data = owned, .term = osc.term } });
        },
        else => try actions.append(allocator, action),
    }
}
