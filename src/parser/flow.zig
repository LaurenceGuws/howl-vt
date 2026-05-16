//! Parser feed, parsed-event queue, and screen apply flow.

const std = @import("std");
const parser_mod = @import("../parser.zig");
const parsed_events_mod = @import("events.zig");

const ParserApi = parser_mod.Parser;

const Event = parsed_events_mod.Event;

/// Stateful parser-to-screen feed path.
pub const ApplyFlow = struct {
    allocator: std.mem.Allocator,
    parsed_events: *parsed_events_mod.ParsedEvents,
    parser: ParserApi,

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

    pub fn deinit(self: *ApplyFlow) void {
        self.parser.deinit();
        self.parsed_events.deinit();
        self.allocator.destroy(self.parsed_events);
    }

    pub fn feedByte(self: *ApplyFlow, byte: u8) void {
        self.parser.handleByte(byte);
    }

    pub fn feedSlice(self: *ApplyFlow, bytes: []const u8) void {
        self.parser.handleSlice(bytes);
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
        self.parsed_events.clear();
        self.parser.reset();
    }

    pub fn deccirCharsetState(self: *const ApplyFlow) @TypeOf(self.parser.deccirCharsetState()) {
        return self.parser.deccirCharsetState();
    }

};
