//! Parser feed, parsed-event queue, and screen apply flow.

const std = @import("std");
const parser_mod = @import("../parser.zig");
const parsed_events_mod = @import("events.zig");

const ParserApi = parser_mod.Parser;

const Event = parsed_events_mod.Event;

pub const State = struct {
    apply_flow: ApplyFlow,

    pub fn getAllocator(self: *const State) std.mem.Allocator {
        return self.apply_flow.allocator;
    }

    pub fn init(allocator: std.mem.Allocator) !State {
        return .{ .apply_flow = try ApplyFlow.init(allocator) };
    }

    pub fn deinit(self: *State) void {
        self.apply_flow.deinit();
    }
};

/// Stateful parser-to-screen feed path.
pub const ApplyFlow = struct {
    allocator: std.mem.Allocator,
    parsed_events: *parsed_events_mod.ParsedEvents,
    parser_action_arena: std.heap.ArenaAllocator,
    parser_actions: std.ArrayList(parser_mod.Action),
    parser: ParserApi,

    pub fn init(allocator: std.mem.Allocator) !ApplyFlow {
        const parsed_events = try allocator.create(parsed_events_mod.ParsedEvents);
        parsed_events.* = parsed_events_mod.ParsedEvents.init(allocator);
        errdefer {
            parsed_events.deinit();
            allocator.destroy(parsed_events);
        }
        const p = try ParserApi.init(allocator);
        var parser_actions = try std.ArrayList(parser_mod.Action).initCapacity(allocator, 16);
        errdefer parser_actions.deinit(allocator);
        return .{
            .allocator = allocator,
            .parsed_events = parsed_events,
            .parser_action_arena = std.heap.ArenaAllocator.init(allocator),
            .parser_actions = parser_actions,
            .parser = p,
        };
    }

    pub fn deinit(self: *ApplyFlow) void {
        self.parser_actions.deinit(self.allocator);
        self.parser_action_arena.deinit();
        self.parser.deinit();
        self.parsed_events.deinit();
        self.allocator.destroy(self.parsed_events);
    }

    // Repo-local tests still use the convenience entrypoints below. The
    // shipped feed seam must use the checked variants so allocation failure
    // surfaces explicitly instead of dropping parser work.
    pub fn feedByte(self: *ApplyFlow, byte: u8) void {
        self.feedByteChecked(byte) catch unreachable;
    }

    pub fn feedByteChecked(self: *ApplyFlow, byte: u8) error{OutOfMemory}!void {
        self.clearParserActions();
        try appendOwnedPhases(self.allocator, self.parser_action_arena.allocator(), &self.parser_actions, self.parser.next(byte));
        try self.parsed_events.appendParserActions(self.parser_actions.items);
    }

    pub fn feedSlice(self: *ApplyFlow, bytes: []const u8) void {
        self.feedSliceChecked(bytes) catch unreachable;
    }

    pub fn feedSliceChecked(self: *ApplyFlow, bytes: []const u8) error{OutOfMemory}!void {
        self.clearParserActions();
        for (bytes) |byte| {
            try appendOwnedPhases(self.allocator, self.parser_action_arena.allocator(), &self.parser_actions, self.parser.next(byte));
        }
        try self.parsed_events.appendParserActions(self.parser_actions.items);
    }

    pub fn events(self: *const ApplyFlow) []const Event {
        return self.parsed_events.events.items;
    }

    pub fn len(self: *const ApplyFlow) usize {
        return self.parsed_events.len();
    }

    pub fn isEmpty(self: *const ApplyFlow) bool {
        return self.parsed_events.isEmpty();
    }

    /// Clear queued events without resetting parser state.
    pub fn clear(self: *ApplyFlow) void {
        self.parsed_events.clear();
    }

    pub fn reset(self: *ApplyFlow) void {
        self.parsed_events.resetState();
        self.parser.reset();
    }

    pub fn deccirCharsetState(self: *const ApplyFlow) @TypeOf(self.parsed_events.deccirCharsetState()) {
        return self.parsed_events.deccirCharsetState();
    }

    fn clearParserActions(self: *ApplyFlow) void {
        self.parser_actions.clearRetainingCapacity();
        _ = self.parser_action_arena.reset(.retain_capacity);
    }

};

pub fn feedByte(vt: anytype, byte: u8) error{OutOfMemory}!void {
    try vt.parser_state.apply_flow.feedByteChecked(byte);
}

pub fn feedSlice(vt: anytype, bytes: []const u8) error{OutOfMemory}!void {
    try vt.parser_state.apply_flow.feedSliceChecked(bytes);
}

pub fn clear(vt: anytype) void {
    vt.parser_state.apply_flow.clear();
}

pub fn reset(vt: anytype) void {
    vt.parser_state.apply_flow.reset();
}

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
