const std = @import("std");
const route = @import("action/route.zig");
const parsed_events = @import("parser/events.zig");
const parser_mod = @import("parser/main.zig");
const terminal_mod = @import("terminal.zig");

pub const FeedError = error{
    ConsequenceLimit,
    OutOfMemory,
    ParsedEventLimit,
    StringControlLimit,
};

pub const FeedSummary = struct {
    state_changed: bool,
    latest_title: ?[]const u8,
};

pub const State = struct {
    parser: parser_mod.Parser,
    events: parsed_events.ParsedEvents,

    pub fn initAlloc(allocator: std.mem.Allocator) !State {
        var parser = try parser_mod.Parser.init(allocator);
        errdefer parser.deinit();
        return .{
            .parser = parser,
            .events = parsed_events.ParsedEvents.init(allocator),
        };
    }

    pub fn deinit(self: *State) void {
        self.events.deinit();
        self.parser.deinit();
    }
};

pub const Stream = struct {
    terminal: *terminal_mod.Terminal,

    pub fn init(terminal: *terminal_mod.Terminal) Stream {
        return .{ .terminal = terminal };
    }

    pub fn deinit(_: *Stream) void {
    }

    pub fn next(self: *Stream, byte: u8) FeedError!void {
        _ = try self.nextSummary(byte);
    }

    pub fn nextSlice(self: *Stream, bytes: []const u8) FeedError!void {
        _ = try self.nextSliceSummary(bytes);
    }

    pub fn nextSummary(self: *Stream, byte: u8) FeedError!FeedSummary {
        var latest_title: ?[]const u8 = null;
        var state_changed = false;
        const state = &self.terminal.stream_state;

        const batch = state.events.beginBatch();
        errdefer state.events.rollbackBatch(batch);
        errdefer state.parser.reset();

        const phases = state.parser.next(byte);
        if (state.parser.takeStringControlFailed()) |err| return err;
        try state.events.appendPhases(batch, phases);
        state.events.finishBatch(batch);

        while (state.events.front()) |event_| {
            const effect = try route.apply(self.terminal, latest_title, event_);
            state_changed = state_changed or effect.changed;
            latest_title = effect.latest_title;
            state.events.popFront();
        }

        self.finishTurn();
        return .{ .state_changed = state_changed, .latest_title = latest_title };
    }

    pub fn nextSliceSummary(self: *Stream, bytes: []const u8) FeedError!FeedSummary {
        var summary: FeedSummary = .{ .state_changed = false, .latest_title = null };
        for (bytes) |byte| {
            const byte_summary = try self.nextSummary(byte);
            summary.state_changed = summary.state_changed or byte_summary.state_changed;
            if (byte_summary.latest_title) |title| summary.latest_title = title;
        }
        return summary;
    }

    fn finishTurn(self: *Stream) void {
        self.terminal.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.terminal.screen_state.activeConst(),
        );
    }
};
