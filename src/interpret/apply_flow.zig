//! Responsibility: orchestrate parser feed, event queue, and screen apply flow.
//! Ownership: interpret apply flow.
//! Reason: provide deterministic parser-to-screen action progression.

const std = @import("std");
const grid_mod = @import("../grid/grid.zig");
const parser_mod = @import("../parser/parser.zig");
const parser_events_mod = @import("parser_events.zig");
const actions_mod = @import("actions.zig");

const Grid = grid_mod;
const ParserApi = parser_mod.Parser;

/// ApplyFlow event alias.
const Event = parser_events_mod.Event;

/// Parser event apply-flow surface.
pub const ApplyFlow = struct {
    allocator: std.mem.Allocator,
    parser_events: *parser_events_mod.ParserEvents,
    parser: ParserApi,

    /// Initialize apply-flow resources.
    pub fn init(allocator: std.mem.Allocator) !ApplyFlow {
        const parser_events = try allocator.create(parser_events_mod.ParserEvents);
        parser_events.* = parser_events_mod.ParserEvents.init(allocator);
        errdefer {
            parser_events.deinit();
            allocator.destroy(parser_events);
        }
        const p = try ParserApi.init(allocator, parser_events.toSink());
        return .{ .allocator = allocator, .parser_events = parser_events, .parser = p };
    }

    /// Release apply-flow resources.
    pub fn deinit(self: *ApplyFlow) void {
        self.parser.deinit();
        self.parser_events.deinit();
        self.allocator.destroy(self.parser_events);
    }

    /// Feed one byte.
    pub fn feedByte(self: *ApplyFlow, byte: u8) void {
        self.parser.handleByte(byte);
    }

    /// Feed a byte slice.
    pub fn feedSlice(self: *ApplyFlow, bytes: []const u8) void {
        self.parser.handleSlice(bytes);
    }

    /// Return queued event slice.
    pub fn events(self: *const ApplyFlow) []const Event {
        return self.parser_events.events.items;
    }

    /// Return queued event count.
    pub fn len(self: *const ApplyFlow) usize {
        return self.parser_events.len();
    }

    /// Return true when queue is empty.
    pub fn isEmpty(self: *const ApplyFlow) bool {
        return self.parser_events.isEmpty();
    }

    /// Clear queued events only.
    pub fn clear(self: *ApplyFlow) void {
        self.parser_events.clear();
    }

    /// Reset parser state and queue.
    pub fn reset(self: *ApplyFlow) void {
        self.parser_events.clear();
        self.parser.reset();
    }

    pub fn deccirCharsetState(self: *const ApplyFlow) @TypeOf(self.parser.deccirCharsetState()) {
        return self.parser.deccirCharsetState();
    }

    /// Apply queued events to screen.
    pub fn applyToScreen(self: *ApplyFlow, screen: *Grid.GridModel) void {
        for (self.parser_events.events.items) |ev| {
            if (actions_mod.process(ev)) |sem_ev| {
                if (actions_mod.screenAction(sem_ev)) |screen_ev| screen.applyScreen(screen_ev);
            }
        }
        self.parser_events.clear();
    }
};

fn feed(flow: *ApplyFlow, screen: *Grid.GridModel, bytes: []const u8) void {
    flow.feedSlice(bytes);
    flow.applyToScreen(screen);
}
