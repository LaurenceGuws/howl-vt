const std = @import("std");
const screen_mod = @import("../terminal/screen.zig");
const host_state = @import("../host/state.zig");

const Screen = screen_mod.Screen;
const Grid = Screen;
const Rgb = Screen.Rgb;
const osc_reply_max_bytes = 8;
const color_osc_max_bytes = 16;

pub const TerminalColorState = struct {
    foreground: Rgb = default_fg,
    background: Rgb = default_bg,
    cursor: ?Rgb = null,
    pointer_foreground: ?Rgb = null,
    pointer_background: ?Rgb = null,
    tektronix_foreground: ?Rgb = null,
    tektronix_background: ?Rgb = null,
    tektronix_cursor: ?Rgb = null,
    cursor_text: ?Rgb = null,
    selection_background: ?Rgb = null,
    selection_foreground: ?Rgb = null,
    special_palette: [5]?Rgb = [_]?Rgb{null} ** 5,
    palette: [256]Rgb = defaultPalette(),
};

pub const default_fg = Rgb{ .r = 220, .g = 220, .b = 220 };
pub const default_bg = Rgb{ .r = 24, .g = 25, .b = 33 };

pub const SpecialKey = enum { foreground, background, cursor, cursor_text, selection_background, selection_foreground };
pub const DynamicKey = enum {
    foreground,
    background,
    cursor,
    pointer_foreground,
    pointer_background,
    tektronix_foreground,
    tektronix_background,
    selection_background,
    tektronix_cursor,
    selection_foreground,
};
pub const SpecialPaletteKey = enum(u3) {
    bold = 0,
    underline = 1,
    blink = 2,
    reverse = 3,
    italic = 4,
};

pub fn handleXtermPaletteControl(allocator: std.mem.Allocator, colors: *TerminalColorState, output: *std.ArrayList(u8), encode_buf: []u8, payload: []const u8) host_state.ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u16, idx_text, 10) catch continue;
        if (std.mem.eql(u8, value, "?")) {
            const text = formatOscReply(encode_buf, "\x1b]4;{d};", .{idx});
            const start = host_state.byteCount(output.items);
            errdefer host_state.restorePendingOutput(output, start);
            try host_state.appendOutput(output, allocator, text);
            if (paletteTargetColor(colors.*, idx)) |color| try appendColorOsc(allocator, output, color);
            try host_state.appendOutput(output, allocator, "\x1b\\");
        } else if (parseColor(value)) |color| {
            setPaletteTarget(colors, idx, color);
        }
    }
}

pub fn handleXtermSpecialPaletteControl(allocator: std.mem.Allocator, colors: *TerminalColorState, output: *std.ArrayList(u8), encode_buf: []u8, payload: []const u8) host_state.ApplyError!void {
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const value = parts.next() orelse break;
        const idx = std.fmt.parseUnsigned(u3, idx_text, 10) catch continue;
        const text = formatOscReply(encode_buf, "\x1b]5;{d};", .{idx});
        if (std.mem.eql(u8, value, "?")) {
            const start = host_state.byteCount(output.items);
            errdefer host_state.restorePendingOutput(output, start);
            try host_state.appendOutput(output, allocator, text);
            if (colors.special_palette[idx]) |color| try appendColorOsc(allocator, output, color);
            try host_state.appendOutput(output, allocator, "\x1b\\");
        } else if (parseColor(value)) |color| {
            colors.special_palette[idx] = color;
        }
    }
}

pub fn handleXtermDynamicColor(allocator: std.mem.Allocator, colors: *TerminalColorState, output: *std.ArrayList(u8), encode_buf: []u8, command: u16, payload: []const u8) host_state.ApplyError!void {
    var key = dynamicKeyForCommand(command) orelse return;
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |value| {
        if (std.mem.eql(u8, value, "?")) {
            try appendXtermDynamicColorReply(allocator, output, encode_buf, colors.*, key);
        } else if (parseColor(value)) |color| {
            setDynamicColor(colors, key, color);
        }
        key = nextDynamicKey(key) orelse return;
    }
}

