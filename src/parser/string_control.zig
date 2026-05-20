//! String-control parser state owners.

const std = @import("std");

pub const OscKind = enum {
    title,
    clipboard,
    hyperlink,
    other,
};

/// String-control terminator.
pub const Finish = enum {
    bel,
    st,
};

pub const FeedResult = union(enum) {
    put: u8,
    finish: Finish,
};

const DelimitedState = enum {
    idle,
    payload,
    esc,
};

/// Incremental string-control byte buffer.
pub const StringControl = struct {
    const Failure = error{ OutOfMemory, StringControlLimit };

    allocator: std.mem.Allocator,
    state: DelimitedState = .idle,
    buffer: std.ArrayList(u8),
    max_len: usize,
    bel_terminates: bool,
    alloc_failed: bool = false,
    overflowed: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        capacity: usize,
        max_len: usize,
        bel_terminates: bool,
    ) !StringControl {
        return .{
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
            .max_len = max_len,
            .bel_terminates = bel_terminates,
        };
    }

    pub fn deinit(self: *StringControl) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *StringControl) void {
        self.state = .idle;
        self.alloc_failed = false;
        self.overflowed = false;
        self.buffer.clearRetainingCapacity();
    }

    pub fn start(self: *StringControl) void {
        self.state = .payload;
        self.alloc_failed = false;
        self.overflowed = false;
        self.buffer.clearRetainingCapacity();
    }

    pub fn active(self: *const StringControl) bool {
        return stateActive(self.state);
    }

    pub fn escaping(self: *const StringControl) bool {
        return stateEscaping(self.state);
    }

    pub fn data(self: *const StringControl) []const u8 {
        return self.buffer.items;
    }

    pub fn clearFinished(self: *StringControl) void {
        self.buffer.clearRetainingCapacity();
    }

    pub fn takeFailure(self: *StringControl) ?Failure {
        var failure: ?Failure = null;
        if (self.overflowed) {
            failure = error.StringControlLimit;
        } else if (self.alloc_failed) {
            failure = error.OutOfMemory;
        }
        self.alloc_failed = false;
        self.overflowed = false;
        return failure;
    }

    pub fn feed(self: *StringControl, byte: u8) ?FeedResult {
        const result = feedDelimitedState(&self.state, byte, self.bel_terminates) orelse return null;
        switch (result) {
            .put => |payload_byte| self.append(payload_byte),
            .finish => {},
        }
        return result;
    }

    fn append(self: *StringControl, byte: u8) void {
        if (self.buffer.items.len >= self.max_len) {
            self.overflowed = true;
            return;
        }
        self.buffer.append(self.allocator, byte) catch {
            self.alloc_failed = true;
        };
    }
};

