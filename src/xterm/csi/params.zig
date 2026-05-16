//! CSI parameter normalization.

const std = @import("std");
const events = @import("../../action/vocabulary.zig");

const SemanticEvent = events.SemanticEvent;

pub fn optionalRectArea(params: [16]i32, count: u8) SemanticEvent.OptionalRectArea {
    return .{
        .top = if (count >= 1 and params[0] > 0) paramOrDefault1(params[0]) - 1 else null,
        .left = if (count >= 2 and params[1] > 0) paramOrDefault1(params[1]) - 1 else null,
        .bottom = if (count >= 3 and params[2] > 0) paramOrDefault1(params[2]) - 1 else null,
        .right = if (count >= 4 and params[3] > 0) paramOrDefault1(params[3]) - 1 else null,
    };
}

pub fn rectArea(params: [16]i32, count: u8, start_idx: usize) SemanticEvent.RectArea {
    return .{
        .top = if (count > start_idx) paramOrDefault1(params[start_idx]) - 1 else 0,
        .left = if (count > start_idx + 1) paramOrDefault1(params[start_idx + 1]) - 1 else 0,
        .bottom = if (count > start_idx + 2) paramOrDefault1(params[start_idx + 2]) - 1 else null,
        .right = if (count > start_idx + 3) paramOrDefault1(params[start_idx + 3]) - 1 else null,
    };
}

pub fn attrParams(params: [16]i32, count: u8, start_idx: usize) SemanticEvent.AttrParams {
    var out = [_]u16{0} ** 16;
    var idx: usize = start_idx;
    var dst: usize = 0;
    while (idx < count and dst < out.len) : ({
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

pub fn collectParams(params: [16]i32, count: u8) SemanticEvent.ModeParams {
    var out = [_]u16{0} ** 16;
    const n = @min(count, out.len);
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

pub fn intermediatesLenHas(intermediates: [4]u8, len: u8, needle: u8) bool {
    var idx: usize = 0;
    while (idx < len) : (idx += 1) {
        if (intermediates[idx] == needle) return true;
    }
    return false;
}
