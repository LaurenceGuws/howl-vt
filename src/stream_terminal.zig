const std = @import("std");
const host = @import("host/apply.zig");
const kitty = @import("kitty/apply.zig");
const mode = @import("control/mode.zig");
const report = @import("control/report.zig");
const route = @import("action/route.zig");
const parsed_events = @import("parser/events.zig");
const parser_mod = @import("parser/main.zig");
const terminal_mod = @import("terminal.zig");

pub const FeedError = error{
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

pub const Handler = struct {
    terminal: *terminal_mod.Terminal,

    pub fn init(terminal: *terminal_mod.Terminal) Handler {
        return .{ .terminal = terminal };
    }

    pub fn event(self: *Handler, event_: parsed_events.Event) void {
        _ = self.eventWithLatestTitle(null, event_);
    }

    pub fn eventWithLatestTitle(
        self: *Handler,
        current: ?[]const u8,
        event_: parsed_events.Event,
    ) ?[]const u8 {
        const latest = self.latestTitle(current, event_);
        self.applyEvent(event_);
        return latest;
    }

    pub fn finishTurn(self: *Handler) void {
        self.terminal.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.terminal.screen_state.activeConst(),
        );
    }

    fn latestTitle(self: *Handler, current: ?[]const u8, event_: parsed_events.Event) ?[]const u8 {
        switch (event_) {
            .osc => |osc_event| switch (osc_event) {
                .title, .raw_title => {
                    const owned = self.terminal.allocator.dupe(u8, osc_event.payload()) catch return current;
                    if (self.terminal.host.current_title) |old| self.terminal.allocator.free(old);
                    self.terminal.host.current_title = owned;
                    return owned;
                },
                else => return current,
            },
            else => return current,
        }
    }

    fn applyEvent(self: *Handler, event_: parsed_events.Event) void {
        switch (event_) {
            .invoke_charset => |slot| {
                self.terminal.gl_index = slot;
                return;
            },
            .configure_charset => |cfg| {
                switch (cfg.slot) {
                    0 => self.terminal.g0_designation = cfg.designation,
                    1 => self.terminal.g1_designation = cfg.designation,
                    else => unreachable,
                }
                return;
            },
            else => {},
        }
        const sem_ev = route.process(event_) orelse return;
        if (route.reportAction(sem_ev)) |report_action| {
            report.apply(self.terminal, report_action);
            return;
        }
        if (route.kittyAction(sem_ev)) |kitty_action| {
            kitty.apply(self.terminal, kitty_action);
            return;
        }
        if (route.modeAction(sem_ev)) |mode_action| {
            mode.apply(self.terminal, mode_action);
            return;
        }
        if (route.hostAction(sem_ev)) |host_action| {
            host.apply(self.terminal, host_action);
            return;
        }
        const screen_ev = route.screenAction(sem_ev) orelse unreachable;
        self.terminal.screen_state.active().applyScreen(screen_ev);
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
        var handler = self.terminal.vtHandler();
        const state = &self.terminal.stream_state;

        const batch = state.events.beginBatch();
        errdefer state.events.rollbackBatch(batch);
        errdefer state.parser.reset();

        const phases = state.parser.next(byte);
        if (state.parser.takeStringControlFailed()) |err| return err;
        try state.events.appendPhases(batch, phases);
        state.events.finishBatch(batch);

        while (state.events.front()) |event_| {
            state_changed = true;
            latest_title = handler.eventWithLatestTitle(latest_title, event_);
            state.events.popFront();
        }

        handler.finishTurn();
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
};
