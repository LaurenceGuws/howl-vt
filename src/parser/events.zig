//! Parser actions collected as parsed events.

const std = @import("std");
const parser_mod = @import("../parser.zig");
const parser_flow = @import("flow.zig");
const osc_parse = @import("../xterm/osc_parse.zig");

const ParserApi = parser_mod.Parser;
const dec_special_designation: u8 = '0';
const ascii_designation: u8 = 'B';

/// Parser output event.
pub const Event = union(enum) {
    text: []const u8,
    codepoint: u21,
    control: u8,
    style_change: struct {
        final: u8,
        params: [parser_mod.max_params]i32,
        separators: [parser_mod.max_params]u8 = [_]u8{0} ** parser_mod.max_params,
        param_count: u8,
        leader: u8,
        private: bool,
        intermediates: [parser_mod.max_intermediates]u8,
        intermediates_len: u8,
    },
    osc: struct {
        kind: OscKind,
        command: ?u16,
        payload: []const u8,
        terminator: parser_mod.OscTerminator,
    },
    apc: []const u8,
    dcs: struct {
        body: []const u8,
        payload: []const u8,
        final: u8,
        params: [parser_mod.max_params]i32,
        param_count: u8,
        intermediates: [parser_mod.max_intermediates]u8,
        intermediates_len: u8,
    },
    pm: []const u8,
    esc_dispatch: parser_mod.EscAction,
    invalid_sequence,
};

pub const OscKind = osc_parse.Kind;

