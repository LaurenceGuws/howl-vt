//! Responsibility: consume byte streams and emit parser events.
//! Ownership: parser state-machine core.
//! Reason: implement deterministic VT stream decoding boundaries.

const std = @import("std");
const stream_mod = @import("stream.zig");
const csi_mod = @import("csi.zig");

/// Escape-state machine mode.
const EscState = enum {
    ground,
    esc,
    csi,
    charset,
};

/// OSC parse-state mode.
const OscState = enum {
    idle,
    osc,
    osc_esc,
};

/// APC parse-state mode.
const ApcState = enum {
    idle,
    apc,
    apc_esc,
};

/// DCS parse-state mode.
const DcsState = enum {
    idle,
    dcs,
    dcs_esc,
};

/// PM parse-state mode.
const PmState = enum {
    idle,
    pm,
    pm_esc,
};

/// OSC termination style.
pub const OscTerminator = enum {
    bel,
    st,
};

/// Character set selector.
const Charset = enum {
    ascii,
    dec_special,
};

/// Character set target selector.
const CharsetTarget = enum {
    g0,
    g1,
};

pub const DeccirCharsetState = struct {
    g0_designation: u8,
    g1_designation: u8,
    gl_index: u8,
};

/// Parser sink callback interface.
pub const Sink = struct {
    ptr: *anyopaque,
    onStreamEventFn: *const fn (*anyopaque, stream_mod.StreamEvent) void,
    onAsciiSliceFn: *const fn (*anyopaque, []const u8) void,
    onCsiFn: *const fn (*anyopaque, csi_mod.CsiAction) void,
    onOscFn: *const fn (*anyopaque, []const u8, OscTerminator) void,
    onApcFn: *const fn (*anyopaque, []const u8) void,
    onDcsFn: *const fn (*anyopaque, []const u8) void,
    onPmFn: *const fn (*anyopaque, []const u8) void,
    onEscFinalFn: *const fn (*anyopaque, u8) void,

    /// Emit stream event callback.
    pub fn onStreamEvent(self: Sink, event: stream_mod.StreamEvent) void {
        self.onStreamEventFn(self.ptr, event);
    }

    /// Emit ASCII slice callback.
    pub fn onAsciiSlice(self: Sink, bytes: []const u8) void {
        self.onAsciiSliceFn(self.ptr, bytes);
    }

    /// Emit CSI callback.
    pub fn onCsi(self: Sink, action: csi_mod.CsiAction) void {
        self.onCsiFn(self.ptr, action);
    }

    /// Emit OSC callback.
    pub fn onOsc(self: Sink, data: []const u8, terminator: OscTerminator) void {
        self.onOscFn(self.ptr, data, terminator);
    }

    /// Emit APC callback.
    pub fn onApc(self: Sink, data: []const u8) void {
        self.onApcFn(self.ptr, data);
    }

    /// Emit DCS callback.
    pub fn onDcs(self: Sink, data: []const u8) void {
        self.onDcsFn(self.ptr, data);
    }

    /// Emit PM callback.
    pub fn onPm(self: Sink, data: []const u8) void {
        self.onPmFn(self.ptr, data);
    }

    /// Emit ESC-final callback.
    pub fn onEscFinal(self: Sink, byte: u8) void {
        self.onEscFinalFn(self.ptr, byte);
    }
};

