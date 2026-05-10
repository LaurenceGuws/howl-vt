//! Responsibility: own shared OSC terminal color state and xterm color controls.
//! Ownership: OSC color protocol domain owner.
//! Reason: keep non-kitty terminal color state and xterm color operations outside the kitty umbrella.

const std = @import("std");
const grid_owner = @import("grid/grid.zig");

const Grid = grid_owner;

pub const State = struct {
    foreground: Grid.Color = Grid.default_fg,
    background: Grid.Color = Grid.default_bg,
    cursor: ?Grid.Color = null,
    cursor_text: ?Grid.Color = null,
    selection_background: ?Grid.Color = null,
    selection_foreground: ?Grid.Color = null,
    palette: [256]Grid.Color = defaultPalette(),
};

pub const SpecialKey = enum { foreground, background, cursor, cursor_text, selection_background, selection_foreground };

pub fn handleXtermPaletteControl(allocator: std.mem.Allocator, colors: *State, output: *std.ArrayList(u8), encode_buf: []u8, payload: []const u8) void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u8, idx_text, 10) catch continue;
        if (std.mem.eql(u8, value, "?")) {
            const text = std.fmt.bufPrint(encode_buf, "\x1b]4;{d};", .{idx}) catch continue;
            output.appendSlice(allocator, text) catch continue;
            appendColorOsc(allocator, output, colors.palette[idx]);
            output.appendSlice(allocator, "\x1b\\") catch {};
        } else if (parseColor(value)) |color| {
            colors.palette[idx] = color;
        }
    }
}

pub fn handleXtermSpecialColor(allocator: std.mem.Allocator, colors: *State, output: *std.ArrayList(u8), encode_buf: []u8, key: SpecialKey, payload: []const u8) void {
    if (std.mem.eql(u8, payload, "?")) {
        appendXtermSpecialColorReply(allocator, output, encode_buf, colors.*, key);
    } else if (parseColor(payload)) |color| {
        setSpecialColor(colors, key, color);
    }
}

pub fn resetXtermPalette(colors: *State, payload: []const u8) void {
    if (payload.len == 0) {
        colors.palette = buildDefaultPalette();
        return;
    }
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const idx = std.fmt.parseUnsigned(u8, idx_text, 10) catch continue;
        colors.palette[idx] = paletteColor(idx);
    }
}

pub fn parseColor(value: []const u8) ?Grid.Color {
    const color_text = stripAlpha(std.mem.trim(u8, value, " \t\r\n"));
    if (color_text.len == 0) return null;
    if (std.mem.startsWith(u8, color_text, "#")) return parseHashColor(color_text[1..]);
    if (std.mem.startsWith(u8, color_text, "rgb:")) return parseRgbColor(color_text[4..]);
    if (std.ascii.eqlIgnoreCase(color_text, "black")) return .{ .r = 0, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "red")) return .{ .r = 255, .g = 0, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "green")) return .{ .r = 0, .g = 255, .b = 0 };
    if (std.ascii.eqlIgnoreCase(color_text, "blue")) return .{ .r = 0, .g = 0, .b = 255 };
    if (std.ascii.eqlIgnoreCase(color_text, "white")) return .{ .r = 255, .g = 255, .b = 255 };
    return null;
}

pub fn defaultPalette() [256]Grid.Color {
    return buildDefaultPalette();
}

pub fn defaultPaletteColor(idx: u8) Grid.Color {
    return paletteColor(idx);
}

pub fn specialColorKey(key: []const u8) ?SpecialKey {
    if (std.mem.eql(u8, key, "foreground")) return .foreground;
    if (std.mem.eql(u8, key, "background")) return .background;
    if (std.mem.eql(u8, key, "cursor")) return .cursor;
    if (std.mem.eql(u8, key, "cursor_text")) return .cursor_text;
    if (std.mem.eql(u8, key, "selection_background")) return .selection_background;
    if (std.mem.eql(u8, key, "selection_foreground")) return .selection_foreground;
    return null;
}

pub fn isKnownColorKey(key: []const u8) bool {
    if (specialColorKey(key) != null) return true;
    _ = std.fmt.parseUnsigned(u8, key, 10) catch return false;
    return true;
}

pub fn colorForKey(colors: State, key: []const u8) ?Grid.Color {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| return colors.palette[idx] else |_| {}
    if (specialColorKey(key)) |special| return switch (special) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .cursor_text => colors.cursor_text,
        .selection_background => colors.selection_background,
        .selection_foreground => colors.selection_foreground,
    };
    return null;
}

pub fn appendColorOsc(allocator: std.mem.Allocator, output: *std.ArrayList(u8), color: Grid.Color) void {
    var buf: [32]u8 = undefined;
    const text = std.fmt.bufPrint(buf[0..], "rgb:{x:0>2}/{x:0>2}/{x:0>2}", .{ color.r, color.g, color.b }) catch return;
    output.appendSlice(allocator, text) catch {};
}

pub fn setColorKey(colors: *State, key: []const u8, value: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        if (parseColor(value)) |color| colors.palette[idx] = color;
        return;
    } else |_| {}
    if (value.len == 0) {
        setSpecialColorDynamic(colors, key);
    } else if (parseColor(value)) |color| {
        if (specialColorKey(key)) |special| setSpecialColor(colors, special, color);
    }
}