/// Arena-backed event queue for parser callbacks.
pub const ParsedEvents = struct {
    const max_queued_events: u32 = 1024 * 1024;

    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    events: std.ArrayList(Event),
    apc_bytes: std.ArrayList(u8),
    dcs_bytes: std.ArrayList(u8),
    pm_bytes: std.ArrayList(u8),
    dcs_hook: ?parser_mod.DcsHook,
    gl_index: u8,
    g0_designation: u8,
    g1_designation: u8,

    pub fn init(allocator: std.mem.Allocator) ParsedEvents {
        const arena = std.heap.ArenaAllocator.init(allocator);
        return .{
            .allocator = allocator,
            .arena = arena,
            .events = std.ArrayList(Event).initCapacity(allocator, 32) catch unreachable,
            .apc_bytes = std.ArrayList(u8).empty,
            .dcs_bytes = std.ArrayList(u8).empty,
            .pm_bytes = std.ArrayList(u8).empty,
            .dcs_hook = null,
            .gl_index = 0,
            .g0_designation = ascii_designation,
            .g1_designation = ascii_designation,
        };
    }

    pub fn deinit(self: *ParsedEvents) void {
        self.clear();
        self.apc_bytes.deinit(self.allocator);
        self.dcs_bytes.deinit(self.allocator);
        self.pm_bytes.deinit(self.allocator);
        self.events.deinit(self.allocator);
        self.arena.deinit();
    }

    pub fn len(self: *const ParsedEvents) usize {
        return self.events.items.len;
    }

    pub fn isEmpty(self: *const ParsedEvents) bool {
        return self.events.items.len == 0;
    }

    /// Clear queued events and arena-owned byte slices.
    pub fn clear(self: *ParsedEvents) void {
        self.events.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
    }

    pub fn resetState(self: *ParsedEvents) void {
        self.clear();
        self.apc_bytes.clearRetainingCapacity();
        self.dcs_bytes.clearRetainingCapacity();
        self.pm_bytes.clearRetainingCapacity();
        self.dcs_hook = null;
        self.gl_index = 0;
        self.g0_designation = ascii_designation;
        self.g1_designation = ascii_designation;
    }

    pub fn deccirCharsetState(self: *const ParsedEvents) parser_mod.DeccirCharsetState {
        return .{
            .gl_index = self.gl_index,
            .g0_designation = self.g0_designation,
            .g1_designation = self.g1_designation,
        };
    }

    pub fn dropPrefix(self: *ParsedEvents, count: usize) void {
        if (count == 0) return;
        if (count >= self.events.items.len) {
            self.clear();
            return;
        }
        const remaining = self.events.items.len - count;
        std.mem.copyForwards(Event, self.events.items[0..remaining], self.events.items[count..]);
        self.events.shrinkRetainingCapacity(remaining);
    }

    pub fn drainInto(self: *ParsedEvents, dest: *std.ArrayList(Event), dest_allocator: std.mem.Allocator) !void {
        try dest.appendSlice(dest_allocator, self.events.items);
        self.events.clearRetainingCapacity();
    }

    pub fn appendParserActions(self: *ParsedEvents, actions: []const parser_mod.Action) error{ OutOfMemory, ParsedEventLimit }!void {
        // Alacritty's PTY loop reads up to 1 MiB before forcing a terminal
        // synchronization point. The host PTY owner follows that burst scale,
        // and the current parser/event shape can materialize at most one
        // queued parsed event per input byte. Keep the queue large enough to
        // absorb one normal burst, but still explicitly bounded.
        if (!self.canAppendActions(actions.len)) return error.ParsedEventLimit;

        var idx: usize = 0;
        while (idx < actions.len) {
            if (takeAsciiTextPrefix(self, actions[idx..])) |ascii_len| {
                try self.appendAsciiText(actions[idx .. idx + ascii_len]);
                idx += ascii_len;
                continue;
            }

            switch (actions[idx]) {
                .print => |cp| try self.appendPrint(cp),
                .execute => |ctrl| try self.appendControl(ctrl),
                .invalid => try self.events.append(self.allocator, Event.invalid_sequence),
                .csi_dispatch => |csi| try self.appendCsi(csi),
                .osc_dispatch => |osc| try self.appendOsc(osc.data, osc.term),
                .apc_start => self.apc_bytes.clearRetainingCapacity(),
                .apc_put => |byte| try self.apcBytesAppend(byte),
                .apc_end => try self.appendBufferedBytes(.apc, &self.apc_bytes),
                .dcs_hook => |hook| {
                    self.dcs_hook = hook;
                    self.dcs_bytes.clearRetainingCapacity();
                },
                .dcs_put => |byte| try self.dcsBytesAppend(byte),
                .dcs_unhook => try self.appendDcs(),
                .pm_start => self.pm_bytes.clearRetainingCapacity(),
                .pm_put => |byte| try self.pmBytesAppend(byte),
                .pm_end => try self.appendBufferedBytes(.pm, &self.pm_bytes),
                .esc_dispatch => |esc| try self.appendEscDispatch(esc),
            }
            idx += 1;
        }
    }

    fn appendPrint(self: *ParsedEvents, cp: u21) error{OutOfMemory}!void {
        try self.events.append(self.allocator, Event{ .codepoint = self.mapCodepoint(cp) });
    }

    fn appendAsciiText(self: *ParsedEvents, actions: []const parser_mod.Action) error{OutOfMemory}!void {
        if (actions.len == 1) {
            try self.events.append(self.allocator, Event{ .codepoint = self.mapCodepoint(actions[0].print) });
            return;
        }

        const owned = try self.arena.allocator().alloc(u8, actions.len);
        for (actions, 0..) |action, idx| owned[idx] = @intCast(self.mapCodepoint(action.print));
        try self.events.append(self.allocator, Event{ .text = owned });
    }

    fn appendCsi(self: *ParsedEvents, action: parser_mod.CsiAction) error{OutOfMemory}!void {
        try self.events.append(self.allocator, Event{
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
        });
    }

    fn appendOsc(self: *ParsedEvents, data: []const u8, term: parser_mod.OscTerminator) error{OutOfMemory}!void {
        const parsed = osc_parse.parse(data);
        const owned = try self.arena.allocator().dupe(u8, parsed.payload);
        try self.events.append(self.allocator, Event{ .osc = .{
            .kind = parsed.kind,
            .command = parsed.command,
            .payload = owned,
            .terminator = term,
        } });
    }

    fn appendBytes(self: *ParsedEvents, comptime tag: std.meta.FieldEnum(Event), data: []const u8) error{OutOfMemory}!void {
        const owned = try self.arena.allocator().dupe(u8, data);
        try self.events.append(self.allocator, @unionInit(Event, @tagName(tag), owned));
    }

    fn appendBufferedBytes(self: *ParsedEvents, comptime tag: std.meta.FieldEnum(Event), buffer: *std.ArrayList(u8)) error{OutOfMemory}!void {
        try self.appendBytes(tag, buffer.items);
        buffer.clearRetainingCapacity();
    }

    fn appendDcs(self: *ParsedEvents) error{OutOfMemory}!void {
        const hook = self.dcs_hook orelse return;
        const arena_allocator = self.arena.allocator();
        const payload = try arena_allocator.dupe(u8, self.dcs_bytes.items);
        var body = try std.ArrayList(u8).initCapacity(arena_allocator, self.dcs_bytes.items.len + 32);
        var idx: usize = 0;
        while (idx < hook.count) : (idx += 1) {
            if (idx > 0) try body.append(arena_allocator, ';');
            const text = try std.fmt.allocPrint(arena_allocator, "{d}", .{hook.params[idx]});
            try body.appendSlice(arena_allocator, text);
        }
        try body.appendSlice(arena_allocator, hook.intermediates[0..hook.intermediates_len]);
        try body.append(arena_allocator, hook.final);
        try body.appendSlice(arena_allocator, self.dcs_bytes.items);
        try self.events.append(self.allocator, Event{ .dcs = .{
            .body = body.items,
            .payload = payload,
            .final = hook.final,
            .params = hook.params,
            .param_count = hook.count,
            .intermediates = hook.intermediates,
            .intermediates_len = hook.intermediates_len,
        } });
        self.dcs_bytes.clearRetainingCapacity();
        self.dcs_hook = null;
    }

    fn apcBytesAppend(self: *ParsedEvents, byte: u8) error{OutOfMemory}!void {
        try self.apc_bytes.append(self.allocator, byte);
    }

    fn dcsBytesAppend(self: *ParsedEvents, byte: u8) error{OutOfMemory}!void {
        try self.dcs_bytes.append(self.allocator, byte);
    }

    fn pmBytesAppend(self: *ParsedEvents, byte: u8) error{OutOfMemory}!void {
        try self.pm_bytes.append(self.allocator, byte);
    }

    fn appendControl(self: *ParsedEvents, ctrl: u8) error{OutOfMemory}!void {
        switch (ctrl) {
            0x0E => {
                self.gl_index = 1;
                return;
            },
            0x0F => {
                self.gl_index = 0;
                return;
            },
            else => {},
        }
        try self.events.append(self.allocator, Event{ .control = ctrl });
    }

    fn appendEscDispatch(self: *ParsedEvents, esc: parser_mod.EscAction) error{OutOfMemory}!void {
        if (esc.intermediates_len == 1) {
            switch (esc.intermediates[0]) {
                '(' => {
                    self.g0_designation = esc.final;
                    return;
                },
                ')' => {
                    self.g1_designation = esc.final;
                    return;
                },
                else => {},
            }
        }
        try self.events.append(self.allocator, Event{ .esc_dispatch = esc });
    }

    fn canAppendActions(self: *const ParsedEvents, action_count: usize) bool {
        const queued = self.events.items.len;
        const total = std.math.add(usize, queued, action_count) catch return false;
        return total <= max_queued_events;
    }

    fn mapCodepoint(self: *const ParsedEvents, cp: u21) u21 {
        if (!self.activeDecSpecial()) return cp;
        if (cp < 0x20 or cp > 0x7e) return cp;
        return mapDecSpecial(@intCast(cp));
    }

    fn activeDecSpecial(self: *const ParsedEvents) bool {
        return switch (self.gl_index) {
            0 => self.g0_designation == dec_special_designation,
            1 => self.g1_designation == dec_special_designation,
            else => false,
        };
    }
};

