//! Responsibility: collect parser callbacks into owned interpreted records.
//! Ownership: parser-to-interpret boundary.
//! Reason: isolate parser sink mechanics from downstream processing.

const std = @import("std");
const parser_owner = @import("../parser.zig");

const ParserApi = parser_owner.ParserApi;

/// Parser-facing bridge event union.
pub const Event = union(enum) {
    text: []const u8,
    codepoint: u21,
    control: u8,
    style_change: struct {
        final: u8,
        params: [16]i32,
        separators: [16]u8 = [_]u8{0} ** 16,
        param_count: u8,
        leader: u8,
        private: bool,
        intermediates: [ParserApi.max_intermediates]u8,
        intermediates_len: u8,
    },
    osc: struct {
        kind: OscKind,
        command: ?u16,
        payload: []const u8,
        terminator: ParserApi.OscTerminator,
    },
    apc: []const u8,
    dcs: []const u8,
    pm: []const u8,
    esc_final: u8,
    invalid_sequence,
};

pub const OscKind = enum {
    title,
    clipboard,
    hyperlink,
    generic,
};

/// Owned event queue bridge for parser sink callbacks.
pub const Bridge = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    events: std.ArrayList(Event),

    /// Initialize bridge queue.
    pub fn init(allocator: std.mem.Allocator) Bridge {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .allocator = allocator,
            .arena = arena,
            .events = std.ArrayList(Event).initCapacity(allocator, 32) catch unreachable,
        };
    }

    /// Release bridge queue storage.
    pub fn deinit(self: *Bridge) void {
        self.clear();
        self.events.deinit(self.allocator);
        self.arena.deinit();
    }

    /// Return queued event count.
    pub fn len(self: *const Bridge) usize {
        return self.events.items.len;
    }

    /// Return true when queue is empty.
    pub fn isEmpty(self: *const Bridge) bool {
        return self.events.items.len == 0;
    }

    /// Clear queued events and free owned payloads.
    pub fn clear(self: *Bridge) void {
        self.events.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
    }

    /// Drain queued events into destination list.
    pub fn drainInto(self: *Bridge, dest: *std.ArrayList(Event), dest_allocator: std.mem.Allocator) !void {
        try dest.appendSlice(dest_allocator, self.events.items);
        self.events.clearRetainingCapacity();
    }

    /// Build parser sink bound to this bridge.
    pub fn toSink(self: *Bridge) ParserApi.Sink {
        return .{
            .ptr = self,
            .onStreamEventFn = onStreamEvent,
            .onAsciiSliceFn = onAsciiSlice,
            .onCsiFn = onCsi,
            .onOscFn = onOsc,
            .onApcFn = onApc,
            .onDcsFn = onDcs,
            .onPmFn = onPm,
            .onEscFinalFn = onEscFinal,
        };
    }

    fn onStreamEvent(ptr: *anyopaque, event: ParserApi.StreamEvent) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const ce = switch (event) {
            .codepoint => |cp| Event{ .codepoint = cp },
            .control => |ctrl| Event{ .control = ctrl },
            .invalid => Event.invalid_sequence,
        };
        self.events.append(self.allocator, ce) catch {};
    }

    fn onAsciiSlice(ptr: *anyopaque, bytes: []const u8) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        if (bytes.len == 1) {
            self.events.append(self.allocator, Event{ .codepoint = bytes[0] }) catch {};
            return;
        }
        const owned = self.arena.allocator().dupe(u8, bytes) catch return;
        self.events.append(self.allocator, Event{ .text = owned }) catch {};
    }

    fn onCsi(ptr: *anyopaque, action: ParserApi.CsiAction) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{
            .style_change = .{
                .final = action.final,
                .params = action.params,
                .separators = action.separators,
                .param_count = action.count,
                .leader = action.leader,
                .private = action.private,
                .intermediates = action.intermediates,
                .intermediates_len = action.intermediates_len,
            },
        }) catch {};
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, term: ParserApi.OscTerminator) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const parsed = parseOsc(data);
        const owned = self.arena.allocator().dupe(u8, parsed.payload) catch return;
        self.events.append(self.allocator, Event{ .osc = .{
            .kind = parsed.kind,
            .command = parsed.command,
            .payload = owned,
            .terminator = term,
        } }) catch {};
    }

    fn onApc(ptr: *anyopaque, data: []const u8) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const owned = self.arena.allocator().dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .apc = owned }) catch {};
    }

    fn onDcs(ptr: *anyopaque, data: []const u8) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const owned = self.arena.allocator().dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .dcs = owned }) catch {};
    }

    fn onPm(ptr: *anyopaque, data: []const u8) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        const owned = self.arena.allocator().dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .pm = owned }) catch {};
    }

    fn onEscFinal(ptr: *anyopaque, byte: u8) void {
        const self: *Bridge = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{ .esc_final = byte }) catch {};
    }
};