/// Stateful parser for terminal input streams.
pub const Parser = struct {
    allocator: std.mem.Allocator,
    sink: Sink,
    stream: stream_mod.Stream,
    esc_state: EscState,
    csi: csi_mod.CsiParser,
    osc_state: OscState,
    osc_terminator: OscTerminator,
    osc_buffer: std.ArrayList(u8),
    apc_state: ApcState,
    apc_buffer: std.ArrayList(u8),
    dcs_state: DcsState,
    dcs_buffer: std.ArrayList(u8),
    pm_state: PmState,
    pm_buffer: std.ArrayList(u8),
    g0_charset: Charset,
    g1_charset: Charset,
    gl_charset: Charset,
    gl_target: CharsetTarget,
    charset_target: CharsetTarget,

    /// Initialize parser state and owned buffers.
    pub fn init(allocator: std.mem.Allocator, sink: Sink) !Parser {
        var osc_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer osc_buffer.deinit(allocator);

        var apc_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer apc_buffer.deinit(allocator);

        var dcs_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer dcs_buffer.deinit(allocator);

        var pm_buffer = try std.ArrayList(u8).initCapacity(allocator, 256);
        errdefer pm_buffer.deinit(allocator);

        return .{
            .allocator = allocator,
            .sink = sink,
            .stream = .{},
            .esc_state = .ground,
            .csi = .{},
            .osc_state = .idle,
            .osc_terminator = .st,
            .osc_buffer = osc_buffer,
            .apc_state = .idle,
            .apc_buffer = apc_buffer,
            .dcs_state = .idle,
            .dcs_buffer = dcs_buffer,
            .pm_state = .idle,
            .pm_buffer = pm_buffer,
            .g0_charset = .ascii,
            .g1_charset = .ascii,
            .gl_charset = .ascii,
            .gl_target = .g0,
            .charset_target = .g0,
        };
    }

    /// Release parser-owned buffers.
    pub fn deinit(self: *Parser) void {
        self.osc_buffer.deinit(self.allocator);
        self.apc_buffer.deinit(self.allocator);
        self.dcs_buffer.deinit(self.allocator);
        self.pm_buffer.deinit(self.allocator);
    }

    /// Reset parser state and transient buffers.
    pub fn reset(self: *Parser) void {
        self.stream.reset();
        self.csi.reset();
        self.esc_state = .ground;
        self.osc_state = .idle;
        self.osc_terminator = .st;
        self.apc_state = .idle;
        self.dcs_state = .idle;
        self.pm_state = .idle;
        self.g0_charset = .ascii;
        self.g1_charset = .ascii;
        self.gl_charset = .ascii;
        self.gl_target = .g0;
        self.charset_target = .g0;
        self.osc_buffer.clearRetainingCapacity();
        self.apc_buffer.clearRetainingCapacity();
        self.dcs_buffer.clearRetainingCapacity();
        self.pm_buffer.clearRetainingCapacity();
    }

    /// Handle one byte of terminal input.
    pub fn handleByte(self: *Parser, byte: u8) void {
        if (self.osc_state != .idle) {
            self.handleOscByte(byte);
            return;
        }
        if (self.apc_state != .idle) {
            self.handleApcByte(byte);
            return;
        }
        if (self.dcs_state != .idle) {
            self.handleDcsByte(byte);
            return;
        }
        if (self.pm_state != .idle) {
            self.handlePmByte(byte);
            return;
        }
        switch (self.esc_state) {
            .ground => {
                if (byte == 0x1B) {
                    self.esc_state = .esc;
                    self.stream.reset();
                    self.csi.reset();
                    self.osc_state = .idle;
                    return;
                }
                if (byte == 0x0E) {
                    self.gl_charset = self.g1_charset;
                    self.gl_target = .g1;
                    return;
                }
                if (byte == 0x0F) {
                    self.gl_charset = self.g0_charset;
                    self.gl_target = .g0;
                    return;
                }
                if (self.gl_charset == .dec_special and byte >= 0x20 and byte <= 0x7e) {
                    self.sink.onStreamEvent(.{ .codepoint = mapDecSpecial(byte) });
                    return;
                }
                if (self.stream.feed(byte)) |event| {
                    self.sink.onStreamEvent(event);
                }
            },
            .esc => {
                if (byte == '[') {
                    self.esc_state = .csi;
                    self.csi.reset();
                } else if (byte == ']') {
                    self.esc_state = .ground;
                    self.osc_state = .osc;
                    self.osc_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == 'P') {
                    self.esc_state = .ground;
                    self.dcs_state = .dcs;
                    self.dcs_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == '_') {
                    self.esc_state = .ground;
                    self.apc_state = .apc;
                    self.apc_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == '^') {
                    self.esc_state = .ground;
                    self.pm_state = .pm;
                    self.pm_buffer.clearRetainingCapacity();
                    return;
                } else if (byte == '(') {
                    self.charset_target = .g0;
                    self.esc_state = .charset;
                } else if (byte == ')') {
                    self.charset_target = .g1;
                    self.esc_state = .charset;
                } else {
                    self.sink.onEscFinal(byte);
                    self.esc_state = .ground;
                }
            },
            .charset => {
                const charset: Charset = switch (byte) {
                    '0' => .dec_special,
                    'B' => .ascii,
                    else => .ascii,
                };
                switch (self.charset_target) {
                    .g0 => self.g0_charset = charset,
                    .g1 => self.g1_charset = charset,
                }
                if (self.charset_target == .g0) {
                    self.gl_charset = self.g0_charset;
                    self.gl_target = .g0;
                }
                self.esc_state = .ground;
            },
            .csi => {
                if (self.csi.feed(byte)) |action| {
                    self.sink.onCsi(action);
                    self.esc_state = .ground;
                }
            },
        }
    }

    /// Handle a byte slice of terminal input.
    pub fn handleSlice(self: *Parser, bytes: []const u8) void {
        var i: usize = 0;
        while (i < bytes.len) {
            if (self.osc_state != .idle) {
                self.handleOscByte(bytes[i]);
                i += 1;
                continue;
            }
            if (self.apc_state != .idle) {
                self.handleApcByte(bytes[i]);
                i += 1;
                continue;
            }
            if (self.dcs_state != .idle) {
                self.handleDcsByte(bytes[i]);
                i += 1;
                continue;
            }
            if (self.pm_state != .idle) {
                self.handlePmByte(bytes[i]);
                i += 1;
                continue;
            }

            if (self.esc_state == .ground and self.stream.decoder.needed == 0 and self.gl_charset == .ascii) {
                const start = i;
                // ASCII fast path batches printable bytes into one sink event.
                while (i < bytes.len) {
                    const b = bytes[i];
                    if (b < 0x20 or b == 0x7f or b == 0x1b or b >= 0x80) break;
                    i += 1;
                }
                if (i > start) {
                    self.sink.onAsciiSlice(bytes[start..i]);
                    continue;
                }
            }

            self.handleByte(bytes[i]);
            i += 1;
        }
    }

    pub fn deccirCharsetState(self: *const Parser) DeccirCharsetState {
        return .{
            .g0_designation = charsetDesignation(self.g0_charset),
            .g1_designation = charsetDesignation(self.g1_charset),
            .gl_index = switch (self.gl_target) {
                .g0 => 0,
                .g1 => 1,
            },
        };
    }

    fn handleOscByte(self: *Parser, byte: u8) void {
        switch (self.osc_state) {
            .idle => return,
            .osc => {
                if (byte == 0x07) {
                    self.osc_terminator = .bel;
                    self.finishOsc();
                    return;
                }
                if (byte == 0x1B) {
                    self.osc_state = .osc_esc;
                    return;
                }
                if (self.osc_buffer.items.len < 4096) {
                    self.osc_buffer.append(self.allocator, byte) catch {};
                }
            },
            .osc_esc => {
                if (byte == '\\') {
                    self.osc_terminator = .st;
                    self.finishOsc();
                    return;
                }

                // Stray ESC marker is dropped; following byte stays OSC payload.
                self.osc_state = .osc;
                if (self.osc_buffer.items.len < 4096) {
                    self.osc_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishOsc(self: *Parser) void {
        self.sink.onOsc(self.osc_buffer.items, self.osc_terminator);
        self.osc_buffer.clearRetainingCapacity();
        self.osc_state = .idle;
    }

    fn handleApcByte(self: *Parser, byte: u8) void {
        const apc_max_len: usize = 1024 * 1024;
        switch (self.apc_state) {
            .idle => return,
            .apc => {
                if (byte == 0x07) {
                    self.finishApc();
                    return;
                }
                if (byte == 0x1B) {
                    self.apc_state = .apc_esc;
                    return;
                }
                if (self.apc_buffer.items.len < apc_max_len) {
                    self.apc_buffer.append(self.allocator, byte) catch {};
                }
            },
            .apc_esc => {
                if (byte == '\\') {
                    self.finishApc();
                    return;
                }

                self.apc_state = .apc;
                if (self.apc_buffer.items.len < apc_max_len) {
                    self.apc_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishApc(self: *Parser) void {
        self.sink.onApc(self.apc_buffer.items);
        self.apc_buffer.clearRetainingCapacity();
        self.apc_state = .idle;
    }

    fn handleDcsByte(self: *Parser, byte: u8) void {
        switch (self.dcs_state) {
            .idle => return,
            .dcs => {
                if (byte == 0x1B) {
                    self.dcs_state = .dcs_esc;
                    return;
                }
                if (self.dcs_buffer.items.len < 4096) {
                    self.dcs_buffer.append(self.allocator, byte) catch {};
                }
            },
            .dcs_esc => {
                if (byte == '\\') {
                    self.finishDcs();
                    return;
                }

                // Stray ESC marker is dropped; following byte stays DCS payload.
                self.dcs_state = .dcs;
                if (self.dcs_buffer.items.len < 4096) {
                    self.dcs_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishDcs(self: *Parser) void {
        self.sink.onDcs(self.dcs_buffer.items);
        self.dcs_buffer.clearRetainingCapacity();
        self.dcs_state = .idle;
    }

    fn handlePmByte(self: *Parser, byte: u8) void {
        switch (self.pm_state) {
            .idle => return,
            .pm => {
                if (byte == 0x1B) {
                    self.pm_state = .pm_esc;
                    return;
                }
                if (self.pm_buffer.items.len < 4096) {
                    self.pm_buffer.append(self.allocator, byte) catch {};
                }
            },
            .pm_esc => {
                if (byte == '\\') {
                    self.finishPm();
                    return;
                }

                self.pm_state = .pm;
                if (self.pm_buffer.items.len < 4096) {
                    self.pm_buffer.append(self.allocator, byte) catch {};
                }
            },
        }
    }

    fn finishPm(self: *Parser) void {
        self.sink.onPm(self.pm_buffer.items);
        self.pm_buffer.clearRetainingCapacity();
        self.pm_state = .idle;
    }
};

fn mapDecSpecial(byte: u8) u21 {
    return switch (byte) {
        '`' => 0x25C6, // ◆
        'a' => 0x2592, // ▒
        'f' => 0x00B0, // °
        'g' => 0x00B1, // ±
        'h' => 0x2424, // ␤
        'i' => 0x240B, // ␋
        'j' => 0x2518, // ┘
        'k' => 0x2510, // ┐
        'l' => 0x250C, // ┌
        'm' => 0x2514, // └
        'n' => 0x253C, // ┼
        'o' => 0x23BA, // ⎺
        'p' => 0x23BB, // ⎻
        'q' => 0x2500, // ─
        'r' => 0x23BC, // ⎼
        's' => 0x23BD, // ⎽
        't' => 0x251C, // ├
        'u' => 0x2524, // ┤
        'v' => 0x2534, // ┴
        'w' => 0x252C, // ┬
        'x' => 0x2502, // │
        'y' => 0x2264, // ≤
        'z' => 0x2265, // ≥
        '{' => 0x03C0, // π
        '|' => 0x2260, // ≠
        '}' => 0x00A3, // £
        '~' => 0x00B7, // ·
        else => byte,
    };
}

fn charsetDesignation(charset: Charset) u8 {
    return switch (charset) {
        .ascii => 'B',
        .dec_special => '0',
    };
}


const Event = union(enum) {
    stream_codepoint: u21,
    stream_control: u8,
    stream_invalid,
    ascii_slice: []const u8,
    csi: struct { final: u8, params: [16]i32, count: u8 },
    osc: struct { data: []const u8, term: OscTerminator },
    apc: []const u8,
    dcs: []const u8,
    pm: []const u8,
    esc_final: u8,
};

const Harness = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),

    fn init(allocator: std.mem.Allocator) Harness {
        return .{ .allocator = allocator, .events = std.ArrayList(Event).initCapacity(allocator, 16) catch unreachable };
    }

    fn deinit(self: *Harness) void {
        for (self.events.items) |event| {
            switch (event) {
                .ascii_slice => |data| self.allocator.free(data),
                .osc => |osc_ev| self.allocator.free(osc_ev.data),
                .apc => |data| self.allocator.free(data),
                .dcs => |data| self.allocator.free(data),
                .pm => |data| self.allocator.free(data),
                else => {},
            }
        }
        self.events.deinit(self.allocator);
    }

    fn toSink(self: *Harness) Sink {
        return .{ .ptr = self, .onStreamEventFn = onStreamEvent, .onAsciiSliceFn = onAsciiSlice, .onCsiFn = onCsi, .onOscFn = onOsc, .onApcFn = onApc, .onDcsFn = onDcs, .onPmFn = onPm, .onEscFinalFn = onEscFinal };
    }

    fn onStreamEvent(ptr: *anyopaque, event: stream_mod.StreamEvent) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const ev = switch (event) {
            .codepoint => |cp| Event{ .stream_codepoint = cp },
            .control => |ctrl| Event{ .stream_control = ctrl },
            .invalid => Event.stream_invalid,
        };
        self.events.append(self.allocator, ev) catch {};
    }

    fn onAsciiSlice(ptr: *anyopaque, bytes: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, bytes) catch return;
        self.events.append(self.allocator, Event{ .ascii_slice = owned }) catch {};
    }

    fn onCsi(ptr: *anyopaque, action: csi_mod.CsiAction) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{ .csi = .{ .final = action.final, .params = action.params, .count = action.count } }) catch {};
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, term: OscTerminator) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .osc = .{ .data = owned, .term = term } }) catch {};
    }

    fn onApc(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .apc = owned }) catch {};
    }

    fn onDcs(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .dcs = owned }) catch {};
    }

    fn onPm(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, Event{ .pm = owned }) catch {};
    }

    fn onEscFinal(ptr: *anyopaque, byte: u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, Event{ .esc_final = byte }) catch {};
    }
};
test "parser: mixed stream exact sequence (ASCII+CSI+ASCII)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("AB\x1b[31mC");
    try std.testing.expectEqual(@as(usize, 3), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .ascii_slice);
    try std.testing.expect(harness.events.items[1] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[1].csi.final);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[1].csi.params[0]);
    try std.testing.expect(harness.events.items[2] == .ascii_slice);
}

