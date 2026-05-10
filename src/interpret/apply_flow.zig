//! Responsibility: orchestrate parser feed, event queue, and screen apply flow.
//! Ownership: interpret apply flow.
//! Reason: provide deterministic parser-to-screen action progression.

const std = @import("std");
const grid_mod = @import("../grid/grid.zig");
const parser_mod = @import("../parser/parser.zig");
const parsed_events_mod = @import("parsed_events.zig");
const action_map = @import("actions/map.zig");

const Grid = grid_mod.Grid;
const ParserApi = parser_mod.Parser;

/// ApplyFlow event alias.
const Event = parsed_events_mod.Event;

/// Parsed event apply-flow surface.
pub const ApplyFlow = struct {
    allocator: std.mem.Allocator,
    parsed_events: *parsed_events_mod.ParsedEvents,
    parser: ParserApi,

    /// Initialize apply-flow resources.
    pub fn init(allocator: std.mem.Allocator) !ApplyFlow {
        const parsed_events = try allocator.create(parsed_events_mod.ParsedEvents);
        parsed_events.* = parsed_events_mod.ParsedEvents.init(allocator);
        errdefer {
            parsed_events.deinit();
            allocator.destroy(parsed_events);
        }
        const p = try ParserApi.init(allocator, parsed_events.toSink());
        return .{ .allocator = allocator, .parsed_events = parsed_events, .parser = p };
    }

    /// Release apply-flow resources.
    pub fn deinit(self: *ApplyFlow) void {
        self.parser.deinit();
        self.parsed_events.deinit();
        self.allocator.destroy(self.parsed_events);
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
        return self.parsed_events.events.items;
    }

    /// Return queued event count.
    pub fn len(self: *const ApplyFlow) usize {
        return self.parsed_events.len();
    }

    /// Return true when queue is empty.
    pub fn isEmpty(self: *const ApplyFlow) bool {
        return self.parsed_events.isEmpty();
    }

    /// Clear queued events only.
    pub fn clear(self: *ApplyFlow) void {
        self.parsed_events.clear();
    }

    /// Reset parser state and queue.
    pub fn reset(self: *ApplyFlow) void {
        self.parsed_events.clear();
        self.parser.reset();
    }

    pub fn deccirCharsetState(self: *const ApplyFlow) @TypeOf(self.parser.deccirCharsetState()) {
        return self.parser.deccirCharsetState();
    }

    /// Apply queued events to screen.
    pub fn applyToScreen(self: *ApplyFlow, screen: *Grid) void {
        for (self.parsed_events.events.items) |ev| {
            if (action_map.process(ev)) |sem_ev| {
                if (action_map.screenAction(sem_ev)) |screen_ev| screen.applyScreen(screen_ev);
            }
        }
        self.parsed_events.clear();
    }
};

fn feed(flow: *ApplyFlow, screen: *Grid, bytes: []const u8) void {
    flow.feedSlice(bytes);
    flow.applyToScreen(screen);
}
