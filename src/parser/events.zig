//! Parser actions collected as parsed events.

const std = @import("std");
const parser_mod = @import("main.zig");
const osc_parse = @import("../xterm/osc_parse.zig");

const ParserApi = parser_mod.Parser;
const dec_special_designation: u8 = '0';
const ascii_designation: u8 = 'B';

/// Parser output event.
pub const StyleChange = struct {
    final: u8,
    params: []const i32,
    separators: parser_mod.CsiSeparatorList,
    param_count: u8,
    leader: u8,
    private: bool,
    intermediates: []const u8,
    intermediates_len: u8,
};

pub const DcsEvent = struct {
    body: []const u8,
    payload: []const u8,
    final: u8,
    params: []const i32,
    param_count: u8,
    intermediates: []const u8,
    intermediates_len: u8,
};

pub const Event = union(enum) {
    text: []const u8,
    codepoint: u21,
    control: u8,
    style_change: StyleChange,
    osc: struct {
        kind: OscKind,
        command: ?u16,
        payload: []const u8,
        terminator: parser_mod.OscTerminator,
    },
    apc: []const u8,
    dcs: DcsEvent,
    pm: []const u8,
    esc_dispatch: parser_mod.EscAction,
    invalid_sequence,
};

pub const OscKind = osc_parse.Kind;