test "parser: ASCII fast path preserves spaces" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("A B");

    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .ascii_slice);
    try std.testing.expectEqualSlices(u8, "A B", harness.events.items[0].ascii_slice);
}

test "parser: ESC final passthrough (ESC M)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1bM");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .esc_final);
    try std.testing.expectEqual(@as(u8, 'M'), harness.events.items[0].esc_final);
}

test "parser: OSC with BEL terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]title\x07");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqual(OscTerminator.bel, harness.events.items[0].osc.term);
    try std.testing.expectEqualSlices(u8, "title", harness.events.items[0].osc.data);
}

test "parser: OSC with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]url\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqual(OscTerminator.st, harness.events.items[0].osc.term);
    try std.testing.expectEqualSlices(u8, "url", harness.events.items[0].osc.data);
}

test "parser: APC with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b_kitty\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .apc);
    try std.testing.expectEqualSlices(u8, "kitty", harness.events.items[0].apc);
}

test "parser: DCS with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1bPdata\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .dcs);
    try std.testing.expectEqualSlices(u8, "data", harness.events.items[0].dcs);
}

test "parser: PM with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b^ignored\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .pm);
    try std.testing.expectEqualSlices(u8, "ignored", harness.events.items[0].pm);
}

test "parser: split input - partial UTF-8 then completion" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleByte(0xE2);
    parser.handleByte(0x82);
    parser.handleByte(0xAC);
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x20AC), harness.events.items[0].stream_codepoint);
}

