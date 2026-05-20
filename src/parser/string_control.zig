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

    pub const Snapshot = struct {
        command: ?u16,
        kind: OscKind,
        payload: []const u8,
    };

    allocator: std.mem.Allocator,
    state: OscState = .idle,
    prefix: PrefixState = .start,
    buffer: std.ArrayList(u8),
    metadata_max_len: usize,
    large_max_len: usize,
    policy: CommandPolicy,
    alloc_failed: bool = false,
    overflowed: bool = false,

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

    const PrefixState = enum {
        start,
        c0,
        c1,
        c2,
        c3,
        c4,
        c5,
        c6,
        c7,
        c8,
        c9,
        c10,
        c11,
        c12,
        c13,
        c14,
        c15,
        c16,
        c17,
        c18,
        c19,
        c21,
        c22,
        c30,
        c51,
        c52,
        c55,
        c66,
        c77,
        c99,
        c104,
        c110,
        c111,
        c112,
        c113,
        c114,
        c115,
        c116,
        c117,
        c118,
        c119,
        c133,
        c300,
        c301,
        c511,
        c552,
        c777,
        c1337,
        c3008,
        c3000,
        c30001,
        c3010,
        c30101,
        c5113,
        c5522,
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
        self.prefix = .start;
        self.alloc_failed = false;
        self.overflowed = false;
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

    pub fn snapshot(self: *const OscControl) Snapshot {
        return .{
            .command = self.policy.command,
            .kind = self.policy.kind,
            .payload = self.buffer.items,
        };
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
        if (self.advancePrefix(byte)) |next| {
            self.append(byte);
            self.prefix = next;
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
        if (!self.promoteRecognizedPrefix(.idle)) {
            self.policy = .{ .command = null, .kind = .title, .max_len = self.metadata_max_len };
        }
        self.prefix = .start;
        self.state = .idle;
    }

    fn finishRaw(self: *OscControl) void {
        self.policy.command = null;
        self.prefix = .start;
        self.state = .idle;
    }

    fn finishBody(self: *OscControl, comptime kind: BodyKind) void {
        switch (kind) {
            .payload => self.state = .idle,
            .raw => self.finishRaw(),
        }
    }

    fn enterPayloadFromPrefix(self: *OscControl) bool {
        if (self.promoteRecognizedPrefix(.payload)) return true;
        self.enterRawFromPrefix(';', true);
        return false;
    }

    fn enterRawFromPrefix(self: *OscControl, byte: u8, has_separator: bool) void {
        self.policy = .{
            .command = null,
            .kind = if (has_separator) .other else .title,
            .max_len = self.metadata_max_len,
        };
        self.prefix = .start;
        self.state = .raw;
        if (byte == ';') self.policy.kind = .other;
        self.append(byte);
    }

    fn promoteRecognizedPrefix(self: *OscControl, next_state: OscState) bool {
        const command = self.prefixCommand() orelse return false;
        self.setCommandPolicy(command);
        self.buffer.clearRetainingCapacity();
        self.prefix = .start;
        self.state = next_state;
        return true;
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

    fn advancePrefix(self: *const OscControl, byte: u8) ?PrefixState {
        return switch (self.prefix) {
            .start => switch (byte) {
                '0' => .c0,
                '1' => .c1,
                '2' => .c2,
                '3' => .c3,
                '4' => .c4,
                '5' => .c5,
                '6' => .c6,
                '7' => .c7,
                '8' => .c8,
                '9' => .c9,
                else => null,
            },
            .c1 => switch (byte) {
                '0' => .c10,
                '1' => .c11,
                '2' => .c12,
                '3' => .c13,
                '4' => .c14,
                '5' => .c15,
                '6' => .c16,
                '7' => .c17,
                '8' => .c18,
                '9' => .c19,
                else => null,
            },
            .c2 => switch (byte) {
                '1' => .c21,
                '2' => .c22,
                else => null,
            },
            .c3 => switch (byte) {
                '0' => .c30,
                else => null,
            },
            .c5 => switch (byte) {
                '1' => .c51,
                '2' => .c52,
                '5' => .c55,
                else => null,
            },
            .c6 => switch (byte) {
                '6' => .c66,
                else => null,
            },
            .c7 => switch (byte) {
                '7' => .c77,
                else => null,
            },
            .c9 => switch (byte) {
                '9' => .c99,
                else => null,
            },
            .c10 => switch (byte) {
                '4' => .c104,
                else => null,
            },
            .c11 => switch (byte) {
                '0' => .c110,
                '1' => .c111,
                '2' => .c112,
                '3' => .c113,
                '4' => .c114,
                '5' => .c115,
                '6' => .c116,
                '7' => .c117,
                '8' => .c118,
                '9' => .c119,
                else => null,
            },
            .c13 => switch (byte) {
                '3' => .c133,
                else => null,
            },
            .c30 => switch (byte) {
                '0' => .c300,
                '1' => .c301,
                else => null,
            },
            .c51 => switch (byte) {
                '1' => .c511,
                else => null,
            },
            .c55 => switch (byte) {
                '2' => .c552,
                else => null,
            },
            .c77 => switch (byte) {
                '7' => .c777,
                else => null,
            },
            .c133 => switch (byte) {
                '7' => .c1337,
                else => null,
            },
            .c300 => switch (byte) {
                '0' => .c3000,
                '8' => .c3008,
                else => null,
            },
            .c301 => switch (byte) {
                '0' => .c3010,
                else => null,
            },
            .c511 => switch (byte) {
                '3' => .c5113,
                else => null,
            },
            .c552 => switch (byte) {
                '2' => .c5522,
                else => null,
            },
            .c3000 => switch (byte) {
                '1' => .c30001,
                else => null,
            },
            .c3010 => switch (byte) {
                '1' => .c30101,
                else => null,
            },
            else => null,
        };
    }

    fn prefixCommand(self: *const OscControl) ?u16 {
        return switch (self.prefix) {
            .c0 => 0,
            .c1 => 1,
            .c2 => 2,
            .c4 => 4,
            .c5 => 5,
            .c7 => 7,
            .c8 => 8,
            .c9 => 9,
            .c10 => 10,
            .c11 => 11,
            .c12 => 12,
            .c13 => 13,
            .c14 => 14,
            .c15 => 15,
            .c16 => 16,
            .c17 => 17,
            .c18 => 18,
            .c19 => 19,
            .c21 => 21,
            .c22 => 22,
            .c52 => 52,
            .c66 => 66,
            .c99 => 99,
            .c104 => 104,
            .c110 => 110,
            .c111 => 111,
            .c112 => 112,
            .c113 => 113,
            .c114 => 114,
            .c115 => 115,
            .c116 => 116,
            .c117 => 117,
            .c118 => 118,
            .c119 => 119,
            .c133 => 133,
            .c777 => 777,
            .c1337 => 1337,
            .c3008 => 3008,
            .c30001 => 30001,
            .c30101 => 30101,
            .c5113 => 5113,
            .c5522 => 5522,
            else => null,
        };
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
    const snapshot = osc.snapshot();
    try std.testing.expectEqual(@as(?u16, 0), snapshot.command);
    try std.testing.expectEqual(OscKind.title, snapshot.kind);
    try std.testing.expectEqualStrings("hell", snapshot.payload);
    try std.testing.expectEqual(error.StringControlLimit, osc.takeFailure().?);
}

test "osc control: clipboard payload uses large limit" {
    var osc = try OscControl.init(std.testing.allocator, 16, 4, 32);
    defer osc.deinit();
    osc.start();
    for ("52;c;abcdefgh") |byte| _ = osc.feed(byte);
    _ = osc.feed(0x07);
    const snapshot = osc.snapshot();
    try std.testing.expectEqual(@as(?u16, 52), snapshot.command);
    try std.testing.expectEqual(OscKind.clipboard, snapshot.kind);
    try std.testing.expectEqualStrings("c;abcdefgh", snapshot.payload);
    try std.testing.expectEqual(@as(?(error{ OutOfMemory, StringControlLimit }), null), osc.takeFailure());
}