fn takeAsciiTextPrefix(self: *const ParsedEvents, actions: []const parser_mod.Action) ?usize {
    if (self.activeDecSpecial()) return null;
    var len: usize = 0;
    while (len < actions.len) : (len += 1) {
        const action = actions[len];
        if (action != .print) break;
        if (!isAsciiTextCodepoint(action.print)) break;
    }
    if (len == 0) return null;
    return len;
}

fn isAsciiTextCodepoint(cp: u21) bool {
    return cp >= 0x20 and cp != 0x7f and cp < 0x80;
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

test "parsed events: maps ASCII text to text event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("hello") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", parsed_events.events.items[0].text);
}

test "parsed events: maps single ASCII byte to codepoint event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("x") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 'x'), parsed_events.events.items[0].codepoint);
}

test "parsed events: maps UTF-8 codepoint to codepoint event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\xC3\xA9") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), parsed_events.events.items[0].codepoint);
}

test "parsed events: maps control byte to control event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(0x07));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .control);
    try std.testing.expectEqual(@as(u8, 0x07), parsed_events.events.items[0].control);
}

test "parsed events: maps CSI sequence to style_change event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\x1b[31m") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, 'm'), parsed_events.events.items[0].style_change.final);
    try std.testing.expectEqual(@as(i32, 31), parsed_events.events.items[0].style_change.params[0]);
}