test "parser: split input - partial CSI then final byte" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleByte(0x1B);
    parser.handleByte('[');
    parser.handleByte('3');
    parser.handleByte('1');
    parser.handleByte('m');
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .csi);
    try std.testing.expectEqual(@as(u8, 'm'), harness.events.items[0].csi.final);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[0].csi.params[0]);
}

test "parser: stray ESC in OSC (marker dropped, byte appended)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]ab\x1bcd\x1b\\");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqualSlices(u8, "abcd", harness.events.items[0].osc.data);
}

test "parser: CSI with multiple parameters exact order" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b[1;31;40m");
    try std.testing.expectEqual(@as(usize, 1), harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .csi);
    try std.testing.expectEqual(@as(i32, 1), harness.events.items[0].csi.params[0]);
    try std.testing.expectEqual(@as(i32, 31), harness.events.items[0].csi.params[1]);
    try std.testing.expectEqual(@as(i32, 40), harness.events.items[0].csi.params[2]);
    try std.testing.expectEqual(@as(u8, 3), harness.events.items[0].csi.count);
}

test "parser: DEC special graphics maps box drawing bytes" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b(0lqkxmj\x1b(Bq");

    try std.testing.expectEqual(@as(usize, 7), harness.events.items.len);
    try std.testing.expectEqual(@as(u21, 0x250C), harness.events.items[0].stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x2500), harness.events.items[1].stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x2510), harness.events.items[2].stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x2502), harness.events.items[3].stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x2514), harness.events.items[4].stream_codepoint);
    try std.testing.expectEqual(@as(u21, 0x2518), harness.events.items[5].stream_codepoint);
    try std.testing.expect(harness.events.items[6] == .ascii_slice);
    try std.testing.expectEqualSlices(u8, "q", harness.events.items[6].ascii_slice);
}

test "parser: SO SI switch G1 DEC special graphics" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();

    parser.handleSlice("\x1b)0\x0eq\x0fq");

    try std.testing.expectEqual(@as(usize, 2), harness.events.items.len);
    try std.testing.expectEqual(@as(u21, 0x2500), harness.events.items[0].stream_codepoint);
    try std.testing.expect(harness.events.items[1] == .ascii_slice);
    try std.testing.expectEqualSlices(u8, "q", harness.events.items[1].ascii_slice);
}