pub const OscControl = struct {
    const Failure = error{ OutOfMemory, StringControlLimit };
    const prefix_max_bytes = 8;

    allocator: std.mem.Allocator,
    state: OscState = .idle,
    buffer: std.ArrayList(u8),
    metadata_max_len: usize,
    large_max_len: usize,
    payload_max_len: usize,
    alloc_failed: bool = false,
    overflowed: bool = false,
    raw_has_separator: bool = false,
    prefix: [prefix_max_bytes]u8 = undefined,
    prefix_len: u8 = 0,
    command_acc: u16 = 0,
    command_ok: bool = false,
    command: ?u16 = null,
    kind: OscKind = .title,

    const OscState = enum {
        idle,
        prefix,
        prefix_esc,
        payload,
        payload_esc,
        raw,
        raw_esc,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        capacity: usize,
        metadata_max_len: usize,
        large_max_len: usize,
    ) !OscControl {
        return .{
            .allocator = allocator,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, capacity),
            .metadata_max_len = metadata_max_len,
            .large_max_len = large_max_len,
            .payload_max_len = metadata_max_len,
        };
    }

    pub fn deinit(self: *OscControl) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *OscControl) void {
        self.state = .idle;
        self.alloc_failed = false;
        self.overflowed = false;
        self.raw_has_separator = false;
        self.prefix_len = 0;
        self.command_acc = 0;
        self.command_ok = false;
        self.command = null;
        self.kind = .title;
        self.payload_max_len = self.metadata_max_len;
        self.buffer.clearRetainingCapacity();
    }

    pub fn start(self: *OscControl) void {
        self.reset();
        self.state = .prefix;
    }

    pub fn active(self: *const OscControl) bool {
        return self.state != .idle;
    }

    pub fn escaping(self: *const OscControl) bool {
        return switch (self.state) {
            .prefix_esc, .payload_esc, .raw_esc => true,
            else => false,
        };
    }

    pub fn payload(self: *const OscControl) []const u8 {
        return self.buffer.items;
    }

    pub fn currentCommand(self: *const OscControl) ?u16 {
        return self.command;
    }

    pub fn currentKind(self: *const OscControl) OscKind {
        if (self.state == .raw or self.state == .raw_esc) {
            return if (self.raw_has_separator) .other else .title;
        }
        return self.kind;
    }

    pub fn takeFailure(self: *OscControl) ?Failure {
        var failure: ?Failure = null;
        if (self.overflowed) {
            failure = error.StringControlLimit;
        } else if (self.alloc_failed) {
            failure = error.OutOfMemory;
        }
        self.alloc_failed = false;
        self.overflowed = false;
        return failure;
    }

    pub fn feed(self: *OscControl, byte: u8) ?FeedResult {
        return switch (self.state) {
            .idle => null,
            .prefix => self.feedPrefix(byte),
            .prefix_esc => self.feedPrefixEsc(byte),
            .payload, .payload_esc => self.feedPayload(byte),
            .raw, .raw_esc => self.feedRaw(byte),
        };
    }

    fn feedPrefix(self: *OscControl, byte: u8) ?FeedResult {
        if (byte == 0x07) {
            self.finishPrefix();
            return .{ .finish = .bel };
        }
        if (byte == 0x9C) {
            self.finishPrefix();
            return .{ .finish = .st };
        }
        if (byte == 0x1B) {
            self.state = .prefix_esc;
            return null;
        }
        if (byte == ';') {
            if (!self.enterPayloadFromPrefix()) return .{ .put = byte };
            return .{ .put = byte };
        }
        if (isDigit(byte) and self.prefix_len < prefix_max_bytes) {
            self.prefix[self.prefix_len] = byte;
            self.prefix_len += 1;
            self.pushCommandDigit(byte);
            return .{ .put = byte };
        }
        self.enterRawFromPrefix(byte, false);
        return .{ .put = byte };
    }

    fn feedPrefixEsc(self: *OscControl, byte: u8) ?FeedResult {
        if (byte == '\\') {
            self.finishPrefix();
            return .{ .finish = .st };
        }
        self.state = .prefix;
        return self.feedPrefix(byte);
    }

    fn feedPayload(self: *OscControl, byte: u8) ?FeedResult {
        switch (self.state) {
            .payload => {
                if (byte == 0x07) {
                    self.state = .idle;
                    return .{ .finish = .bel };
                }
                if (byte == 0x9C) {
                    self.state = .idle;
                    return .{ .finish = .st };
                }
                if (byte == 0x1B) {
                    self.state = .payload_esc;
                    return null;
                }
                self.append(byte);
                return .{ .put = byte };
            },
            .payload_esc => {
                if (byte == '\\') {
                    self.state = .idle;
                    return .{ .finish = .st };
                }
                self.state = .payload;
                self.append(byte);
                return .{ .put = byte };
            },
            else => unreachable,
        }
    }

    fn feedRaw(self: *OscControl, byte: u8) ?FeedResult {
        switch (self.state) {
            .raw => {
                if (byte == 0x07) {
                    self.finishRaw();
                    return .{ .finish = .bel };
                }
                if (byte == 0x9C) {
                    self.finishRaw();
                    return .{ .finish = .st };
                }
                if (byte == 0x1B) {
                    self.state = .raw_esc;
                    return null;
                }
                if (byte == ';') self.raw_has_separator = true;
                self.append(byte);
                return .{ .put = byte };
            },
            .raw_esc => {
                if (byte == '\\') {
                    self.finishRaw();
                    return .{ .finish = .st };
                }
                self.state = .raw;
                if (byte == ';') self.raw_has_separator = true;
                self.append(byte);
                return .{ .put = byte };
            },
            else => unreachable,
        }
    }

    fn finishPrefix(self: *OscControl) void {
        if (self.currentPrefixCommand()) |command| {
            self.command = command;
            self.kind = classifyCommand(command);
            self.payload_max_len = self.payloadMaxLen(command);
        } else {
            self.command = null;
            self.kind = if (self.raw_has_separator) .other else .title;
        }
        self.state = .idle;
    }

    fn finishRaw(self: *OscControl) void {
        self.command = null;
        self.kind = if (self.raw_has_separator) .other else .title;
        self.state = .idle;
    }

    fn enterPayloadFromPrefix(self: *OscControl) bool {
        if (self.currentPrefixCommand()) |command| {
            self.command = command;
            self.kind = classifyCommand(command);
            self.payload_max_len = self.payloadMaxLen(command);
            self.state = .payload;
            return true;
        }
        self.enterRawFromPrefix(';', true);
        return false;
    }

    fn enterRawFromPrefix(self: *OscControl, byte: u8, has_separator: bool) void {
        self.command = null;
        self.kind = .other;
        self.raw_has_separator = has_separator;
        self.state = .raw;
        var idx: u8 = 0;
        while (idx < self.prefix_len) : (idx += 1) self.append(self.prefix[idx]);
        self.prefix_len = 0;
        if (byte == ';') self.raw_has_separator = true;
        self.append(byte);
    }

    fn currentPrefixCommand(self: *const OscControl) ?u16 {
        if (self.prefix_len == 0) return null;
        if (!self.command_ok) return null;
        return self.command_acc;
    }

    fn pushCommandDigit(self: *OscControl, byte: u8) void {
        if (self.prefix_len == 1) {
            self.command_acc = byte - '0';
            self.command_ok = true;
            return;
        }
        if (!self.command_ok) return;
        const digit: u16 = byte - '0';
        const next, const mul_overflow = @mulWithOverflow(self.command_acc, 10);
        if (mul_overflow != 0) {
            self.command_ok = false;
            return;
        }
        const value, const add_overflow = @addWithOverflow(next, digit);
        if (add_overflow != 0) {
            self.command_ok = false;
            return;
        }
        self.command_acc = value;
    }

    fn append(self: *OscControl, byte: u8) void {
        if (self.buffer.items.len >= self.payload_max_len) {
            self.overflowed = true;
            return;
        }
        self.buffer.append(self.allocator, byte) catch {
            self.alloc_failed = true;
        };
    }

    fn payloadMaxLen(self: *const OscControl, command: u16) usize {
        return switch (command) {
            52, 66, 5113, 5522 => self.large_max_len,
            else => self.metadata_max_len,
        };
    }
};

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
}