test "parsed events: preserves CSI leader private and intermediates" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\x1b[?25h\x1b[!p") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 2), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .style_change);
    try std.testing.expectEqual(@as(u8, '?'), parsed_events.events.items[0].style_change.leader);
    try std.testing.expect(parsed_events.events.items[0].style_change.private);
    try std.testing.expectEqual(@as(i32, 25), parsed_events.events.items[0].style_change.params[0]);
    try std.testing.expectEqual(@as(u8, 0), parsed_events.events.items[1].style_change.leader);
    try std.testing.expect(!parsed_events.events.items[1].style_change.private);
    try std.testing.expectEqual(@as(u8, 1), parsed_events.events.items[1].style_change.intermediates_len);
    try std.testing.expectEqual(@as(u8, '!'), parsed_events.events.items[1].style_change.intermediates[0]);
}

test "parsed events: maps OSC title command to typed osc event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\x1b]0;My Window\x07") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .osc);
    try std.testing.expectEqual(OscKind.title, parsed_events.events.items[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 0), parsed_events.events.items[0].osc.command);
    try std.testing.expectEqualSlices(u8, "My Window", parsed_events.events.items[0].osc.payload);
}

test "parsed events: preserves OSC clipboard transport" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\x1b]52;c;Zm9v\x07") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .osc);
    try std.testing.expectEqual(OscKind.clipboard, parsed_events.events.items[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 52), parsed_events.events.items[0].osc.command);
    try std.testing.expectEqualSlices(u8, "c;Zm9v", parsed_events.events.items[0].osc.payload);
}

test "parsed events: parses OSC command without semicolon payload" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\x1b]30001\x1b\\") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 1), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .osc);
    try std.testing.expectEqual(OscKind.other, parsed_events.events.items[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 30001), parsed_events.events.items[0].osc.command);
    try std.testing.expectEqualSlices(u8, "", parsed_events.events.items[0].osc.payload);
}

test "parsed events: preserves APC, DCS, PM, and ESC transport" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);
    for ("\x1b_kitty\x1b\\\x1bP1$qdata\x1b\\\x1b^ignored\x1b\\\x1bM") |byte| try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    try parsed_events.appendParserActions(actions.items);
    try std.testing.expectEqual(@as(usize, 4), parsed_events.events.items.len);
    try std.testing.expect(parsed_events.events.items[0] == .apc);
    try std.testing.expectEqualSlices(u8, "kitty", parsed_events.events.items[0].apc);
    try std.testing.expect(parsed_events.events.items[1] == .dcs);
    try std.testing.expectEqualSlices(u8, "data", parsed_events.events.items[1].dcs.payload);
    try std.testing.expectEqual(@as(u8, 'q'), parsed_events.events.items[1].dcs.final);
    try std.testing.expectEqual(@as(u8, 1), parsed_events.events.items[1].dcs.param_count);
    try std.testing.expectEqual(@as(i32, 1), parsed_events.events.items[1].dcs.params[0]);
    try std.testing.expectEqual(@as(u8, 1), parsed_events.events.items[1].dcs.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), parsed_events.events.items[1].dcs.intermediates[0]);
    try std.testing.expect(parsed_events.events.items[2] == .pm);
    try std.testing.expectEqualSlices(u8, "ignored", parsed_events.events.items[2].pm);
    try std.testing.expect(parsed_events.events.items[3] == .esc_dispatch);
    try std.testing.expectEqual(@as(u8, 'M'), parsed_events.events.items[3].esc_dispatch.final);
}

test "parsed events: rejects queue growth past explicit bound" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    try parsed_events.events.ensureTotalCapacity(gpa, ParsedEvents.max_queued_events);
    parsed_events.events.items.len = ParsedEvents.max_queued_events;

    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 1);
    defer actions.deinit(gpa);
    try actions.append(gpa, .{ .print = 'A' });

    try std.testing.expectError(error.ParsedEventLimit, parsed_events.appendParserActions(actions.items));
    try std.testing.expectEqual(@as(usize, ParsedEvents.max_queued_events), parsed_events.events.items.len);
}
