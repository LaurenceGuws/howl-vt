const std = @import("std");
const events = @import("../../action/vocabulary.zig");
const parser_mod = @import("../../parser.zig");

const SemanticEvent = events.SemanticEvent;
const csi_max_params = parser_mod.max_params;

fn count32(items: anytype) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

pub fn optionalRectArea(params: []const i32) SemanticEvent.OptionalRectArea {
    return .{
        .top = if (params.len >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (params.len >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (params.len >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (params.len >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

pub fn rectArea(params: []const i32, start_idx: u8) SemanticEvent.RectArea {
    const start = @as(u32, start_idx);
    const param_len = count32(params);
    return .{
        .top = if (param_len > start) paramOrDefault1(params[@intCast(start)]) - 1 else 0,
        .left = if (param_len > start + 1) paramOrDefault1(params[@intCast(start + 1)]) - 1 else 0,
        .bottom = if (param_len > start + 2) paramOrDefault1(params[@intCast(start + 2)]) - 1 else null,
        .right = if (param_len > start + 3) paramOrDefault1(params[@intCast(start + 3)]) - 1 else null,
    };
}

pub fn attrParams(params: []const i32, start_idx: u8) SemanticEvent.AttrParams {
    var out = [_]u16{0} ** csi_max_params;
    const param_len = count32(params);
    var idx: u8 = start_idx;
    var dst: u8 = 0;
    while (idx < param_len and dst < csi_max_params) : ({
        idx += 1;
        dst += 1;
    }) {
        out[@intCast(dst)] = paramOrDefault0(params[@intCast(idx)]);
    }
    return .{ .params = out, .param_count = @intCast(dst) };
}

pub fn isValidRectFillChar(ch: u16) bool {
    return (ch >= 32 and ch <= 126) or (ch >= 160 and ch <= 255);
}

pub fn paramAtOrDefault1(params: []const i32, idx: u8) u16 {
    return if (count32(params) > idx) paramOrDefault1(params[idx]) else 1;
}

pub fn paramAtOrDefault0(params: []const i32, idx: u8) u16 {
    return if (count32(params) > idx) paramOrDefault0(params[idx]) else 0;
}

pub fn eraseMode(v: i32) u2 {
    return switch (v) {
        1 => 1,
        2 => 2,
        3 => 3,
        else => 0,
    };
}

pub fn cursorStyle(param: u16) SemanticEvent.CursorStyle {
    return switch (param) {
        2 => .{ .shape = .block, .blink = false },
        3 => .{ .shape = .underline, .blink = true },
        4 => .{ .shape = .underline, .blink = false },
        5 => .{ .shape = .bar, .blink = true },
        6 => .{ .shape = .bar, .blink = false },
        else => .{ .shape = .block, .blink = true },
    };
}

pub fn collectParams(params: []const i32) SemanticEvent.ModeParams {
    var out = [_]u16{0} ** csi_max_params;
    const n = @min(count32(params), csi_max_params);
    var idx: u8 = 0;
    while (idx < n) : (idx += 1) out[@intCast(idx)] = paramOrDefault0(params[@intCast(idx)]);
    return .{ .params = out, .param_count = @intCast(n) };
}

pub fn paramOrDefault1(v: i32) u16 {
    if (v <= 0) return 1;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

pub fn paramOrDefault0(v: i32) u16 {
    if (v <= 0) return 0;
    if (v > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(v);
}

pub fn intermediatesHas(intermediates: []const u8, needle: u8) bool {
    return std.mem.indexOfScalar(u8, intermediates, needle) != null;
}
