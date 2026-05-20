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

    const CommandPolicy = struct {
        command: ?u16,
        kind: OscKind,
        max_len: usize,
    };

    allocator: std.mem.Allocator,
    state: OscState = .idle,
    buffer: std.ArrayList(u8),
    metadata_max_len: usize,
    large_max_len: usize,
    policy: CommandPolicy,
    alloc_failed: bool = false,
    overflowed: bool = false,
    command_acc: ?u16 = null,

    const OscState = enum {
        idle,
        prefix,
        prefix_esc,
        payload,
        payload_esc,
        raw,
        raw_esc,
    };

    const BodyKind = enum {
        payload,
        raw,
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
            .policy = .{ .command = null, .kind = .title, .max_len = metadata_max_len },
        };
    }

    pub fn deinit(self: *OscControl) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn reset(self: *OscControl) void {
        self.state = .idle;
        self.alloc_failed = false;
        self.overflowed = false;
        self.command_acc = null;
        self.policy = .{ .command = null, .kind = .title, .max_len = self.metadata_max_len };
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
        return self.policy.command;
    }

    pub fn currentKind(self: *const OscControl) OscKind {
        return self.policy.kind;
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
        if (isDigit(byte) and self.buffer.items.len < prefix_max_bytes) {
            self.append(byte);
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
        return self.feedBody(.payload, byte);
    }

    fn feedRaw(self: *OscControl, byte: u8) ?FeedResult {
        return self.feedBody(.raw, byte);
    }

    fn feedBody(self: *OscControl, comptime kind: BodyKind, byte: u8) ?FeedResult {
        switch (self.state) {
            bodyState(kind) => {
                if (byte == 0x07) {
                    self.finishBody(kind);
                    return .{ .finish = .bel };
                }
                if (byte == 0x9C) {
                    self.finishBody(kind);
                    return .{ .finish = .st };
                }
                if (byte == 0x1B) {
                    self.state = bodyEscState(kind);
                    return null;
                }
                if (kind == .raw and byte == ';') self.policy.kind = .other;
                self.append(byte);
                return .{ .put = byte };
            },
            bodyEscState(kind) => {
                if (byte == '\\') {
                    self.finishBody(kind);
                    return .{ .finish = .st };
                }
                self.state = bodyState(kind);
                if (kind == .raw and byte == ';') self.policy.kind = .other;
                self.append(byte);
                return .{ .put = byte };
            },
            else => unreachable,
        }
    }

    fn finishPrefix(self: *OscControl) void {
        if (self.currentPrefixCommand()) |command| {
            self.setCommandPolicy(command);
            self.buffer.clearRetainingCapacity();
        } else {
            self.policy = .{ .command = null, .kind = .title, .max_len = self.metadata_max_len };
        }
        self.state = .idle;
    }

    fn finishRaw(self: *OscControl) void {
        self.policy.command = null;
        self.state = .idle;
    }

    fn finishBody(self: *OscControl, comptime kind: BodyKind) void {
        switch (kind) {
            .payload => self.state = .idle,
            .raw => self.finishRaw(),
        }
    }

    fn enterPayloadFromPrefix(self: *OscControl) bool {
        if (self.currentPrefixCommand()) |command| {
            self.setCommandPolicy(command);
            self.buffer.clearRetainingCapacity();
            self.state = .payload;
            return true;
        }
        self.enterRawFromPrefix(';', true);
        return false;
    }

    fn enterRawFromPrefix(self: *OscControl, byte: u8, has_separator: bool) void {
        self.policy = .{
            .command = null,
            .kind = if (has_separator) .other else .title,
            .max_len = self.metadata_max_len,
        };
        self.state = .raw;
        if (byte == ';') self.policy.kind = .other;
        self.append(byte);
    }

    fn currentPrefixCommand(self: *const OscControl) ?u16 {
        if (self.buffer.items.len == 0) return null;
        return self.command_acc;
    }

    fn pushCommandDigit(self: *OscControl, byte: u8) void {
        if (self.buffer.items.len == 1) {
            self.command_acc = byte - '0';
            return;
        }
        const current = self.command_acc orelse return;
        const digit: u16 = byte - '0';
        const next, const mul_overflow = @mulWithOverflow(current, 10);
        if (mul_overflow != 0) {
            self.command_acc = null;
            return;
        }
        const value, const add_overflow = @addWithOverflow(next, digit);
        if (add_overflow != 0) {
            self.command_acc = null;
            return;
        }
        self.command_acc = value;
    }

    fn append(self: *OscControl, byte: u8) void {
        if (self.buffer.items.len >= self.policy.max_len) {
            self.overflowed = true;
            return;
        }
        self.buffer.append(self.allocator, byte) catch {
            self.alloc_failed = true;
        };
    }

    fn setCommandPolicy(self: *OscControl, command: u16) void {
        self.policy = self.commandPolicy(command);
    }

    fn commandPolicy(self: *const OscControl, command: u16) CommandPolicy {
        return switch (command) {
            52 => .{ .command = command, .kind = .clipboard, .max_len = self.large_max_len },
            66, 5113, 5522 => .{ .command = command, .kind = .other, .max_len = self.large_max_len },
            0, 1, 2 => .{ .command = command, .kind = .title, .max_len = self.metadata_max_len },
            8 => .{ .command = command, .kind = .hyperlink, .max_len = self.metadata_max_len },
            else => .{ .command = command, .kind = .other, .max_len = self.metadata_max_len },
        };
    }
};

fn bodyState(comptime kind: OscControl.BodyKind) OscControl.OscState {
    return switch (kind) {
        .payload => .payload,
        .raw => .raw,
    };
}

fn bodyEscState(comptime kind: OscControl.BodyKind) OscControl.OscState {
    return switch (kind) {
        .payload => .payload_esc,
        .raw => .raw_esc,
    };
}

fn isDigit(byte: u8) bool {
    return byte >= '0' and byte <= '9';
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