/// Parsed-event queue for parser callbacks.
pub const ParsedEvents = struct {
    // Alacritty forces a terminal synchronization point after a 1 MiB PTY read
    // burst. The PTY owner keeps that burst scale, and the current Howl
    // parser/event shape can still materialize one queued event per input byte.
    // Keep exactly one reference burst buffered, then fail the next byte
    // explicitly instead of letting queue growth outrun the owner thread. If
    // the PTY burst or queued-event shape changes, re-derive this bound.
    pub const max_queued_events: u32 = 1024 * 1024;

    allocator: std.mem.Allocator,
    events: std.ArrayList(EventMeta),
    event_head: u32,
    bytes: std.ArrayList(u8),
    byte_head: u32,
    ints: std.ArrayList(i32),
    int_head: u32,
    aux: std.ArrayList(u8),
    aux_head: u32,
    apc_bytes: std.ArrayList(u8),
    dcs_bytes: std.ArrayList(u8),
    pm_bytes: std.ArrayList(u8),
    dcs_hook: ?DcsHookState,
    gl_index: u8,
    g0_designation: u8,
    g1_designation: u8,

    const compact_event_min: u32 = 64;
    const compact_value_min: u32 = 256;
    const compact_byte_min: u32 = 4096;

    const EventMeta = union(enum) {
        text: u32,
        codepoint: u21,
        control: u8,
        style_change: struct {
            final: u8,
            separators: parser_mod.CsiSeparatorList,
            param_count: u8,
            leader: u8,
            private: bool,
            intermediates_len: u8,
        },
        osc: struct {
            kind: OscKind,
            command: ?u16,
            payload_len: u32,
            terminator: parser_mod.OscTerminator,
        },
        apc: u32,
        dcs: struct {
            body_len: u32,
            payload_len: u32,
            final: u8,
            param_count: u8,
            intermediates_len: u8,
        },
        pm: u32,
        esc_dispatch: parser_mod.EscAction,
        invalid_sequence,
    };

    const DcsHookState = struct {
        final: u8,
        param_count: u8,
        intermediates_len: u8,
        params: [parser_mod.max_params]i32,
        intermediates: [parser_mod.max_intermediates]u8,
    };

    pub const AppendBatch = struct {
        event_len_start: u32,
        bytes_len_start: u32,
        ints_len_start: u32,
        aux_len_start: u32,
        apc_len_start: u32,
        dcs_len_start: u32,
        pm_len_start: u32,
        dcs_hook_start: ?DcsHookState,
        gl_index_start: u8,
        g0_designation_start: u8,
        g1_designation_start: u8,
    };

    pub const Iterator = struct {
        parsed_events: *const ParsedEvents,
        event_idx: u32,
        byte_idx: u32,
        int_idx: u32,
        aux_idx: u32,

        pub fn next(self: *Iterator) ?Event {
            if (self.event_idx >= self.parsed_events.events.items.len) return null;
            const meta = self.parsed_events.events.items[self.event_idx];
            const event = self.parsed_events.eventAt(self.event_idx, self.byte_idx, self.int_idx, self.aux_idx);
            self.event_idx += 1;
            advanceCursor(meta, &self.byte_idx, &self.int_idx, &self.aux_idx);
            return event;
        }
    };

    pub fn init(allocator: std.mem.Allocator) ParsedEvents {
        return .{
            .allocator = allocator,
            .events = .empty,
            .event_head = 0,
            .bytes = .empty,
            .byte_head = 0,
            .ints = .empty,
            .int_head = 0,
            .aux = .empty,
            .aux_head = 0,
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
        self.apc_bytes.deinit(self.allocator);
        self.dcs_bytes.deinit(self.allocator);
        self.pm_bytes.deinit(self.allocator);
        self.aux.deinit(self.allocator);
        self.ints.deinit(self.allocator);
        self.bytes.deinit(self.allocator);
        self.events.deinit(self.allocator);
    }

    pub fn eventCount(self: *const ParsedEvents) u32 {
        const count = self.events.items.len - index(self.event_head);
        std.debug.assert(count <= std.math.maxInt(u32));
        return @intCast(count);
    }

    /// Clear queued events and owned queued payloads, but preserve append state.
    pub fn clear(self: *ParsedEvents) void {
        self.events.clearRetainingCapacity();
        self.event_head = 0;
        self.bytes.clearRetainingCapacity();
        self.byte_head = 0;
        self.ints.clearRetainingCapacity();
        self.int_head = 0;
        self.aux.clearRetainingCapacity();
        self.aux_head = 0;
    }

    pub fn resetState(self: *ParsedEvents) void {
        self.events.clearRetainingCapacity();
        self.event_head = 0;
        self.bytes.clearRetainingCapacity();
        self.byte_head = 0;
        self.ints.clearRetainingCapacity();
        self.int_head = 0;
        self.aux.clearRetainingCapacity();
        self.aux_head = 0;
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

    pub fn iterator(self: *const ParsedEvents) Iterator {
        return .{
            .parsed_events = self,
            .event_idx = self.event_head,
            .byte_idx = self.byte_head,
            .int_idx = self.int_head,
            .aux_idx = self.aux_head,
        };
    }

    pub fn front(self: *const ParsedEvents) ?Event {
        if (self.eventCount() == 0) return null;
        return self.eventAt(self.event_head, self.byte_head, self.int_head, self.aux_head);
    }

    pub fn dropPrefix(self: *ParsedEvents, count: u32) void {
        std.debug.assert(count <= self.eventCount());
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) self.popFront();
    }

    pub fn popFront(self: *ParsedEvents) void {
        if (self.eventCount() == 0) return;
        const meta = self.events.items[self.event_head];
        self.event_head += 1;
        advanceCursor(meta, &self.byte_head, &self.int_head, &self.aux_head);
        maybeCompactStore(EventMeta, &self.events, &self.event_head, compact_event_min);
        maybeCompactStore(u8, &self.bytes, &self.byte_head, compact_byte_min);
        maybeCompactStore(i32, &self.ints, &self.int_head, compact_value_min);
        maybeCompactStore(u8, &self.aux, &self.aux_head, compact_value_min);
    }

    pub fn beginBatch(self: *const ParsedEvents) AppendBatch {
        return .{
            .event_len_start = boundedLen(self.events.items.len),
            .bytes_len_start = boundedLen(self.bytes.items.len),
            .ints_len_start = boundedLen(self.ints.items.len),
            .aux_len_start = boundedLen(self.aux.items.len),
            .apc_len_start = boundedLen(self.apc_bytes.items.len),
            .dcs_len_start = boundedLen(self.dcs_bytes.items.len),
            .pm_len_start = boundedLen(self.pm_bytes.items.len),
            .dcs_hook_start = self.dcs_hook,
            .gl_index_start = self.gl_index,
            .g0_designation_start = self.g0_designation,
            .g1_designation_start = self.g1_designation,
        };
    }

    pub fn rollbackBatch(self: *ParsedEvents, batch: AppendBatch) void {
        self.events.shrinkRetainingCapacity(index(batch.event_len_start));
        self.bytes.shrinkRetainingCapacity(index(batch.bytes_len_start));
        self.ints.shrinkRetainingCapacity(index(batch.ints_len_start));
        self.aux.shrinkRetainingCapacity(index(batch.aux_len_start));
        self.apc_bytes.shrinkRetainingCapacity(index(batch.apc_len_start));
        self.dcs_bytes.shrinkRetainingCapacity(index(batch.dcs_len_start));
        self.pm_bytes.shrinkRetainingCapacity(index(batch.pm_len_start));
        self.dcs_hook = batch.dcs_hook_start;
        self.gl_index = batch.gl_index_start;
        self.g0_designation = batch.g0_designation_start;
        self.g1_designation = batch.g1_designation_start;
    }

    pub fn finishBatch(self: *ParsedEvents, batch: AppendBatch) void {
        if (self.events.items.len <= index(batch.event_len_start)) return;
        const last = &self.events.items[self.events.items.len - 1];
        switch (last.*) {
            .text => |len| {
                if (len != 1) return;
                std.debug.assert(self.bytes.items.len > 0);
                const byte = self.bytes.items[self.bytes.items.len - 1];
                self.bytes.items.len -= 1;
                last.* = .{ .codepoint = byte };
            },
            else => {},
        }
    }

    pub fn appendPhases(self: *ParsedEvents, batch: AppendBatch, phases: parser_mod.PhaseActions) error{ OutOfMemory, ParsedEventLimit, StringControlLimit }!void {
        for (phases) |phase| {
            if (phase) |action| try self.appendAction(batch, action);
        }
    }

    pub fn appendParserActions(self: *ParsedEvents, actions: []const parser_mod.Action) error{ OutOfMemory, ParsedEventLimit, StringControlLimit }!void {
        const batch = self.beginBatch();
        errdefer self.rollbackBatch(batch);
        for (actions) |action| try self.appendAction(batch, action);
        self.finishBatch(batch);
    }

    fn appendAction(self: *ParsedEvents, batch: AppendBatch, action: parser_mod.Action) error{ OutOfMemory, ParsedEventLimit, StringControlLimit }!void {
        switch (action) {
            .print => |cp| try self.appendPrint(batch, cp),
            .execute => |ctrl| try self.appendControl(ctrl),
            .invalid => try self.appendMeta(.invalid_sequence),
            .csi_dispatch => |csi| try self.appendCsi(csi),
            .osc_dispatch => |osc| try self.appendOsc(osc.data, osc.term),
            .apc_start => self.apc_bytes.clearRetainingCapacity(),
            .apc_put => |byte| try self.apcBytesAppend(byte),
            .apc_end => try self.appendBufferedBytes(.apc, &self.apc_bytes),
            .dcs_hook => |hook| self.captureDcsHook(hook),
            .dcs_put => |byte| try self.dcsBytesAppend(byte),
            .dcs_unhook => try self.appendDcs(),
            .pm_start => self.pm_bytes.clearRetainingCapacity(),
            .pm_put => |byte| try self.pmBytesAppend(byte),
            .pm_end => try self.appendBufferedBytes(.pm, &self.pm_bytes),
            .esc_dispatch => |esc| try self.appendEscDispatch(esc),
        }
    }

    fn appendPrint(self: *ParsedEvents, batch: AppendBatch, cp: u21) error{ OutOfMemory, ParsedEventLimit }!void {
        const mapped = self.mapCodepoint(cp);
        if (isAsciiTextCodepoint(mapped)) {
            try self.bytes.append(self.allocator, @intCast(mapped));
            if (self.events.items.len > index(batch.event_len_start)) {
                const last = &self.events.items[self.events.items.len - 1];
                switch (last.*) {
                    .text => |*len| {
                        std.debug.assert(len.* < std.math.maxInt(u32));
                        len.* += 1;
                        return;
                    },
                    else => {},
                }
            }
            try self.appendMeta(.{ .text = 1 });
            return;
        }
        try self.appendMeta(.{ .codepoint = mapped });
    }

    fn appendCsi(self: *ParsedEvents, action: parser_mod.CsiAction) error{ OutOfMemory, ParsedEventLimit }!void {
        try self.ints.appendSlice(self.allocator, action.params[0..action.count]);
        try self.aux.appendSlice(self.allocator, action.intermediates[0..action.intermediates_len]);
        try self.appendMeta(.{ .style_change = .{
            .final = action.final,
            .separators = action.separators,
            .param_count = action.count,
            .leader = action.leader,
            .private = action.private,
            .intermediates_len = action.intermediates_len,
        } });
    }

    fn appendOsc(self: *ParsedEvents, data: []const u8, term: parser_mod.OscTerminator) error{ OutOfMemory, ParsedEventLimit }!void {
        const parsed = osc_parse.parse(data);
        try self.bytes.appendSlice(self.allocator, parsed.payload);
        try self.appendMeta(.{ .osc = .{
            .kind = parsed.kind,
            .command = parsed.command,
            .payload_len = boundedLen(parsed.payload.len),
            .terminator = term,
        } });
    }

    fn appendBufferedBytes(self: *ParsedEvents, comptime tag: std.meta.FieldEnum(EventMeta), buffer: *std.ArrayList(u8)) error{ OutOfMemory, ParsedEventLimit }!void {
        try self.bytes.appendSlice(self.allocator, buffer.items);
        try self.appendMeta(@unionInit(EventMeta, @tagName(tag), boundedLen(buffer.items.len)));
        buffer.clearRetainingCapacity();
    }

    fn appendDcs(self: *ParsedEvents) error{ OutOfMemory, ParsedEventLimit }!void {
        const hook = self.dcs_hook orelse return;
        try self.ints.appendSlice(self.allocator, hook.params[0..hook.param_count]);
        try self.aux.appendSlice(self.allocator, hook.intermediates[0..hook.intermediates_len]);
        const body_len = try self.appendDcsBody(hook);
        try self.appendMeta(.{ .dcs = .{
            .body_len = body_len,
            .payload_len = boundedLen(self.dcs_bytes.items.len),
            .final = hook.final,
            .param_count = hook.param_count,
            .intermediates_len = hook.intermediates_len,
        } });
        self.dcs_bytes.clearRetainingCapacity();
        self.dcs_hook = null;
    }

    fn appendDcsBody(self: *ParsedEvents, hook: DcsHookState) error{OutOfMemory}!u32 {
        const start = self.bytes.items.len;
        var idx: u8 = 0;
        while (idx < hook.param_count) : (idx += 1) {
            if (idx > 0) try self.bytes.append(self.allocator, ';');
            var text_buf: [32]u8 = undefined;
            const text = std.fmt.bufPrint(&text_buf, "{d}", .{hook.params[idx]}) catch unreachable;
            try self.bytes.appendSlice(self.allocator, text);
        }
        try self.bytes.appendSlice(self.allocator, hook.intermediates[0..hook.intermediates_len]);
        try self.bytes.append(self.allocator, hook.final);
        try self.bytes.appendSlice(self.allocator, self.dcs_bytes.items);
        return boundedLen(self.bytes.items.len - start);
    }

    fn captureDcsHook(self: *ParsedEvents, hook: parser_mod.DcsHook) void {
        var state = DcsHookState{
            .final = hook.final,
            .param_count = hook.count,
            .intermediates_len = hook.intermediates_len,
            .params = [_]i32{0} ** parser_mod.max_params,
            .intermediates = [_]u8{0} ** parser_mod.max_intermediates,
        };
        std.mem.copyForwards(i32, state.params[0..hook.count], hook.params[0..hook.count]);
        std.mem.copyForwards(u8, state.intermediates[0..hook.intermediates_len], hook.intermediates[0..hook.intermediates_len]);
        self.dcs_hook = state;
        self.dcs_bytes.clearRetainingCapacity();
    }

    fn apcBytesAppend(self: *ParsedEvents, byte: u8) error{ OutOfMemory, StringControlLimit }!void {
        if (self.apc_bytes.items.len >= parser_mod.max_apc_control_bytes) return error.StringControlLimit;
        try self.apc_bytes.append(self.allocator, byte);
    }

    fn dcsBytesAppend(self: *ParsedEvents, byte: u8) error{ OutOfMemory, StringControlLimit }!void {
        if (self.dcs_bytes.items.len >= parser_mod.max_metadata_control_bytes) return error.StringControlLimit;
        try self.dcs_bytes.append(self.allocator, byte);
    }

    fn pmBytesAppend(self: *ParsedEvents, byte: u8) error{ OutOfMemory, StringControlLimit }!void {
        if (self.pm_bytes.items.len >= parser_mod.max_metadata_control_bytes) return error.StringControlLimit;
        try self.pm_bytes.append(self.allocator, byte);
    }

    fn appendControl(self: *ParsedEvents, ctrl: u8) error{ OutOfMemory, ParsedEventLimit }!void {
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
        try self.appendMeta(.{ .control = ctrl });
    }

    fn appendEscDispatch(self: *ParsedEvents, esc: parser_mod.EscAction) error{ OutOfMemory, ParsedEventLimit }!void {
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
        try self.appendMeta(.{ .esc_dispatch = esc });
    }

    fn appendMeta(self: *ParsedEvents, meta: EventMeta) error{ParsedEventLimit, OutOfMemory}!void {
        if (self.eventCount() >= max_queued_events) return error.ParsedEventLimit;
        try self.events.append(self.allocator, meta);
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

    fn eventAt(self: *const ParsedEvents, event_idx: u32, byte_idx: u32, int_idx: u32, aux_idx: u32) Event {
        const meta = self.events.items[index(event_idx)];
        const byte_start = index(byte_idx);
        const int_start = index(int_idx);
        const aux_start = index(aux_idx);
        return switch (meta) {
            .text => |len| .{ .text = self.bytes.items[byte_start .. byte_start + index(len)] },
            .codepoint => |cp| .{ .codepoint = cp },
            .control => |ctrl| .{ .control = ctrl },
            .style_change => |sc| .{ .style_change = .{
                .final = sc.final,
                .params = self.ints.items[int_start .. int_start + index(sc.param_count)],
                .separators = sc.separators,
                .param_count = sc.param_count,
                .leader = sc.leader,
                .private = sc.private,
                .intermediates = self.aux.items[aux_start .. aux_start + index(sc.intermediates_len)],
                .intermediates_len = sc.intermediates_len,
            } },
            .osc => |osc| .{ .osc = .{
                .kind = osc.kind,
                .command = osc.command,
                .payload = self.bytes.items[byte_start .. byte_start + index(osc.payload_len)],
                .terminator = osc.terminator,
            } },
            .apc => |len| .{ .apc = self.bytes.items[byte_start .. byte_start + index(len)] },
            .dcs => |dcs| .{ .dcs = .{
                .body = self.bytes.items[byte_start .. byte_start + index(dcs.body_len)],
                .payload = self.bytes.items[byte_start + index(dcs.body_len - dcs.payload_len) .. byte_start + index(dcs.body_len)],
                .final = dcs.final,
                .params = self.ints.items[int_start .. int_start + index(dcs.param_count)],
                .param_count = dcs.param_count,
                .intermediates = self.aux.items[aux_start .. aux_start + index(dcs.intermediates_len)],
                .intermediates_len = dcs.intermediates_len,
            } },
            .pm => |len| .{ .pm = self.bytes.items[byte_start .. byte_start + index(len)] },
            .esc_dispatch => |esc| .{ .esc_dispatch = esc },
            .invalid_sequence => .invalid_sequence,
        };
    }
};

fn boundedLen(len: usize) u32 {
    std.debug.assert(len <= std.math.maxInt(u32));
    return @intCast(len);
}

fn index(value: u32) usize {
    return @intCast(value);
}

fn advanceCursor(meta: ParsedEvents.EventMeta, byte_idx: *u32, int_idx: *u32, aux_idx: *u32) void {
    switch (meta) {
        .text => |len| byte_idx.* += len,
        .style_change => |sc| {
            int_idx.* += sc.param_count;
            aux_idx.* += sc.intermediates_len;
        },
        .osc => |osc| byte_idx.* += osc.payload_len,
        .apc => |len| byte_idx.* += len,
        .dcs => |dcs| {
            byte_idx.* += dcs.body_len;
            int_idx.* += dcs.param_count;
            aux_idx.* += dcs.intermediates_len;
        },
        .pm => |len| byte_idx.* += len,
        .codepoint, .control, .esc_dispatch, .invalid_sequence => {},
    }
}

fn maybeCompactStore(comptime T: type, list: *std.ArrayList(T), head: *u32, min_reclaim: u32) void {
    if (head.* == 0) return;
    if (index(head.*) == list.items.len) {
        list.clearRetainingCapacity();
        head.* = 0;
        return;
    }
    if (head.* < min_reclaim or index(head.*) * 2 < list.items.len) return;
    const remaining = list.items.len - index(head.*);
    std.mem.copyForwards(T, list.items[0..remaining], list.items[index(head.*)..]);
    list.shrinkRetainingCapacity(remaining);
    head.* = 0;
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

fn feedParsedEvents(parsed_events: *ParsedEvents, parser: *ParserApi, bytes: []const u8) !void {
    const batch = parsed_events.beginBatch();
    errdefer parsed_events.rollbackBatch(batch);
    for (bytes) |byte| {
        const phases = parser.next(byte);
        if (parser.takeStringControlFailed()) |failure| {
            parser.reset();
            return failure;
        }
        try parsed_events.appendPhases(batch, phases);
    }
    parsed_events.finishBatch(batch);
}

fn collectParsedEvents(allocator: std.mem.Allocator, parsed_events: *const ParsedEvents) ![]Event {
    var out: std.ArrayList(Event) = .empty;
    defer out.deinit(allocator);
    var it = parsed_events.iterator();
    while (it.next()) |event| try out.append(allocator, event);
    return try out.toOwnedSlice(allocator);
}

test "parsed events: maps ASCII text to text event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "hello");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .text);
    try std.testing.expectEqualSlices(u8, "hello", events[0].text);
}

test "parsed events: maps single ASCII byte to codepoint event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "x");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 'x'), events[0].codepoint);
}

test "parsed events: maps UTF-8 codepoint to codepoint event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\xC3\xA9");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .codepoint);
    try std.testing.expectEqual(@as(u21, 0xE9), events[0].codepoint);
}

