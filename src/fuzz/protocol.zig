//! Protocol/parser fuzz scenarios.

const std = @import("std");
const action = @import("../action.zig");
const parser_mod = @import("../parser.zig");
const parser_flow = @import("../parser/flow.zig");
const screen_set = @import("../screen_set.zig");
const Action = action;
const Parser = parser_mod.Parser;
const OscTerminator = parser_mod.OscTerminator;
const CsiAction = parser_mod.CsiAction;
const xterm_ctlseqs = @embedFile("assets/xterm-ctlseqs.ms");

pub const Options = struct {
    iterations: usize = 32,
    ops_per_case: usize = 64,
    max_chunk_len: usize = 32,
};

const FeedMode = enum {
    whole_slice,
    bytewise,
    chunked,
};

const OpKind = enum {
    prose,
    csi,
    osc,
    dcs,
    apc,
    pm,
    esc_dispatch,
    utf8,
    control,
};

const Event = union(enum) {
    print: u21,
    execute: u8,
    invalid,
    csi: struct {
        final: u8,
        leader: u8,
        private: bool,
        params: [parser_mod.max_params]i32,
        count: u8,
        intermediates: [parser_mod.max_intermediates]u8,
        intermediates_len: u8,
    },
    osc: struct {
        data: []u8,
        term: OscTerminator,
    },
    apc_start,
    apc_put: u8,
    apc_end,
    dcs_hook: parser_mod.DcsHook,
    dcs_put: u8,
    dcs_unhook,
    pm_start,
    pm_put: u8,
    pm_end,
    esc_dispatch: parser_mod.EscAction,
};

const Harness = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),

    fn init(allocator: std.mem.Allocator) Harness {
        return .{
            .allocator = allocator,
            .events = std.ArrayList(Event).empty,
        };
    }

    fn deinit(self: *Harness) void {
        for (self.events.items) |event| {
            switch (event) {
                .osc => |osc| self.allocator.free(osc.data),
                else => {},
            }
        }
        self.events.deinit(self.allocator);
    }

    fn appendActions(self: *Harness, actions: []const parser_mod.Action) void {
        for (actions) |action| switch (action) {
            .print => |cp| self.events.append(self.allocator, Event{ .print = cp }) catch {},
            .execute => |ctrl| self.events.append(self.allocator, Event{ .execute = ctrl }) catch {},
            .invalid => self.events.append(self.allocator, .invalid) catch {},
            .csi_dispatch => |csi| self.appendCsi(csi),
            .osc_dispatch => |osc| self.appendOsc(osc.data, osc.term),
            .apc_start => self.events.append(self.allocator, .apc_start) catch {},
            .apc_put => |byte| self.events.append(self.allocator, Event{ .apc_put = byte }) catch {},
            .apc_end => self.events.append(self.allocator, .apc_end) catch {},
            .dcs_hook => |hook| self.events.append(self.allocator, Event{ .dcs_hook = hook }) catch {},
            .dcs_put => |byte| self.events.append(self.allocator, Event{ .dcs_put = byte }) catch {},
            .dcs_unhook => self.events.append(self.allocator, .dcs_unhook) catch {},
            .pm_start => self.events.append(self.allocator, .pm_start) catch {},
            .pm_put => |byte| self.events.append(self.allocator, Event{ .pm_put = byte }) catch {},
            .pm_end => self.events.append(self.allocator, .pm_end) catch {},
            .esc_dispatch => |esc| self.events.append(self.allocator, Event{ .esc_dispatch = esc }) catch {},
        };
    }

    fn appendCsi(self: *Harness, action: CsiAction) void {
        self.events.append(self.allocator, Event{ .csi = .{
            .final = action.final,
            .leader = action.leader,
            .private = action.private,
            .params = action.params,
            .count = action.count,
            .intermediates = action.intermediates,
            .intermediates_len = action.intermediates_len,
        } }) catch {};
    }

    fn appendOsc(self: *Harness, data: []const u8, term: OscTerminator) void {
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .osc = .{
            .data = owned,
            .term = term,
        } }) catch {};
    }

};

const VtDigest = struct {
    hash: u64,
    rows: u16,
    cols: u16,
    cursor_row: u16,
    cursor_col: u16,
    history_count: usize,
    alt_active: bool,
};

const EventDigest = struct {
    hash: u64,
    token_count: usize,
};

