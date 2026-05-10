//! Parser-level CSI syntax data.

/// Maximum supported CSI parameter count.
pub const max_params: usize = 16;

/// Maximum supported CSI intermediate count.
pub const max_intermediates: usize = 4;

/// Parsed CSI action record.
pub const CsiAction = struct {
    final: u8,
    params: [max_params]i32,
    separators: [max_params]u8,
    count: u8,
    leader: u8,
    private: bool,
    intermediates: [max_intermediates]u8,
    intermediates_len: u8,
};

/// Incremental CSI parser state.
pub const CsiParser = struct {
    params: [max_params]i32 = [_]i32{0} ** max_params,
    separators: [max_params]u8 = [_]u8{0} ** max_params,
    count: u8 = 0,
    leader: u8 = 0,
    private: bool = false,
    intermediates: [max_intermediates]u8 = [_]u8{0} ** max_intermediates,
    intermediates_len: u8 = 0,
    in_param: bool = false,

    /// Reset parser state to defaults.
    pub fn reset(self: *CsiParser) void {
        self.params[0] = 0;
        self.count = 0;
        self.leader = 0;
        self.private = false;
        self.intermediates_len = 0;
        self.in_param = false;
    }

    /// Feed one byte and emit a CSI action when complete.
    pub fn feed(self: *CsiParser, byte: u8) ?CsiAction {
        // Final byte is in 0x40..0x7E.
        if (byte >= 0x40 and byte <= 0x7E) {
            var final_count = self.count;
            if (self.in_param) final_count += 1;
            const action = CsiAction{
                .final = byte,
                .params = self.params,
                .separators = self.separators,
                .count = final_count,
                .leader = self.leader,
                .private = self.private,
                .intermediates = self.intermediates,
                .intermediates_len = self.intermediates_len,
            };
            self.reset();
            return action;
        }

        if (byte == '<' or byte == '>' or byte == '=' or byte == '?') {
            if (self.leader == 0) {
                self.leader = byte;
            }
            if (byte == '?') {
                self.private = true;
            }
            return null;
        }

        if (byte == ';' or byte == ':') {
            if (self.count < self.params.len) {
                self.count += 1;
                if (self.count < self.params.len) {
                    self.params[self.count] = 0;
                    self.separators[self.count] = byte;
                }
            }
            self.in_param = false;
            return null;
        }

        if (byte >= '0' and byte <= '9') {
            const digit: i32 = @intCast(byte - '0');
            if (self.count >= self.params.len) return null;
            if (!self.in_param) {
                self.params[self.count] = digit;
                self.in_param = true;
            } else {
                self.params[self.count] = self.params[self.count] * 10 + digit;
            }
            return null;
        }

        if (byte >= 0x20 and byte <= 0x2F) {
            // Intermediate bytes are in 0x20..0x2F.
            if (self.intermediates_len < self.intermediates.len) {
                self.intermediates[self.intermediates_len] = byte;
                self.intermediates_len += 1;
            }
            return null;
        }

        // Ignore unsupported bytes in CSI payload.
        return null;
    }
};

const std = @import("std");

fn feedCsiBytes(bytes: []const u8) !CsiAction {
    var parser = CsiParser{};
    for (bytes) |b| {
        if (parser.feed(b)) |action| return action;
    }
    return error.NoAction;
}

test "CSI parser captures ansi DECRQM intermediate $" {
    const action = try feedCsiBytes("20$p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, 0), action.leader);
    try std.testing.expect(!action.private);
    try std.testing.expectEqual(@as(u8, 1), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), action.intermediates[0]);
    try std.testing.expectEqual(@as(i32, 20), action.params[0]);
}

test "CSI parser captures dec private DECRQM intermediate $" {
    const action = try feedCsiBytes("?1004$p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, '?'), action.leader);
    try std.testing.expect(action.private);
    try std.testing.expectEqual(@as(u8, 1), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '$'), action.intermediates[0]);
    try std.testing.expectEqual(@as(i32, 1004), action.params[0]);
}

test "CSI parser captures DECSTR intermediate !" {
    const action = try feedCsiBytes("!p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, 0), action.leader);
    try std.testing.expect(!action.private);
    try std.testing.expectEqual(@as(u8, 1), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '!'), action.intermediates[0]);
}

test "CSI parser preserves multiple intermediate bytes in order" {
    const action = try feedCsiBytes("#!p");
    try std.testing.expectEqual(@as(u8, 'p'), action.final);
    try std.testing.expectEqual(@as(u8, 2), action.intermediates_len);
    try std.testing.expectEqual(@as(u8, '#'), action.intermediates[0]);
    try std.testing.expectEqual(@as(u8, '!'), action.intermediates[1]);
}

test "CSI parser: basic ANSI color sequence (31m = red)" {
    var parser = CsiParser{};
    var action: ?CsiAction = null;
    for ("31m") |byte| action = parser.feed(byte);
    try std.testing.expectEqual(@as(u8, 'm'), action.?.final);
    try std.testing.expectEqual(@as(i32, 31), action.?.params[0]);
    try std.testing.expectEqual(@as(u8, 1), action.?.count);
}

test "CSI parser: multi-param sequence (1;31;40m)" {
    var parser = CsiParser{};
    var action: ?CsiAction = null;
    for ("1;31;40m") |byte| action = parser.feed(byte);
    try std.testing.expectEqual(@as(u8, 'm'), action.?.final);
    try std.testing.expectEqual(@as(i32, 1), action.?.params[0]);
    try std.testing.expectEqual(@as(i32, 31), action.?.params[1]);
    try std.testing.expectEqual(@as(i32, 40), action.?.params[2]);
    try std.testing.expectEqual(@as(u8, 3), action.?.count);
}

test "CSI parser preserves colon subparameter separators" {
    const action = try feedCsiBytes("4:3m");
    try std.testing.expectEqual(@as(u8, 'm'), action.final);
    try std.testing.expectEqual(@as(u8, 2), action.count);
    try std.testing.expectEqual(@as(i32, 4), action.params[0]);
    try std.testing.expectEqual(@as(i32, 3), action.params[1]);
    try std.testing.expectEqual(@as(u8, ':'), action.separators[1]);
}

test "CSI parser: empty params stay defaulted after reset" {
    var parser = CsiParser{};
    _ = parser.feed('9');
    _ = parser.feed('9');
    _ = parser.feed('m');

    var action: ?CsiAction = null;
    for (";H") |byte| action = parser.feed(byte);
    try std.testing.expectEqual(@as(u8, 'H'), action.?.final);
    try std.testing.expectEqual(@as(u8, 1), action.?.count);
    try std.testing.expectEqual(@as(i32, 0), action.?.params[0]);
}

test "CSI parser: cursor position query (6n)" {
    var parser = CsiParser{};
    var action: ?CsiAction = null;
    for ("6n") |byte| action = parser.feed(byte);
    try std.testing.expectEqual(@as(u8, 'n'), action.?.final);
}

test "CSI parser: private mode (?25h = show cursor)" {
    var parser = CsiParser{};
    var action: ?CsiAction = null;
    for ("?25h") |byte| action = parser.feed(byte);
    try std.testing.expectEqual(@as(u8, 'h'), action.?.final);
    try std.testing.expect(action.?.private);
    try std.testing.expectEqual(@as(u8, '?'), action.?.leader);
    try std.testing.expectEqual(@as(i32, 25), action.?.params[0]);
}