test "parsed events: maps control byte to control event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, &.{0x07});
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .control);
    try std.testing.expectEqual(@as(u8, 0x07), events[0].control);
}

test "parsed events: maps CSI sequence to style_change event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\x1b[31m");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .style_change);
    try std.testing.expectEqual(@as(u8, 'm'), events[0].style_change.final);
    try std.testing.expectEqual(@as(i32, 31), events[0].style_change.params[0]);
}

test "parsed events: preserves CSI leader private and intermediates" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\x1b[?25h\x1b[!p");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 2);
    try std.testing.expect(events[0] == .style_change);
    try std.testing.expectEqual(@as(u8, '?'), events[0].style_change.leader);
    try std.testing.expect(events[0].style_change.private);
    try std.testing.expectEqual(@as(i32, 25), events[0].style_change.params[0]);
    try std.testing.expectEqual(@as(u8, 0), events[1].style_change.leader);
    try std.testing.expect(!events[1].style_change.private);
    try std.testing.expectEqual(@as(u8, 1), events[1].style_change.intermediates_len);
    try std.testing.expectEqual(@as(u8, '!'), events[1].style_change.intermediates[0]);
}

test "parsed events: maps OSC title command to typed osc event" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\x1b]0;My Window\x07");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .osc);
    try std.testing.expectEqual(OscKind.title, events[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 0), events[0].osc.command);
    try std.testing.expectEqualSlices(u8, "My Window", events[0].osc.payload);
}

