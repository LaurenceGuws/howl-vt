//! Responsibility: orchestrate feed, queue, and apply flow.
//! Ownership: interpret pipeline control surface.
//! Reason: provide deterministic parser-to-screen event progression.

const std = @import("std");
const grid_owner = @import("../grid.zig");
const parser_owner = @import("../parser.zig");
const bridge_mod = @import("bridge.zig");
const semantic_mod = @import("semantic.zig");

const Grid = grid_owner.Grid;
const ParserApi = parser_owner.ParserApi;

/// Pipeline event alias.
const Event = bridge_mod.Event;

/// Parser/bridge orchestration surface.
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    bridge: *bridge_mod.Bridge,
    parser: ParserApi.Parser,

    /// Initialize pipeline resources.
    pub fn init(allocator: std.mem.Allocator) !Pipeline {
        const bridge = try allocator.create(bridge_mod.Bridge);
        bridge.* = bridge_mod.Bridge.init(allocator);
        errdefer {
            bridge.deinit();
            allocator.destroy(bridge);
        }
        const p = try ParserApi.Parser.init(allocator, bridge.toSink());
        return .{ .allocator = allocator, .bridge = bridge, .parser = p };
    }

    /// Release pipeline resources.
    pub fn deinit(self: *Pipeline) void {
        self.parser.deinit();
        self.bridge.deinit();
        self.allocator.destroy(self.bridge);
    }

    /// Feed one byte.
    pub fn feedByte(self: *Pipeline, byte: u8) void {
        self.parser.handleByte(byte);
    }

    /// Feed a byte slice.
    pub fn feedSlice(self: *Pipeline, bytes: []const u8) void {
        self.parser.handleSlice(bytes);
    }

    /// Return queued event slice.
    pub fn events(self: *const Pipeline) []const Event {
        return self.bridge.events.items;
    }

    /// Return queued event count.
    pub fn len(self: *const Pipeline) usize {
        return self.bridge.len();
    }

    /// Return true when queue is empty.
    pub fn isEmpty(self: *const Pipeline) bool {
        return self.bridge.isEmpty();
    }

    /// Clear queued events only.
    pub fn clear(self: *Pipeline) void {
        self.bridge.clear();
    }

    /// Reset parser state and queue.
    pub fn reset(self: *Pipeline) void {
        self.bridge.clear();
        self.parser.reset();
    }

    pub fn deccirCharsetState(self: *const Pipeline) @TypeOf(self.parser.deccirCharsetState()) {
        return self.parser.deccirCharsetState();
    }

    /// Apply queued events to screen.
    pub fn applyToScreen(self: *Pipeline, screen: *Grid.GridModel) void {
        for (self.bridge.events.items) |ev| {
            if (semantic_mod.process(ev)) |sem_ev| {
                screen.apply(sem_ev);
            }
        }
        self.bridge.clear();
    }
};

fn feed(pl: *Pipeline, screen: *Grid.GridModel, bytes: []const u8) void {
    pl.feedSlice(bytes);
    pl.applyToScreen(screen);
}