const ParserOutput = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    actions: std.ArrayList(parser_mod.Action),

    fn init(allocator: std.mem.Allocator) !ParserOutput {
        return .{
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .actions = try std.ArrayList(parser_mod.Action).initCapacity(allocator, 16),
        };
    }

    fn deinit(self: *ParserOutput, allocator: std.mem.Allocator) void {
        self.actions.deinit(allocator);
        self.arena.deinit();
    }

    fn clear(self: *ParserOutput) void {
        self.actions.clearRetainingCapacity();
        _ = self.arena.reset(.retain_capacity);
    }

    fn appendPhases(self: *ParserOutput, phases: parser_mod.PhaseActions) void {
        parser_flow.appendOwnedPhases(self.allocator, self.arena.allocator(), &self.actions, phases);
    }
};

pub fn defaultOptions(events_max: ?usize) Options {
    return .{
        .iterations = 32,
        .ops_per_case = events_max orelse 64,
        .max_chunk_len = 32,
    };
}

pub fn runSmoke(gpa: std.mem.Allocator) !void {
    const seeds = [_]u64{
        0x70726f746f3031,
        0x70726f746f3032,
        0x70726f746f3033,
    };
    for (seeds) |seed| {
        try runDeterminism(gpa, seed, defaultOptions(null));
    }
}

pub fn runDeterminism(gpa: std.mem.Allocator, seed: u64, options: Options) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var case_index: usize = 0;
    while (case_index < options.iterations) : (case_index += 1) {
        var bytes = std.ArrayList(u8).empty;
        defer bytes.deinit(gpa);

        try buildCase(gpa, &bytes, rand, options.ops_per_case);
        try assertParserDeterminism(gpa, seed, case_index, bytes.items, rand, options.max_chunk_len);
        try assertTerminalDeterminism(gpa, seed, case_index, bytes.items, rand, options.max_chunk_len);
    }
}

fn buildCase(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, ops_per_case: usize) !void {
    try bytes.ensureTotalCapacityPrecise(allocator, ops_per_case * 16);

    var op_index: usize = 0;
    while (op_index < ops_per_case) : (op_index += 1) {
        const op: OpKind = rand.enumValue(OpKind);
        switch (op) {
            .prose => try appendAssetText(allocator, bytes, rand, 1 + rand.uintLessThan(usize, 48)),
            .csi => try appendCsi(allocator, bytes, rand),
            .osc => try appendStringCommand(allocator, bytes, rand, ']'),
            .dcs => try appendStringCommand(allocator, bytes, rand, 'P'),
            .apc => try appendStringCommand(allocator, bytes, rand, '_'),
            .pm => try appendStringCommand(allocator, bytes, rand, '^'),
            .esc_dispatch => try appendEscFinal(allocator, bytes, rand),
            .utf8 => try appendUtf8Burst(allocator, bytes, rand),
            .control => try appendControlBurst(allocator, bytes, rand),
        }
    }
}

fn assertParserDeterminism(
    gpa: std.mem.Allocator,
    seed: u64,
    case_index: usize,
    bytes: []const u8,
    rand: std.Random,
    max_chunk_len: usize,
) !void {
    var whole = try runParser(gpa, bytes, .whole_slice, rand, max_chunk_len);
    defer whole.deinit();
    var bytewise = try runParser(gpa, bytes, .bytewise, rand, max_chunk_len);
    defer bytewise.deinit();
    var chunked = try runParser(gpa, bytes, .chunked, rand, max_chunk_len);
    defer chunked.deinit();

    const whole_digest = digestEvents(whole.events.items);
    const bytewise_digest = digestEvents(bytewise.events.items);
    const chunked_digest = digestEvents(chunked.events.items);

    if (!std.meta.eql(whole_digest, bytewise_digest) or !std.meta.eql(whole_digest, chunked_digest)) {
        std.log.err("protocol parser mismatch seed={} case={} bytes={} whole_hash={} bytewise_hash={} chunked_hash={}", .{
            seed,
            case_index,
            bytes.len,
            whole_digest.hash,
            bytewise_digest.hash,
            chunked_digest.hash,
        });
        return error.ParserDeterminismMismatch;
    }
}

