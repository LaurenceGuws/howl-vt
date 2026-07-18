const std = @import("std");
const parsed_events = @import("parser/events.zig");
const route = @import("route.zig");
const parser_mod = @import("parser.zig");
const terminal_mod = @import("terminal.zig");

const Event = parsed_events.Event;

pub const FeedError = error{
    ConsequenceLimit,
    OutOfMemory,
    ParsedEventLimit,
    StringControlLimit,
};

pub const FeedSummary = struct {
    state_changed: bool,
    title_changed: bool,
};

const BoundedStringControl = struct {
    active: bool = false,
    count: u32 = 0,

    pub fn reset(self: *BoundedStringControl) void {
        self.active = false;
        self.count = 0;
    }

    pub fn start(self: *BoundedStringControl) void {
        self.active = true;
        self.count = 0;
    }

    pub fn put(self: *BoundedStringControl, limit: u32) !void {
        std.debug.assert(self.active);
        if (self.count >= limit) return error.StringControlLimit;
        self.count += 1;
    }
};

const DcsCapture = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayList(u8),
    params: [parser_mod.max_params]i32 = [_]i32{0} ** parser_mod.max_params,
    intermediates: [parser_mod.max_intermediates]u8 = [_]u8{0} ** parser_mod.max_intermediates,
    payload_start: usize = 0,
    final: u8 = 0,
    param_count: u8 = 0,
    intermediates_len: u8 = 0,
    active: bool = false,

    pub fn init(allocator: std.mem.Allocator) DcsCapture {
        return .{ .allocator = allocator, .bytes = .empty };
    }

    pub fn deinit(self: *DcsCapture) void {
        self.bytes.deinit(self.allocator);
    }

    pub fn reset(self: *DcsCapture) void {
        self.active = false;
        self.payload_start = 0;
        self.final = 0;
        self.param_count = 0;
        self.intermediates_len = 0;
        self.bytes.clearRetainingCapacity();
    }

    pub fn start(self: *DcsCapture, hook: parser_mod.DcsHook) !void {
        std.debug.assert(hook.count <= parser_mod.max_params);
        std.debug.assert(hook.intermediates_len <= parser_mod.max_intermediates);
        self.reset();
        self.active = true;
        self.final = hook.final;
        self.param_count = hook.count;
        self.intermediates_len = hook.intermediates_len;
        std.mem.copyForwards(i32, self.params[0..hook.count], hook.params[0..hook.count]);
        std.mem.copyForwards(u8, self.intermediates[0..hook.intermediates_len], hook.intermediates[0..hook.intermediates_len]);

        errdefer self.reset();
        var idx: u8 = 0;
        while (idx < hook.count) : (idx += 1) {
            if (idx > 0) try self.bytes.append(self.allocator, ';');
            var text_buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buf, "{d}", .{hook.params[idx]}) catch unreachable;
            try self.bytes.appendSlice(self.allocator, text);
        }
        try self.bytes.appendSlice(self.allocator, self.intermediates[0..hook.intermediates_len]);
        try self.bytes.append(self.allocator, hook.final);
        self.payload_start = self.bytes.items.len;
    }

    pub fn put(self: *DcsCapture, byte: u8) !void {
        std.debug.assert(self.active);
        if (self.bytes.items.len - self.payload_start >= @as(usize, parser_mod.max_metadata_control_bytes)) {
            return error.StringControlLimit;
        }
        try self.bytes.append(self.allocator, byte);
    }

    pub fn event(self: *const DcsCapture) Event {
        std.debug.assert(self.active);
        return .{ .dcs = .{
            .body = self.bytes.items,
            .payload = self.bytes.items[self.payload_start..],
            .final = self.final,
            .params = self.params[0..self.param_count],
            .param_count = self.param_count,
            .intermediates = self.intermediates[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        } };
    }
};

pub const TerminalStreamState = struct {
    parser: parser_mod.Parser,
    dcs: DcsCapture,
    apc: BoundedStringControl,
    pm: BoundedStringControl,

    pub fn initAlloc(allocator: std.mem.Allocator) !TerminalStreamState {
        var parser = try parser_mod.Parser.init(allocator);
        errdefer parser.deinit();
        return .{
            .parser = parser,
            .dcs = DcsCapture.init(allocator),
            .apc = .{},
            .pm = .{},
        };
    }

    pub fn deinit(self: *TerminalStreamState) void {
        self.dcs.deinit();
        self.parser.deinit();
    }
};

