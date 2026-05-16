//! VT byte-stream parser.

const std = @import("std");
const stream_mod = @import("stream.zig");
const csi_mod = @import("csi.zig");
const events = @import("events.zig");
const string_control_mod = @import("string_control.zig");

const EscState = enum {
    ground,
    esc,
    csi,
    charset,
};

const Charset = enum {
    ascii,
    dec_special,
};

const CharsetTarget = enum {
    g0,
    g1,
};

pub const DeccirCharsetState = struct {
    g0_designation: u8,
    g1_designation: u8,
    gl_index: u8,
};

pub const Event = events.Event;
pub const ParsedEvents = events.ParsedEvents;
pub const ApplyFlow = @import("flow.zig").ApplyFlow;

/// Stateful parser for terminal input streams.
pub const Parser = struct {
    /// Stream event payload.
    pub const StreamEvent = stream_mod.StreamEvent;
    /// CSI action payload.
    pub const CsiAction = csi_mod.CsiAction;
    /// Maximum supported CSI parameter count.
    pub const max_params = csi_mod.max_params;
    /// Maximum supported CSI intermediate count.
    pub const max_intermediates = csi_mod.max_intermediates;

    /// OSC termination style.
    pub const OscTerminator = enum {
        bel,
        st,
    };

    /// Parser sink callback interface.
    pub const Sink = struct {
        ptr: *anyopaque,
        onStreamEventFn: *const fn (*anyopaque, StreamEvent) void,
        onAsciiSliceFn: *const fn (*anyopaque, []const u8) void,
        onCsiFn: *const fn (*anyopaque, CsiAction) void,
        onOscFn: *const fn (*anyopaque, []const u8, OscTerminator) void,
        onApcFn: *const fn (*anyopaque, []const u8) void,
        onDcsFn: *const fn (*anyopaque, []const u8) void,
        onPmFn: *const fn (*anyopaque, []const u8) void,
        onEscFinalFn: *const fn (*anyopaque, u8) void,

        /// Emit stream event callback.
        pub fn onStreamEvent(self: Sink, event: StreamEvent) void {
            self.onStreamEventFn(self.ptr, event);
        }

        /// Emit ASCII slice callback.
        pub fn onAsciiSlice(self: Sink, bytes: []const u8) void {
            self.onAsciiSliceFn(self.ptr, bytes);
        }

        /// Emit CSI callback.
        pub fn onCsi(self: Sink, action: CsiAction) void {
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

    allocator: std.mem.Allocator,
    sink: Sink,
    stream: stream_mod.Stream,
    esc_state: EscState,
    csi: csi_mod.CsiParser,
    osc: string_control_mod.StringControl,
    apc: string_control_mod.StringControl,
    dcs: string_control_mod.StringControl,
    pm: string_control_mod.StringControl,
    g0_charset: Charset,
    g1_charset: Charset,
    gl_charset: Charset,
    gl_target: CharsetTarget,
    charset_target: CharsetTarget,

    /// Initialize parser state and owned buffers.
    pub fn init(allocator: std.mem.Allocator, sink: Sink) !Parser {
        var osc = try string_control_mod.StringControl.init(allocator, 256, 4096, true);
        errdefer osc.deinit();

        var apc = try string_control_mod.StringControl.init(allocator, 256, 1024 * 1024, true);
        errdefer apc.deinit();

        var dcs = try string_control_mod.StringControl.init(allocator, 256, 4096, false);
        errdefer dcs.deinit();

        var pm = try string_control_mod.StringControl.init(allocator, 256, 4096, false);
        errdefer pm.deinit();

        return .{
            .allocator = allocator,
            .sink = sink,
            .stream = .{},
            .esc_state = .ground,
            .csi = .{},
            .osc = osc,
            .apc = apc,
            .dcs = dcs,
            .pm = pm,
            .g0_charset = .ascii,
            .g1_charset = .ascii,
            .gl_charset = .ascii,
            .gl_target = .g0,
            .charset_target = .g0,
        };
    }

    /// Release parser-owned buffers.
    pub fn deinit(self: *Parser) void {
        self.osc.deinit();
        self.apc.deinit();
        self.dcs.deinit();
        self.pm.deinit();
    }

    /// Reset parser state and transient buffers.
    pub fn reset(self: *Parser) void {
        self.stream.reset();
        self.csi.reset();
        self.esc_state = .ground;
        self.g0_charset = .ascii;
        self.g1_charset = .ascii;
        self.gl_charset = .ascii;
        self.gl_target = .g0;
        self.charset_target = .g0;
        self.osc.reset();
        self.apc.reset();
        self.dcs.reset();
        self.pm.reset();
    }

    /// Handle one byte of terminal input.
    pub fn handleByte(self: *Parser, byte: u8) void {
        std.debug.assert(self.activeControlCount() <= 1);
        if (self.handleActiveControlByte(byte)) return;

        switch (self.esc_state) {
            .ground => self.handleGroundByte(byte),
            .esc => self.handleEscByte(byte),
            .charset => self.handleCharsetByte(byte),
            .csi => self.handleCsiByte(byte),
        }
    }

    /// Handle a byte slice of terminal input.
    pub fn handleSlice(self: *Parser, bytes: []const u8) void {
        var remaining = bytes;
        while (remaining.len > 0) {
            std.debug.assert(self.activeControlCount() <= 1);
            if (self.handleActiveControlByte(remaining[0])) {
                remaining = remaining[1..];
                continue;
            }

            if (self.takeAsciiFastPath(remaining)) |rest| {
                remaining = rest;
                continue;
            }

            self.handleParserByte(remaining[0]);
            remaining = remaining[1..];
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
        if (self.osc.feed(byte)) |finish| {
            const terminator: OscTerminator = switch (finish) {
                .bel => .bel,
                .st => .st,
            };
            self.sink.onOsc(self.osc.data(), terminator);
            self.osc.clearFinished();
        }
    }

    fn handleActiveControlByte(self: *Parser, byte: u8) bool {
        std.debug.assert(self.activeControlCount() <= 1);
        if (self.osc.active()) {
            self.handleOscByte(byte);
            return true;
        }
        if (self.apc.active()) {
            self.handleApcByte(byte);
            return true;
        }
        if (self.dcs.active()) {
            self.handleDcsByte(byte);
            return true;
        }
        if (self.pm.active()) {
            self.handlePmByte(byte);
            return true;
        }
        return false;
    }

    fn handleParserByte(self: *Parser, byte: u8) void {
        std.debug.assert(self.activeControlCount() == 0);
        switch (self.esc_state) {
            .ground => self.handleGroundByte(byte),
            .esc => self.handleEscByte(byte),
            .charset => self.handleCharsetByte(byte),
            .csi => self.handleCsiByte(byte),
        }
    }

    fn handleGroundByte(self: *Parser, byte: u8) void {
        std.debug.assert(self.activeControlCount() == 0);
        if (byte == 0x1B) {
            self.startEscape();
            return;
        }
        if (byte == 0x0E) {
            self.selectGl(.g1);
            return;
        }
        if (byte == 0x0F) {
            self.selectGl(.g0);
            return;
        }
        if (self.isDecSpecialGraphic(byte)) {
            self.sink.onStreamEvent(.{ .codepoint = mapDecSpecial(byte) });
            return;
        }
        if (self.stream.feed(byte)) |event| {
            self.sink.onStreamEvent(event);
        }
    }

    fn handleEscByte(self: *Parser, byte: u8) void {
        switch (byte) {
            '[' => {
                self.esc_state = .csi;
                self.csi.reset();
            },
            ']' => self.startStringControl(&self.osc),
            'P' => self.startStringControl(&self.dcs),
            '_' => self.startStringControl(&self.apc),
            '^' => self.startStringControl(&self.pm),
            '(' => self.startCharsetDesignation(.g0),
            ')' => self.startCharsetDesignation(.g1),
            else => {
                self.sink.onEscFinal(byte);
                self.esc_state = .ground;
            },
        }
    }

    fn handleCharsetByte(self: *Parser, byte: u8) void {
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
            std.debug.assert(self.gl_charset == self.g0_charset);
            std.debug.assert(self.gl_target == .g0);
        }
        self.esc_state = .ground;
    }

    fn handleCsiByte(self: *Parser, byte: u8) void {
        if (self.csi.feed(byte)) |action| {
            self.sink.onCsi(action);
            self.esc_state = .ground;
        }
    }

    fn takeAsciiFastPath(self: *Parser, bytes: []const u8) ?[]const u8 {
        if (!self.canBatchAscii()) return null;

        const ascii = asciiPrefix(bytes);
        if (ascii.len == 0) return null;
        std.debug.assert(ascii.len <= bytes.len);
        std.debug.assert(isAsciiPrintableSlice(ascii));
        if (ascii.len < bytes.len) std.debug.assert(!isAsciiPrintableByte(bytes[ascii.len]));
        self.sink.onAsciiSlice(ascii);
        return bytes[ascii.len..];
    }

    fn canBatchAscii(self: *const Parser) bool {
        return self.esc_state == .ground and self.stream.decoder.needed == 0 and self.gl_charset == .ascii;
    }

    fn startEscape(self: *Parser) void {
        std.debug.assert(self.activeControlCount() == 0);
        self.esc_state = .esc;
        self.stream.reset();
        self.csi.reset();
        self.osc.reset();
        std.debug.assert(self.esc_state == .esc);
        std.debug.assert(!self.osc.active());
    }

    fn selectGl(self: *Parser, target: CharsetTarget) void {
        self.gl_target = target;
        self.gl_charset = switch (target) {
            .g0 => self.g0_charset,
            .g1 => self.g1_charset,
        };
        std.debug.assert(self.gl_charset == switch (self.gl_target) {
            .g0 => self.g0_charset,
            .g1 => self.g1_charset,
        });
    }

    fn isDecSpecialGraphic(self: *const Parser, byte: u8) bool {
        return self.gl_charset == .dec_special and byte >= 0x20 and byte <= 0x7e;
    }

    fn startStringControl(self: *Parser, control: *string_control_mod.StringControl) void {
        std.debug.assert(self.activeControlCount() == 0);
        self.esc_state = .ground;
        control.start();
        std.debug.assert(self.esc_state == .ground);
        std.debug.assert(control.active());
        std.debug.assert(self.activeControlCount() == 1);
    }

    fn startCharsetDesignation(self: *Parser, target: CharsetTarget) void {
        self.charset_target = target;
        self.esc_state = .charset;
        std.debug.assert(self.esc_state == .charset);
        std.debug.assert(self.charset_target == target);
    }

    fn handleApcByte(self: *Parser, byte: u8) void {
        if (self.apc.feed(byte)) |_| {
            self.sink.onApc(self.apc.data());
            self.apc.clearFinished();
        }
    }

    fn handleDcsByte(self: *Parser, byte: u8) void {
        if (self.dcs.feed(byte)) |_| {
            self.sink.onDcs(self.dcs.data());
            self.dcs.clearFinished();
        }
    }

    fn handlePmByte(self: *Parser, byte: u8) void {
        if (self.pm.feed(byte)) |_| {
            self.sink.onPm(self.pm.data());
            self.pm.clearFinished();
        }
    }

    fn activeControlCount(self: *const Parser) u3 {
        var count: u3 = 0;
        if (self.osc.active()) count += 1;
        if (self.apc.active()) count += 1;
        if (self.dcs.active()) count += 1;
        if (self.pm.active()) count += 1;
        return count;
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

fn asciiPrefix(bytes: []const u8) []const u8 {
    var remaining = bytes;
    while (remaining.len > 0) {
        const byte = remaining[0];
        if (byte < 0x20 or byte == 0x7f or byte == 0x1b or byte >= 0x80) break;
        remaining = remaining[1..];
    }
    return bytes[0 .. bytes.len - remaining.len];
}

fn isAsciiPrintableSlice(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (!isAsciiPrintableByte(byte)) return false;
    }
    return true;
}

fn isAsciiPrintableByte(byte: u8) bool {
    return byte >= 0x20 and byte != 0x7f and byte != 0x1b and byte < 0x80;
}

const HarnessEvent = union(enum) {
    stream_codepoint: u21,
    stream_control: u8,
    stream_invalid,
    ascii_slice: []const u8,
    csi: struct { final: u8, params: [16]i32, count: u8 },
    osc: struct { data: []const u8, term: Parser.OscTerminator },
    apc: []const u8,
    dcs: []const u8,
    pm: []const u8,
    esc_final: u8,
};

const Harness = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(HarnessEvent),

    fn init(allocator: std.mem.Allocator) Harness {
        return .{ .allocator = allocator, .events = std.ArrayList(HarnessEvent).initCapacity(allocator, 16) catch unreachable };
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

    fn toSink(self: *Harness) Parser.Sink {
        return .{ .ptr = self, .onStreamEventFn = onStreamEvent, .onAsciiSliceFn = onAsciiSlice, .onCsiFn = onCsi, .onOscFn = onOsc, .onApcFn = onApc, .onDcsFn = onDcs, .onPmFn = onPm, .onEscFinalFn = onEscFinal };
    }

    fn onStreamEvent(ptr: *anyopaque, event: Parser.StreamEvent) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const ev = switch (event) {
            .codepoint => |cp| HarnessEvent{ .stream_codepoint = cp },
            .control => |ctrl| HarnessEvent{ .stream_control = ctrl },
            .invalid => HarnessEvent.stream_invalid,
        };
        self.events.append(self.allocator, ev) catch {};
    }

    fn onAsciiSlice(ptr: *anyopaque, bytes: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, bytes) catch return;
        self.events.append(self.allocator, HarnessEvent{ .ascii_slice = owned }) catch {};
    }

    fn onCsi(ptr: *anyopaque, action: Parser.CsiAction) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, HarnessEvent{ .csi = .{ .final = action.final, .params = action.params, .count = action.count } }) catch {};
    }

    fn onOsc(ptr: *anyopaque, data: []const u8, term: Parser.OscTerminator) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, HarnessEvent{ .osc = .{ .data = owned, .term = term } }) catch {};
    }

    fn onApc(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, HarnessEvent{ .apc = owned }) catch {};
    }

    fn onDcs(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, HarnessEvent{ .dcs = owned }) catch {};
    }

    fn onPm(ptr: *anyopaque, data: []const u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        const owned = self.allocator.dupe(u8, data) catch return;
        self.events.append(self.allocator, HarnessEvent{ .pm = owned }) catch {};
    }

    fn onEscFinal(ptr: *anyopaque, byte: u8) void {
        const self: *Harness = @ptrCast(@alignCast(ptr));
        self.events.append(self.allocator, HarnessEvent{ .esc_final = byte }) catch {};
    }
};
test "parser: mixed stream exact sequence (ASCII+CSI+ASCII)" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("AB\x1b[31mC");
    try std.testing.expectEqual(3, harness.events.items.len);
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

    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqual(Parser.OscTerminator.bel, harness.events.items[0].osc.term);
    try std.testing.expectEqualSlices(u8, "title", harness.events.items[0].osc.data);
}

test "parser: OSC with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b]url\x1b\\");
    try std.testing.expectEqual(1, harness.events.items.len);
    try std.testing.expect(harness.events.items[0] == .osc);
    try std.testing.expectEqual(Parser.OscTerminator.st, harness.events.items[0].osc.term);
    try std.testing.expectEqualSlices(u8, "url", harness.events.items[0].osc.data);
}

test "parser: APC with ST terminator" {
    const gpa = std.testing.allocator;
    var harness = Harness.init(gpa);
    defer harness.deinit();
    var parser = try Parser.init(gpa, harness.toSink());
    defer parser.deinit();
    parser.handleSlice("\x1b_kitty\x1b\\");
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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
    try std.testing.expectEqual(1, harness.events.items.len);
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

    try std.testing.expectEqual(7, harness.events.items.len);
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

    try std.testing.expectEqual(2, harness.events.items.len);
    try std.testing.expectEqual(@as(u21, 0x2500), harness.events.items[0].stream_codepoint);
    try std.testing.expect(harness.events.items[1] == .ascii_slice);
    try std.testing.expectEqualSlices(u8, "q", harness.events.items[1].ascii_slice);
}
