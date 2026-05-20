//! Parser feed and parsed-event queue.

const std = @import("std");
const parser_mod = @import("main.zig");
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
    parsed_events: parsed_events_mod.ParsedEvents,
    parser: ParserApi,

    pub fn init(allocator: std.mem.Allocator) !Queue {
        var parsed_events = parsed_events_mod.ParsedEvents.init(allocator);
        errdefer parsed_events.deinit();

        var parser = try ParserApi.init(allocator);
        errdefer parser.deinit();
        return .{
            .parsed_events = parsed_events,
            .parser = parser,
        };
    }

    pub fn deinit(self: *Queue) void {
        self.parser.deinit();
        self.parsed_events.deinit();
    }

    pub fn feedSlice(self: *Queue, bytes: []const u8) FeedError!void {
        const batch = self.parsed_events.beginBatch();
        errdefer self.parsed_events.rollbackBatch(batch);
        errdefer self.parser.reset();
        for (bytes) |byte| {
            try self.parsed_events.appendPhases(batch, try self.nextPhasesChecked(byte));
        }
        self.parsed_events.finishBatch(batch);
    }

    pub fn eventCount(self: *const Queue) u32 {
        return self.parsed_events.eventCount();
    }

    pub fn iterator(self: *const Queue) parsed_events_mod.ParsedEvents.Iterator {
        return self.parsed_events.iterator();
    }

    pub fn dropPrefix(self: *Queue, count: u32) void {
        self.parsed_events.dropPrefix(count);
    }

    pub fn front(self: *const Queue) ?Event {
        return self.parsed_events.front();
    }

    pub fn popFront(self: *Queue) void {
        self.parsed_events.popFront();
    }

    pub fn deccirCharsetState(self: *const Queue) parser_mod.DeccirCharsetState {
        return self.parsed_events.deccirCharsetState();
    }

    fn nextPhasesChecked(self: *Queue, byte: u8) FeedError!parser_mod.PhaseActions {
        const phases = self.parser.next(byte);
        return self.parser.takeStringControlFailed() orelse phases;
    }

};