test "parsed events: preserves OSC clipboard transport" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\x1b]52;c;Zm9v\x07");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .osc);
    try std.testing.expectEqual(OscKind.clipboard, events[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 52), events[0].osc.command);
    try std.testing.expectEqualSlices(u8, "c;Zm9v", events[0].osc.payload);
}

test "parsed events: parses OSC command without semicolon payload" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\x1b]30001\x1b\\");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 1);
    try std.testing.expect(events[0] == .osc);
    try std.testing.expectEqual(OscKind.other, events[0].osc.kind);
    try std.testing.expectEqual(@as(?u16, 30001), events[0].osc.command);
    try std.testing.expectEqualSlices(u8, "", events[0].osc.payload);
}

test "parsed events: preserves APC, DCS, PM, and ESC transport" {
    const gpa = std.testing.allocator;
    var parsed_events = ParsedEvents.init(gpa);
    defer parsed_events.deinit();
    var parser = try ParserApi.init(gpa);
    defer parser.deinit();
    try feedParsedEvents(&parsed_events, &parser, "\x1b_kitty\x1b\\\x1bP1$qdata\x1b\\\x1b^ignored\x1b\\\x1bM");
    const events = try collectParsedEvents(gpa, &parsed_events);
    defer gpa.free(events);
    try std.testing.expect(events.len == 4);
    try std.testing.expect(events[0] == .apc);
    try std.testing.expectEqualSlices(u8, "kitty", events[0].apc);
    try std.testing.expect(events[1] == .dcs);
    try std.testing.expectEqualSlices(u8, "data", events[1].dcs.payload);
    try std.testing.expectEqual(@as(u8, 'q'), events[1].dcs.final);
    try std.testing.expectEqual(@as(u8, 1), events[1].dcs.param_count);
    try std.testing.expectEqual(@as(i32, 1), events[1].dcs.params[0]);
    try std.testing.expectEqual(@as(u8, 1), events[1].dcs.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), events[1].dcs.intermediates[0]);
    try std.testing.expect(events[2] == .pm);
    try std.testing.expectEqualSlices(u8, "ignored", events[2].pm);
    try std.testing.expect(events[3] == .esc_dispatch);
    try std.testing.expectEqual(@as(u8, 'M'), events[3].esc_dispatch.final);
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
    try std.testing.expect(parsed_events.events.items.len == ParsedEvents.max_queued_events);
}