const ParsedOsc = struct {
    kind: OscKind,
    command: ?u16,
    payload: []const u8,
};

fn parseOsc(data: []const u8) ParsedOsc {
    const separator = std.mem.indexOfScalar(u8, data, ';') orelse data.len;
    const command_text = data[0..separator];
    const payload = if (separator < data.len) data[separator + 1 ..] else "";
    const command = std.fmt.parseUnsigned(u16, command_text, 10) catch return .{
        .kind = if (separator == data.len) .title else .generic,
        .command = null,
        .payload = data,
    };
    return .{
        .kind = switch (command) {
            0, 1, 2 => .title,
            8 => .hyperlink,
            52 => .clipboard,
            else => .generic,
        },
        .command = command,
        .payload = payload,
    };
}

const bridge_mod = @import("bridge.zig");
test "bridge: maps ASCII text to text event" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("hello");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", bridge.events.items[0].text);
}

test "bridge: maps single ASCII byte to codepoint event" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("x");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 'x'), bridge.events.items[0].codepoint);
}

test "bridge: maps UTF-8 codepoint to codepoint event" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\xC3\xA9");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), bridge.events.items[0].codepoint);
}

test "bridge: maps control byte to control event" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleByte(0x07);
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .control);
    try std.testing.expectEqual(@as(u8, 0x07), bridge.events.items[0].control);
}

test "bridge: maps CSI sequence to style_change event" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b[31m");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, 'm'), bridge.events.items[0].style_change.final);
    try std.testing.expectEqual(@as(i32, 31), bridge.events.items[0].style_change.params[0]);
}

test "bridge: preserves CSI leader private and intermediates" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b[?25h\x1b[!p");
    try std.testing.expectEqual(@as(usize, 2), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, '?'), bridge.events.items[0].style_change.leader);
    try std.testing.expect(bridge.events.items[0].style_change.private);
    try std.testing.expectEqual(@as(i32, 25), bridge.events.items[0].style_change.params[0]);
    try std.testing.expectEqual(@as(u8, 0), bridge.events.items[1].style_change.leader);
    try std.testing.expect(!bridge.events.items[1].style_change.private);
    try std.testing.expectEqual(@as(u8, 1), bridge.events.items[1].style_change.intermediates_len);
    try std.testing.expectEqual(@as(u8, '!'), bridge.events.items[1].style_change.intermediates[0]);
}

test "bridge: maps OSC title command to typed osc event" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]0;My Window\x07");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .osc);
    try std.testing.expectEqual(OscKind.title, bridge.events.items[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 0), bridge.events.items[0].osc.command);
    try std.testing.expectEqualSlices(u8, "My Window", bridge.events.items[0].osc.payload);
}

test "bridge: preserves OSC clipboard transport" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]52;c;Zm9v\x07");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .osc);
    try std.testing.expectEqual(OscKind.clipboard, bridge.events.items[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 52), bridge.events.items[0].osc.command);
    try std.testing.expectEqualSlices(u8, "c;Zm9v", bridge.events.items[0].osc.payload);
}

test "bridge: parses OSC command without semicolon payload" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]30001\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .osc);
    try std.testing.expectEqual(OscKind.generic, bridge.events.items[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 30001), bridge.events.items[0].osc.command);
    try std.testing.expectEqualSlices(u8, "", bridge.events.items[0].osc.payload);
}

test "bridge: preserves APC, DCS, PM, and ESC final transport" {
    const gpa = std.testing.allocator;
    var bridge = Bridge.init(gpa);
    defer bridge.deinit();
    var parser = try ParserApi.Parser.init(gpa, bridge.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b_kitty\x1b\\\x1bPdata\x1b\\\x1b^ignored\x1b\\\x1bM");
    try std.testing.expectEqual(@as(usize, 4), bridge.events.items.len);
    try std.testing.expect(bridge.events.items[0] == .apc);
    try std.testing.expectEqualSlices(u8, "kitty", bridge.events.items[0].apc);
    try std.testing.expect(bridge.events.items[1] == .dcs);
    try std.testing.expectEqualSlices(u8, "data", bridge.events.items[1].dcs);
    try std.testing.expect(bridge.events.items[2] == .pm);
    try std.testing.expectEqualSlices(u8, "ignored", bridge.events.items[2].pm);
    try std.testing.expect(bridge.events.items[3] == .esc_final);
    try std.testing.expectEqual(@as(u8, 'M'), bridge.events.items[3].esc_final);
}