fn classifyCommand(command: u16) OscKind {
    return switch (command) {
        0, 1, 2 => .title,
        8 => .hyperlink,
        52 => .clipboard,
        else => .other,
    };
}

/// Incremental string-control parser state without payload ownership.
pub const PassthroughControl = struct {
    state: DelimitedState = .idle,
    bel_terminates: bool,

    pub fn init(bel_terminates: bool) PassthroughControl {
        return .{ .bel_terminates = bel_terminates };
    }

    pub fn deinit(self: *PassthroughControl) void {
        _ = self;
    }

    pub fn reset(self: *PassthroughControl) void {
        self.state = .idle;
    }

    pub fn clearFinished(self: *PassthroughControl) void {
        _ = self;
    }

    pub fn start(self: *PassthroughControl) void {
        self.state = .payload;
    }

    pub fn active(self: *const PassthroughControl) bool {
        return stateActive(self.state);
    }

    pub fn escaping(self: *const PassthroughControl) bool {
        return stateEscaping(self.state);
    }

    pub fn feed(self: *PassthroughControl, byte: u8) ?FeedResult {
        return feedDelimitedState(&self.state, byte, self.bel_terminates);
    }
};

fn stateActive(state: DelimitedState) bool {
    return state != .idle;
}

fn stateEscaping(state: DelimitedState) bool {
    return state == .esc;
}

fn feedDelimitedState(state: *DelimitedState, byte: u8, bel_terminates: bool) ?FeedResult {
    return switch (state.*) {
        .idle => null,
        .payload => feedPayloadState(state, byte, bel_terminates),
        .esc => feedEscState(state, byte),
    };
}

fn feedPayloadState(state: *DelimitedState, byte: u8, bel_terminates: bool) ?FeedResult {
    if (bel_terminates and byte == 0x07) {
        state.* = .idle;
        return .{ .finish = .bel };
    }
    if (byte == 0x9C) {
        state.* = .idle;
        return .{ .finish = .st };
    }
    if (byte == 0x1B) {
        state.* = .esc;
        return null;
    }
    return .{ .put = byte };
}

fn feedEscState(state: *DelimitedState, byte: u8) ?FeedResult {
    if (byte == '\\') {
        state.* = .idle;
        return .{ .finish = .st };
    }

    // Stray ESC marker is dropped; following byte stays payload.
    state.* = .payload;
    return .{ .put = byte };
}

test "osc control: title payload keeps metadata limit" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 32);
    defer osc.deinit();
    osc.start();
    for ("0;hello") |byte| _ = osc.feed(byte);
    _ = osc.feed(0x07);
    try std.testing.expectEqual(@as(?u16, 0), osc.currentCommand());
    try std.testing.expectEqual(OscKind.title, osc.currentKind());
    try std.testing.expectEqualStrings("hell", osc.payload());
    try std.testing.expectEqual(error.StringControlLimit, osc.takeFailure().?);
}

test "osc control: clipboard payload uses large limit" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 32);
    defer osc.deinit();
    osc.start();
    for ("52;c;abcdefgh") |byte| _ = osc.feed(byte);
    _ = osc.feed(0x07);
    try std.testing.expectEqual(@as(?u16, 52), osc.currentCommand());
    try std.testing.expectEqual(OscKind.clipboard, osc.currentKind());
    try std.testing.expectEqualStrings("c;abcdefgh", osc.payload());
    try std.testing.expectEqual(@as(?(error{ OutOfMemory, StringControlLimit }), null), osc.takeFailure());
}