fn assertTerminalDeterminism(
    gpa: std.mem.Allocator,
    seed: u64,
    case_index: usize,
    bytes: []const u8,
    rand: std.Random,
    max_chunk_len: usize,
) !void {
    const whole = try runTerminal(gpa, bytes, .whole_slice, rand, max_chunk_len);
    const bytewise = try runTerminal(gpa, bytes, .bytewise, rand, max_chunk_len);
    const chunked = try runTerminal(gpa, bytes, .chunked, rand, max_chunk_len);

    if (!std.meta.eql(whole, bytewise) or !std.meta.eql(whole, chunked)) {
        std.log.err("protocol terminal mismatch seed={} case={} bytes={} whole_hash={} bytewise_hash={} chunked_hash={}", .{
            seed,
            case_index,
            bytes.len,
            whole.hash,
            bytewise.hash,
            chunked.hash,
        });
        return error.TerminalDeterminismMismatch;
    }
}

fn runParser(
    gpa: std.mem.Allocator,
    bytes: []const u8,
    mode: FeedMode,
    rand: std.Random,
    max_chunk_len: usize,
) !Harness {
    var harness = Harness.init(gpa);
    errdefer harness.deinit();

    var parser = try Parser.init(gpa);
    defer parser.deinit();
    var output = try ParserOutput.init(gpa);
    defer output.deinit(gpa);

    feedBytesToParser(&parser, &output, &harness, bytes, mode, rand, max_chunk_len);
    return harness;
}

fn runTerminal(
    gpa: std.mem.Allocator,
    bytes: []const u8,
    mode: FeedMode,
    rand: std.Random,
    max_chunk_len: usize,
) !VtDigest {
    var terminal = try vt.Terminal.initWithCellsAndHistory(gpa, 24, 80, 256);
    defer terminal.deinit();

    feedBytesToTerminal(&terminal, bytes, mode, rand, max_chunk_len);
    Action.apply(&terminal);
    return digestTerminal(&terminal);
}

fn feedBytesToParser(parser: *Parser, output: *ParserOutput, harness: *Harness, bytes: []const u8, mode: FeedMode, rand: std.Random, max_chunk_len: usize) void {
    switch (mode) {
        .whole_slice => {
            output.clear();
            for (bytes) |byte| output.appendPhases(parser.next(byte));
            harness.appendActions(output.actions.items);
        },
        .bytewise => for (bytes) |byte| {
            output.clear();
            output.appendPhases(parser.next(byte));
            harness.appendActions(output.actions.items);
        },
        .chunked => {
            var offset: usize = 0;
            while (offset < bytes.len) {
                const remaining = bytes.len - offset;
                const chunk_len = 1 + rand.uintLessThan(usize, @min(remaining, max_chunk_len));
                output.clear();
                for (bytes[offset..][0..chunk_len]) |byte| output.appendPhases(parser.next(byte));
                harness.appendActions(output.actions.items);
                offset += chunk_len;
            }
        },
    }
}

fn feedBytesToTerminal(terminal: *vt.Terminal, bytes: []const u8, mode: FeedMode, rand: std.Random, max_chunk_len: usize) void {
    switch (mode) {
        .whole_slice => parser_flow.feedSlice(terminal, bytes) catch unreachable,
        .bytewise => for (bytes) |byte| parser_flow.feedByte(terminal, byte) catch unreachable,
        .chunked => {
            var offset: usize = 0;
            while (offset < bytes.len) {
                const remaining = bytes.len - offset;
                const chunk_len = 1 + rand.uintLessThan(usize, @min(remaining, max_chunk_len));
                parser_flow.feedSlice(terminal, bytes[offset..][0..chunk_len]) catch unreachable;
                offset += chunk_len;
            }
        },
    }
}

fn digestTerminal(terminal: *const vt.Terminal) VtDigest {
    var hasher = std.hash.Wyhash.init(0);
    const view = screen_set.visibleView(&terminal.screen_state, .{});

    hashValue(&hasher, view.rows);
    hashValue(&hasher, view.cols);
    hashValue(&hasher, view.cursor_row);
    hashValue(&hasher, view.cursor_col);
    hashValue(&hasher, view.cursor_visible);
    hashValue(&hasher, @intFromEnum(view.cursor_shape));
    hashValue(&hasher, view.is_alternate_screen);

    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            hashCell(&hasher, view.cellInfoAt(row, col));
        }
    }

    const history_count = screen_set.visibleView(&terminal.screen_state, .{}).history_count;
    hashValue(&hasher, history_count);
    var history_idx: usize = 0;
    while (history_idx < history_count) : (history_idx += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            hashCell(&hasher, screen_set.historyCellAt(&terminal.screen_state, history_idx, col));
        }
    }

    return .{
        .hash = hasher.final(),
        .rows = view.rows,
        .cols = view.cols,
        .cursor_row = view.cursor_row,
        .cursor_col = view.cursor_col,
        .history_count = history_count,
        .alt_active = view.is_alternate_screen,
    };
}