pub fn resetColorKey(colors: *State, key: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        colors.palette[idx] = paletteColor(idx);
        return;
    } else |_| {}
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => colors.foreground = Grid.default_fg,
        .background => colors.background = Grid.default_bg,
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn appendXtermSpecialColorReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, colors: State, key: SpecialKey) void {
    const osc: u8 = switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        else => 10,
    };
    const color = switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor orelse colors.foreground,
        else => colors.foreground,
    };
    const text = std.fmt.bufPrint(encode_buf, "\x1b]{d};", .{osc}) catch return;
    output.appendSlice(allocator, text) catch return;
    appendColorOsc(allocator, output, color);
    output.appendSlice(allocator, "\x1b\\") catch {};
}

fn setSpecialColor(colors: *State, key: SpecialKey, color: Grid.Color) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .cursor_text => colors.cursor_text = color,
        .selection_background => colors.selection_background = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn setSpecialColorDynamic(colors: *State, key: []const u8) void {
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => {},
        .background => {},
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn buildDefaultPalette() [256]Grid.Color {
    @setEvalBranchQuota(4096);
    var palette: [256]Grid.Color = undefined;
    var idx: u16 = 0;
    while (idx < 256) : (idx += 1) palette[idx] = paletteColor(@intCast(idx));
    return palette;
}

fn paletteColor(idx: u8) Grid.Color {
    if (idx < 16) return ansi16Color(idx);
    if (idx < 232) {
        const n = idx - 16;
        const r = cubeComponent(n / 36);
        const g = cubeComponent((n / 6) % 6);
        const b = cubeComponent(n % 6);
        return .{ .r = r, .g = g, .b = b };
    }
    const gray: u8 = 8 + (idx - 232) * 10;
    return .{ .r = gray, .g = gray, .b = gray };
}

fn cubeComponent(v: u8) u8 {
    return if (v == 0) 0 else 55 + v * 40;
}

fn ansi16Color(idx: u8) Grid.Color {
    return switch (idx) {
        0 => .{ .r = 0, .g = 0, .b = 0 },
        1 => .{ .r = 205, .g = 49, .b = 49 },
        2 => .{ .r = 13, .g = 188, .b = 121 },
        3 => .{ .r = 229, .g = 229, .b = 16 },
        4 => .{ .r = 36, .g = 114, .b = 200 },
        5 => .{ .r = 188, .g = 63, .b = 188 },
        6 => .{ .r = 17, .g = 168, .b = 205 },
        7 => .{ .r = 229, .g = 229, .b = 229 },
        8 => .{ .r = 102, .g = 102, .b = 102 },
        9 => .{ .r = 241, .g = 76, .b = 76 },
        10 => .{ .r = 35, .g = 209, .b = 139 },
        11 => .{ .r = 245, .g = 245, .b = 67 },
        12 => .{ .r = 59, .g = 142, .b = 234 },
        13 => .{ .r = 214, .g = 112, .b = 214 },
        14 => .{ .r = 41, .g = 184, .b = 219 },
        else => .{ .r = 255, .g = 255, .b = 255 },
    };
}

fn stripAlpha(value: []const u8) []const u8 {
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return value;
    return value[0..at];
}

fn parseHashColor(hex: []const u8) ?Grid.Color {
    return switch (hex.len) {
        3 => blk: {
            const r = parseHexNibble(hex[0]) orelse return null;
            const g = parseHexNibble(hex[1]) orelse return null;
            const b = parseHexNibble(hex[2]) orelse return null;
            break :blk .{ .r = r << 4, .g = g << 4, .b = b << 4 };
        },
        6 => .{ .r = parseHexByte(hex[0..2]) orelse return null, .g = parseHexByte(hex[2..4]) orelse return null, .b = parseHexByte(hex[4..6]) orelse return null },
        9 => .{ .r = parseHexByte(hex[0..2]) orelse return null, .g = parseHexByte(hex[3..5]) orelse return null, .b = parseHexByte(hex[6..8]) orelse return null },
        12 => .{ .r = parseHexByte(hex[0..2]) orelse return null, .g = parseHexByte(hex[4..6]) orelse return null, .b = parseHexByte(hex[8..10]) orelse return null },
        else => null,
    };
}

fn parseRgbColor(text: []const u8) ?Grid.Color {
    var parts = std.mem.splitScalar(u8, text, '/');
    const r = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const g = parseRgbComponent(parts.next() orelse return null) orelse return null;
    const b = parseRgbComponent(parts.next() orelse return null) orelse return null;
    return .{ .r = r, .g = g, .b = b };
}

fn parseRgbComponent(text: []const u8) ?u8 {
    if (text.len == 0 or text.len > 4) return null;
    const value = std.fmt.parseUnsigned(u16, text, 16) catch return null;
    return switch (text.len) {
        1 => @intCast(value * 17),
        2 => @intCast(value),
        3 => @intCast(value >> 4),
        4 => @intCast(value >> 8),
        else => null,
    };
}

fn parseHexByte(text: []const u8) ?u8 {
    if (text.len != 2) return null;
    return std.fmt.parseUnsigned(u8, text, 16) catch null;
}

fn parseHexNibble(byte: u8) ?u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => null,
    };
}
