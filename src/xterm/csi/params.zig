//! CSI parameter normalization.

const std = @import("std");
const events = @import("../../action/vocabulary.zig");
const parser_mod = @import("../../parser.zig");

const SemanticEvent = events.SemanticEvent;
const csi_max_params = parser_mod.max_params;

pub fn optionalRectArea(params: []const i32) SemanticEvent.OptionalRectArea {
    return .{
        .top = if (params.len >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (params.len >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (params.len >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (params.len >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

pub fn rectArea(params: []const i32, start_idx: u8) SemanticEvent.RectArea {
    const start: usize = start_idx;
    return .{
        .top = if (params.len > start) paramOrDefault1(params[start]) - 1 else 0,
        .left = if (params.len > start + 1) paramOrDefault1(params[start + 1]) - 1 else 0,
        .bottom = if (params.len > start + 2) paramOrDefault1(params[start + 2]) - 1 else null,
        .right = if (params.len > start + 3) paramOrDefault1(params[start + 3]) - 1 else null,
    };
}

pub fn attrParams(params: []const i32, start_idx: u8) SemanticEvent.AttrParams {
    var out = [_]u16{0} ** csi_max_params;
    var idx: usize = start_idx;
    var dst: usize = 0;
    while (idx < params.len and dst < out.len) : ({
        idx += 1;
        dst += 1;
    }) {
        out[dst] = paramOrDefault0(params[idx]);
    }
    return .{ .params = out, .param_count = @intCast(dst) };
}

pub fn isValidRectFillChar(ch: u16) bool {
    return (ch >= 32 and ch <= 126) or (ch >= 160 and ch <= 255);
}

pub fn paramAtOrDefault1(params: []const i32, idx: u8) u16 {
    const index: usize = idx;
    return if (index < params.len) paramOrDefault1(params[index]) else 1;
}

pub fn paramAtOrDefault0(params: []const i32, idx: u8) u16 {
    const index: usize = idx;
    return if (index < params.len) paramOrDefault0(params[index]) else 0;
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
    const n = @min(params.len, out.len);
    var idx: usize = 0;
    while (idx < n) : (idx += 1) out[idx] = paramOrDefault0(params[idx]);
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