fn hashCell(hasher: *std.hash.Wyhash, cell: anytype) void {
    hashValue(hasher, cell.codepoint);
    hashValue(hasher, cell.combining_len);
    for (cell.combining) |cp| hashValue(hasher, cp);
    hashValue(hasher, cell.width);
    hashValue(hasher, cell.height);
    hashValue(hasher, cell.x);
    hashValue(hasher, cell.y);
    hashColor(hasher, cell.attrs.fg);
    hashColor(hasher, cell.attrs.bg);
    hashValue(hasher, cell.attrs.bold);
    hashValue(hasher, cell.attrs.blink);
    hashValue(hasher, cell.attrs.blink_fast);
    hashValue(hasher, cell.attrs.reverse);
    hashValue(hasher, cell.attrs.underline);
    hashValue(hasher, @intFromEnum(cell.attrs.underline_style));
    hashColor(hasher, cell.attrs.underline_color);
    hashValue(hasher, cell.attrs.link_id);
}

fn hashColor(hasher: *std.hash.Wyhash, color: anytype) void {
    hashValue(hasher, color.r);
    hashValue(hasher, color.g);
    hashValue(hasher, color.b);
    hashValue(hasher, color.a);
}

fn hashValue(hasher: *std.hash.Wyhash, value: anytype) void {
    const bytes = std.mem.asBytes(&value);
    hasher.update(bytes);
}

fn appendCsi(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    try bytes.appendSlice(allocator, "\x1b[");

    if (rand.boolean()) {
        const leaders = [_]u8{ '?', '>', '<', '=' };
        try bytes.append(allocator, leaders[rand.uintLessThan(usize, leaders.len)]);
    }

    const param_count = 1 + rand.uintLessThan(usize, 4);
    var param_idx: usize = 0;
    while (param_idx < param_count) : (param_idx += 1) {
        const value = rand.uintLessThan(u16, 1000);
        var buf: [16]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "{d}", .{value});
        try bytes.appendSlice(allocator, text);
        if (param_idx + 1 < param_count) {
            try bytes.append(allocator, if (rand.boolean()) ';' else ':');
        }
    }

    if (rand.boolean()) {
        const intermediates = [_]u8{ ' ', '!', '"', '#', '$', '%', '&', '\'', '(', ')', '*', '+' };
        const count = 1 + rand.uintLessThan(usize, 2);
        var inter_idx: usize = 0;
        while (inter_idx < count) : (inter_idx += 1) {
            try bytes.append(allocator, intermediates[rand.uintLessThan(usize, intermediates.len)]);
        }
    }

    const finals = "@ABCDEFGHJKLMPSTX`abcdefghlmnprsuxt";
    try bytes.append(allocator, finals[rand.uintLessThan(usize, finals.len)]);
}

fn appendStringCommand(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, introducer: u8) !void {
    try bytes.append(allocator, 0x1B);
    try bytes.append(allocator, introducer);
    try appendAssetPayload(allocator, bytes, rand, 1 + rand.uintLessThan(usize, 48));
    if (rand.boolean()) {
        try bytes.append(allocator, 0x07);
    } else {
        try bytes.appendSlice(allocator, "\x1b\\");
    }
}

fn appendEscFinal(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    const finals = "78DEHM=>cnop";
    try bytes.append(allocator, 0x1B);
    try bytes.append(allocator, finals[rand.uintLessThan(usize, finals.len)]);
}

fn appendUtf8Burst(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    const codepoints = [_]u21{ 0x00A9, 0x03BB, 0x2500, 0x2603, 0x20AC, 0x1F600 };
    const count = 1 + rand.uintLessThan(usize, 6);
    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        var buf: [4]u8 = undefined;
        const cp = codepoints[rand.uintLessThan(usize, codepoints.len)];
        const len = try std.unicode.utf8Encode(cp, &buf);
        try bytes.appendSlice(allocator, buf[0..len]);
    }
}

fn appendControlBurst(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random) !void {
    const controls = [_]u8{ 0x00, 0x07, 0x08, 0x09, 0x0A, 0x0D, 0x7F };
    const count = 1 + rand.uintLessThan(usize, 4);
    var idx: usize = 0;
    while (idx < count) : (idx += 1) {
        try bytes.append(allocator, controls[rand.uintLessThan(usize, controls.len)]);
    }
}