pub fn resetXtermPalette(colors: *TerminalColorState, payload: []const u8) void {
    if (payload.len == 0) {
        colors.palette = buildDefaultPalette();
        return;
    }
    var parts = std.mem.splitScalar(u8, payload, ';');
    while (parts.next()) |idx_text| {
        const idx = std.fmt.parseUnsigned(u16, idx_text, 10) catch continue;
        resetPaletteTarget(colors, idx);
    }
}

pub fn resetXtermDynamicColor(colors: *TerminalColorState, command: u16, payload: []const u8) void {
    if (payload.len != 0) return;
    const key = dynamicKeyForResetCommand(command) orelse return;
    resetDynamicColor(colors, key);
}

pub fn parseColor(value: []const u8) ?Rgb {
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

pub fn defaultPalette() [256]Rgb {
    return buildDefaultPalette();
}

pub fn defaultPaletteColor(idx: u8) Rgb {
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

pub fn colorForKey(colors: TerminalColorState, key: []const u8) ?Rgb {
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

fn paletteTargetColor(colors: TerminalColorState, idx: u16) ?Rgb {
    if (idx < 256) return colors.palette[@intCast(idx)];
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return null;
    return colors.special_palette[special_idx];
}

fn setPaletteTarget(colors: *TerminalColorState, idx: u16, color: Rgb) void {
    if (idx < 256) {
        colors.palette[@intCast(idx)] = color;
        return;
    }
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return;
    colors.special_palette[special_idx] = color;
}

fn resetPaletteTarget(colors: *TerminalColorState, idx: u16) void {
    if (idx < 256) {
        colors.palette[@intCast(idx)] = paletteColor(@intCast(idx));
        return;
    }
    const special_idx = idx - 256;
    if (special_idx >= colors.special_palette.len) return;
    colors.special_palette[special_idx] = null;
}

fn dynamicKeyForCommand(command: u16) ?DynamicKey {
    return switch (command) {
        10 => .foreground,
        11 => .background,
        12 => .cursor,
        13 => .pointer_foreground,
        14 => .pointer_background,
        15 => .tektronix_foreground,
        16 => .tektronix_background,
        17 => .selection_background,
        18 => .tektronix_cursor,
        19 => .selection_foreground,
        else => null,
    };
}

fn dynamicKeyForResetCommand(command: u16) ?DynamicKey {
    return switch (command) {
        110 => .foreground,
        111 => .background,
        112 => .cursor,
        113 => .pointer_foreground,
        114 => .pointer_background,
        115 => .tektronix_foreground,
        116 => .tektronix_background,
        117 => .selection_background,
        118 => .tektronix_cursor,
        119 => .selection_foreground,
        else => null,
    };
}

fn nextDynamicKey(key: DynamicKey) ?DynamicKey {
    return switch (key) {
        .foreground => .background,
        .background => .cursor,
        .cursor => .pointer_foreground,
        .pointer_foreground => .pointer_background,
        .pointer_background => .tektronix_foreground,
        .tektronix_foreground => .tektronix_background,
        .tektronix_background => .selection_background,
        .selection_background => .tektronix_cursor,
        .tektronix_cursor => .selection_foreground,
        .selection_foreground => null,
    };
}

fn dynamicCommandForKey(key: DynamicKey) u16 {
    return switch (key) {
        .foreground => 10,
        .background => 11,
        .cursor => 12,
        .pointer_foreground => 13,
        .pointer_background => 14,
        .tektronix_foreground => 15,
        .tektronix_background => 16,
        .selection_background => 17,
        .tektronix_cursor => 18,
        .selection_foreground => 19,
    };
}

fn dynamicColor(colors: TerminalColorState, key: DynamicKey) ?Rgb {
    return switch (key) {
        .foreground => colors.foreground,
        .background => colors.background,
        .cursor => colors.cursor,
        .pointer_foreground => colors.pointer_foreground,
        .pointer_background => colors.pointer_background,
        .tektronix_foreground => colors.tektronix_foreground,
        .tektronix_background => colors.tektronix_background,
        .selection_background => colors.selection_background,
        .tektronix_cursor => colors.tektronix_cursor,
        .selection_foreground => colors.selection_foreground,
    };
}

fn setDynamicColor(colors: *TerminalColorState, key: DynamicKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .pointer_foreground => colors.pointer_foreground = color,
        .pointer_background => colors.pointer_background = color,
        .tektronix_foreground => colors.tektronix_foreground = color,
        .tektronix_background => colors.tektronix_background = color,
        .selection_background => colors.selection_background = color,
        .tektronix_cursor => colors.tektronix_cursor = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn resetDynamicColor(colors: *TerminalColorState, key: DynamicKey) void {
    switch (key) {
        .foreground => colors.foreground = default_fg,
        .background => colors.background = default_bg,
        .cursor => colors.cursor = null,
        .pointer_foreground => colors.pointer_foreground = null,
        .pointer_background => colors.pointer_background = null,
        .tektronix_foreground => colors.tektronix_foreground = null,
        .tektronix_background => colors.tektronix_background = null,
        .selection_background => colors.selection_background = null,
        .tektronix_cursor => colors.tektronix_cursor = null,
        .selection_foreground => colors.selection_foreground = null,
    }
}

pub fn appendColorOsc(allocator: std.mem.Allocator, output: *std.ArrayList(u8), color: Rgb) host_state.ApplyError!void {
    var buf: [32]u8 = undefined;
    const text = formatColorOsc(buf[0..], color);
    try host_state.appendOutput(output, allocator, text);
}

pub fn setColorKey(colors: *TerminalColorState, key: []const u8, value: []const u8) void {
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

pub fn resetColorKey(colors: *TerminalColorState, key: []const u8) void {
    if (std.fmt.parseUnsigned(u8, key, 10)) |idx| {
        colors.palette[idx] = paletteColor(idx);
        return;
    } else |_| {}
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => colors.foreground = default_fg,
        .background => colors.background = default_bg,
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn appendXtermSpecialColorReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, colors: TerminalColorState, key: SpecialKey) host_state.ApplyError!void {
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
    const text = formatOscReply(encode_buf, "\x1b]{d};", .{osc});
    const start = host_state.byteCount(output.items);
    errdefer host_state.restorePendingOutput(output, start);
    try host_state.appendOutput(output, allocator, text);
    try appendColorOsc(allocator, output, color);
    try host_state.appendOutput(output, allocator, "\x1b\\");
}

fn appendXtermDynamicColorReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, colors: TerminalColorState, key: DynamicKey) host_state.ApplyError!void {
    const text = formatOscReply(encode_buf, "\x1b]{d};", .{dynamicCommandForKey(key)});
    const start = host_state.byteCount(output.items);
    errdefer host_state.restorePendingOutput(output, start);
    try host_state.appendOutput(output, allocator, text);
    if (dynamicColor(colors, key)) |color| try appendColorOsc(allocator, output, color);
    try host_state.appendOutput(output, allocator, "\x1b\\");
}

fn setSpecialColor(colors: *TerminalColorState, key: SpecialKey, color: Rgb) void {
    switch (key) {
        .foreground => colors.foreground = color,
        .background => colors.background = color,
        .cursor => colors.cursor = color,
        .cursor_text => colors.cursor_text = color,
        .selection_background => colors.selection_background = color,
        .selection_foreground => colors.selection_foreground = color,
    }
}

fn setSpecialColorDynamic(colors: *TerminalColorState, key: []const u8) void {
    if (specialColorKey(key)) |special| switch (special) {
        .foreground => {},
        .background => {},
        .cursor => colors.cursor = null,
        .cursor_text => colors.cursor_text = null,
        .selection_background => colors.selection_background = null,
        .selection_foreground => colors.selection_foreground = null,
    };
}

fn formatOscReply(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= osc_reply_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}

fn formatColorOsc(buf: []u8, color: Rgb) []const u8 {
    std.debug.assert(buf.len >= color_osc_max_bytes);
    return std.fmt.bufPrint(buf, "rgb:{x:0>2}/{x:0>2}/{x:0>2}", .{ color.r, color.g, color.b }) catch unreachable;
}

fn buildDefaultPalette() [256]Rgb {
    @setEvalBranchQuota(4096);
    var palette: [256]Rgb = undefined;
    var idx: u16 = 0;
    while (idx < 256) : (idx += 1) palette[idx] = paletteColor(@intCast(idx));
    return palette;
}

fn paletteColor(idx: u8) Rgb {
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

fn ansi16Color(idx: u8) Rgb {
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

fn parseHashColor(hex: []const u8) ?Rgb {
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

fn parseRgbColor(text: []const u8) ?Rgb {
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
