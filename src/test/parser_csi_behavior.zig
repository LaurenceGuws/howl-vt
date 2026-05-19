const std = @import("std");
const parser_mod = @import("../parser.zig");
const parser_flow = @import("../parser/flow.zig");

const CsiAction = parser_mod.CsiAction;

fn feedCsiBytes(bytes: []const u8) !CsiAction {
    const gpa = std.testing.allocator;
    var parser = try parser_mod.Parser.init(gpa);
    defer parser.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var actions = try std.ArrayList(parser_mod.Action).initCapacity(gpa, 8);
    defer actions.deinit(gpa);

    try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(0x1b));
    try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next('['));
    for (bytes) |byte| {
        try parser_flow.appendOwnedPhases(gpa, arena.allocator(), &actions, parser.next(byte));
    }

    for (actions.items) |action| {
        if (action == .csi_dispatch) return action.csi_dispatch;
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
    const action = try feedCsiBytes("31m");
    try std.testing.expectEqual(@as(u8, 'm'), action.final);
    try std.testing.expectEqual(@as(i32, 31), action.params[0]);
    try std.testing.expectEqual(@as(u8, 1), action.count);
}

test "CSI parser: multi-param sequence (1;31;40m)" {
    const action = try feedCsiBytes("1;31;40m");
    try std.testing.expectEqual(@as(u8, 'm'), action.final);
    try std.testing.expectEqual(@as(i32, 1), action.params[0]);
    try std.testing.expectEqual(@as(i32, 31), action.params[1]);
    try std.testing.expectEqual(@as(i32, 40), action.params[2]);
    try std.testing.expectEqual(@as(u8, 3), action.count);
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
    _ = try feedCsiBytes("99m");
    const action = try feedCsiBytes(";H");
    try std.testing.expectEqual(@as(u8, 'H'), action.final);
    try std.testing.expectEqual(@as(u8, 1), action.count);
    try std.testing.expectEqual(@as(i32, 0), action.params[0]);
}

test "CSI parser: cursor position query (6n)" {
    const action = try feedCsiBytes("6n");
    try std.testing.expectEqual(@as(u8, 'n'), action.final);
}

test "CSI parser: private mode (?25h = show cursor)" {
    const action = try feedCsiBytes("?25h");
    try std.testing.expectEqual(@as(u8, 'h'), action.final);
    try std.testing.expect(action.private);
    try std.testing.expectEqual(@as(u8, '?'), action.leader);
    try std.testing.expectEqual(@as(i32, 25), action.params[0]);
}