pub const Stream = struct {
    terminal: *terminal_mod.Terminal,

    pub fn init(terminal: *terminal_mod.Terminal) Stream {
        return .{ .terminal = terminal };
    }

    pub fn deinit(_: *Stream) void {}

    pub fn next(self: *Stream, byte: u8) FeedError!void {
        _ = try self.nextSummary(byte);
    }

    pub fn nextSlice(self: *Stream, bytes: []const u8) FeedError!void {
        _ = try self.nextSliceSummary(bytes);
    }

    pub fn nextSummary(self: *Stream, byte: u8) FeedError!FeedSummary {
        var state_changed = false;
        var title_changed = false;
        const state = &self.terminal.stream_state;

        errdefer {
            state.parser.reset();
            state.dcs.reset();
            state.apc.reset();
            state.pm.reset();
        }

        const phases = state.parser.next(byte);
        if (state.parser.takeStringControlFailed()) |err| return err;

        for (phases) |phase| {
            if (phase) |action| {
                const effect = try self.applyAction(action);
                state_changed = state_changed or effect.changed;
                title_changed = title_changed or effect.title_changed;
            }
        }

        return .{ .state_changed = state_changed, .title_changed = title_changed };
    }

    pub fn nextSliceSummary(self: *Stream, bytes: []const u8) FeedError!FeedSummary {
        var summary: FeedSummary = .{ .state_changed = false, .title_changed = false };
        for (bytes) |byte| {
            const byte_summary = try self.nextSummary(byte);
            summary.state_changed = summary.state_changed or byte_summary.state_changed;
            summary.title_changed = summary.title_changed or byte_summary.title_changed;
        }
        return summary;
    }

    fn applyAction(self: *Stream, action: parser_mod.Action) FeedError!route.EventEffect {
        return switch (action) {
            .print => |cp| self.applyPrint(cp),
            .execute => |ctrl| self.applyExecute(ctrl),
            .invalid => try self.applyEvent(.invalid_sequence),
            .csi_dispatch => |csi| try self.applyEvent(.{ .style_change = .{
                .final = csi.final,
                .params = csi.params[0..csi.count],
                .separators = csi.separators,
                .param_count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = csi.intermediates[0..csi.intermediates_len],
                .intermediates_len = csi.intermediates_len,
            } }),
            .osc_dispatch => |osc| try self.applyEvent(.{ .osc = osc }),
            .apc_start => self.startBoundedStringControl(&self.terminal.stream_state.apc),
            .apc_put => |byte| self.putBoundedStringControl(&self.terminal.stream_state.apc, byte, parser_mod.max_apc_control_bytes),
            .apc_end => self.endBoundedStringControl(&self.terminal.stream_state.apc),
            .dcs_hook => |hook| self.startDcs(hook),
            .dcs_put => |byte| self.putDcs(byte),
            .dcs_unhook => self.endDcs(),
            .pm_start => self.startBoundedStringControl(&self.terminal.stream_state.pm),
            .pm_put => |byte| self.putBoundedStringControl(&self.terminal.stream_state.pm, byte, parser_mod.max_metadata_control_bytes),
            .pm_end => self.endBoundedStringControl(&self.terminal.stream_state.pm),
            .esc_dispatch => |esc| self.applyEsc(esc),
        };
    }

    fn applyPrint(self: *Stream, cp: u21) FeedError!route.EventEffect {
        const mapped = self.mapCodepoint(cp);
        if (mapped <= 0x7f) {
            const ascii: [1]u8 = .{@intCast(mapped)};
            return try self.applyEvent(.{ .text = ascii[0..] });
        }
        return try self.applyEvent(.{ .codepoint = mapped });
    }

    fn applyExecute(self: *Stream, ctrl: u8) FeedError!route.EventEffect {
        switch (ctrl) {
            0x0E => {
                self.terminal.gl_index = 1;
                return .{ .changed = true, .title_changed = false };
            },
            0x0F => {
                self.terminal.gl_index = 0;
                return .{ .changed = true, .title_changed = false };
            },
            else => return try self.applyEvent(.{ .control = ctrl }),
        }
    }

    fn applyEsc(self: *Stream, esc: parser_mod.EscAction) FeedError!route.EventEffect {
        if (esc.intermediates_len == 1) {
            switch (esc.intermediates[0]) {
                '(' => {
                    self.terminal.g0_designation = esc.final;
                    return .{ .changed = true, .title_changed = false };
                },
                ')' => {
                    self.terminal.g1_designation = esc.final;
                    return .{ .changed = true, .title_changed = false };
                },
                else => {},
            }
        }
        return try self.applyEvent(.{ .esc_dispatch = esc });
    }

    fn applyEvent(self: *Stream, event: Event) FeedError!route.EventEffect {
        return try route.apply(self.terminal, event);
    }

    fn startDcs(self: *Stream, hook: parser_mod.DcsHook) FeedError!route.EventEffect {
        try self.terminal.stream_state.dcs.start(hook);
        return .{ .changed = false, .title_changed = false };
    }

    fn putDcs(self: *Stream, byte: u8) FeedError!route.EventEffect {
        try self.terminal.stream_state.dcs.put(byte);
        return .{ .changed = false, .title_changed = false };
    }

    fn endDcs(self: *Stream) FeedError!route.EventEffect {
        const state = &self.terminal.stream_state;
        const event = state.dcs.event();
        defer state.dcs.reset();
        return try route.apply(self.terminal, event);
    }

    fn startBoundedStringControl(self: *Stream, control: *BoundedStringControl) route.EventEffect {
        _ = self;
        control.start();
        return .{ .changed = false, .title_changed = false };
    }

    fn putBoundedStringControl(self: *Stream, control: *BoundedStringControl, byte: u8, limit: u32) FeedError!route.EventEffect {
        _ = self;
        _ = byte;
        try control.put(limit);
        return .{ .changed = false, .title_changed = false };
    }

    fn endBoundedStringControl(self: *Stream, control: *BoundedStringControl) route.EventEffect {
        _ = self;
        control.reset();
        return .{ .changed = false, .title_changed = false };
    }

    fn mapCodepoint(self: *const Stream, cp: u21) u21 {
        if (!isDecSpecial(self.terminal)) return cp;
        if (cp < 0x20 or cp > 0x7e) return cp;
        return mapDecSpecial(@intCast(cp));
    }
};