fn appendAssetText(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, desired_len: usize) !void {
    var idx = pickAssetStart(rand);
    var written: usize = 0;
    while (idx < xterm_ctlseqs.len and written < desired_len) : (idx += 1) {
        try bytes.append(allocator, sanitizeTextByte(xterm_ctlseqs[idx]));
        written += 1;
    }
}

fn appendAssetPayload(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), rand: std.Random, desired_len: usize) !void {
    var idx = pickAssetStart(rand);
    var written: usize = 0;
    while (idx < xterm_ctlseqs.len and written < desired_len) : (idx += 1) {
        const source = xterm_ctlseqs[idx];
        const byte = switch (source) {
            0x1B => '.',
            0x00...0x1A, 0x1C...0x1F, 0x7F => ' ',
            else => source,
        };
        try bytes.append(allocator, byte);
        written += 1;
    }
}

fn sanitizeTextByte(byte: u8) u8 {
    return switch (byte) {
        0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F, 0x7F => ' ',
        else => byte,
    };
}

fn pickAssetStart(rand: std.Random) usize {
    if (xterm_ctlseqs.len == 0) return 0;
    return rand.uintLessThan(usize, xterm_ctlseqs.len);
}

fn digestEvents(events: []const Event) EventDigest {
    var hasher = std.hash.Wyhash.init(0);
    var token_count: usize = 0;

    for (events) |event| {
        switch (event) {
            .print => |cp| {
                hashValue(&hasher, @as(u8, 1));
                hashValue(&hasher, cp);
                token_count += 1;
            },
            .execute => |ctrl| {
                hashValue(&hasher, @as(u8, 2));
                hashValue(&hasher, ctrl);
                token_count += 1;
            },
            .invalid => {
                hashValue(&hasher, @as(u8, 3));
                token_count += 1;
            },
            .csi => |csi| {
                hashValue(&hasher, @as(u8, 4));
                hashValue(&hasher, csi.final);
                hashValue(&hasher, csi.leader);
                hashValue(&hasher, csi.private);
                hashValue(&hasher, csi.count);
                hashValue(&hasher, csi.intermediates_len);
                for (csi.params) |param| hashValue(&hasher, param);
                for (csi.intermediates) |byte| hashValue(&hasher, byte);
                token_count += 1;
            },
            .osc => |osc| {
                hashValue(&hasher, @as(u8, 5));
                hashValue(&hasher, @intFromEnum(osc.term));
                hashValue(&hasher, osc.data.len);
                hasher.update(osc.data);
                token_count += 1;
            },
            .apc_start => {
                hashValue(&hasher, @as(u8, 6));
                token_count += 1;
            },
            .apc_put => |byte| {
                hashValue(&hasher, @as(u8, 7));
                hashValue(&hasher, byte);
                token_count += 1;
            },
            .apc_end => {
                hashValue(&hasher, @as(u8, 8));
                token_count += 1;
            },
            .dcs_hook => |hook| {
                hashValue(&hasher, @as(u8, 9));
                hashValue(&hasher, hook.final);
                hashValue(&hasher, hook.count);
                hashValue(&hasher, hook.intermediates_len);
                for (hook.params) |param| hashValue(&hasher, param);
                for (hook.intermediates) |byte| hashValue(&hasher, byte);
                token_count += 1;
            },
            .dcs_put => |byte| {
                hashValue(&hasher, @as(u8, 10));
                hashValue(&hasher, byte);
                token_count += 1;
            },
            .dcs_unhook => {
                hashValue(&hasher, @as(u8, 11));
                token_count += 1;
            },
            .pm_start => {
                hashValue(&hasher, @as(u8, 12));
                token_count += 1;
            },
            .pm_put => |byte| {
                hashValue(&hasher, @as(u8, 13));
                hashValue(&hasher, byte);
                token_count += 1;
            },
            .pm_end => {
                hashValue(&hasher, @as(u8, 14));
                token_count += 1;
            },
            .esc_dispatch => |esc| {
                hashValue(&hasher, @as(u8, 15));
                hashValue(&hasher, @as(u8, 8));
                hashValue(&hasher, esc.final);
                hashValue(&hasher, esc.intermediates_len);
                for (esc.intermediates) |byte| hashValue(&hasher, byte);
                token_count += 1;
            },
        }
    }

    return .{ .hash = hasher.final(), .token_count = token_count };
}