fn isDecSpecial(terminal: *const terminal_mod.Terminal) bool {
    return switch (terminal.gl_index) {
        0 => terminal.g0_designation == '0',
        1 => terminal.g1_designation == '0',
        else => false,
    };
}

fn mapDecSpecial(byte: u8) u21 {
    return switch (byte) {
        '`' => 0x25C6,
        'a' => 0x2592,
        'f' => 0x00B0,
        'g' => 0x00B1,
        'h' => 0x2424,
        'i' => 0x240B,
        'j' => 0x2518,
        'k' => 0x2510,
        'l' => 0x250C,
        'm' => 0x2514,
        'n' => 0x253C,
        'o' => 0x23BA,
        'p' => 0x23BB,
        'q' => 0x2500,
        'r' => 0x23BC,
        's' => 0x23BD,
        't' => 0x251C,
        'u' => 0x2524,
        'v' => 0x2534,
        'w' => 0x252C,
        'x' => 0x2502,
        'y' => 0x2264,
        'z' => 0x2265,
        '{' => 0x03C0,
        '|' => 0x2260,
        '}' => 0x00A3,
        '~' => 0x00B7,
        else => byte,
    };
}

test "ignored APC bytes enforce the exact tolerance and reset" {
    var control: BoundedStringControl = .{};
    control.start();
    control.count = parser_mod.max_apc_control_bytes - 1;

    try control.put(parser_mod.max_apc_control_bytes);
    try std.testing.expectEqual(parser_mod.max_apc_control_bytes, control.count);
    try std.testing.expectError(
        error.StringControlLimit,
        control.put(parser_mod.max_apc_control_bytes),
    );

    control.reset();
    try std.testing.expect(!control.active);
    try std.testing.expectEqual(@as(u32, 0), control.count);
    control.start();
    try control.put(parser_mod.max_apc_control_bytes);
    try std.testing.expectEqual(@as(u32, 1), control.count);
}

test "ignored PM bytes enforce the exact tolerance and reset" {
    var control: BoundedStringControl = .{};
    control.start();
    control.count = parser_mod.max_metadata_control_bytes - 1;

    try control.put(parser_mod.max_metadata_control_bytes);
    try std.testing.expectEqual(parser_mod.max_metadata_control_bytes, control.count);
    try std.testing.expectError(
        error.StringControlLimit,
        control.put(parser_mod.max_metadata_control_bytes),
    );

    control.reset();
    try std.testing.expect(!control.active);
    try std.testing.expectEqual(@as(u32, 0), control.count);
    control.start();
    try control.put(parser_mod.max_metadata_control_bytes);
    try std.testing.expectEqual(@as(u32, 1), control.count);
}
