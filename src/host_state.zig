const std = @import("std");
const locator = @import("locator.zig");
const osc_color = @import("osc_color.zig");
const action_vocabulary = @import("vocabulary.zig");
const osc = @import("osc.zig");
const parser = @import("parser.zig");

const LocatorNs = locator;
const OscColorNs = osc_color;

pub const ClipboardRequest = struct {
    raw: []u8,
};

pub const CopyIntoResult = union(enum) {
    copied: u64,
    short: u64,
};

pub const ClipboardDrainResult = union(enum) {
    none,
    copied: u64,
    short: u64,
    failed,
};

pub const ApplyError = error{
    OutOfMemory,
    ConsequenceLimit,
};

pub const pending_output_max_bytes: u32 = parser.max_large_osc_control_bytes;
pub const retained_payload_max_bytes: u32 = parser.max_large_osc_control_bytes;
pub const retained_metadata_max_bytes: u32 = parser.max_metadata_control_bytes;
pub const title_max_bytes: u32 = 1024;
pub const hyperlink_target_max_count: u32 = 4096;

comptime {
    std.debug.assert(pending_output_max_bytes == parser.max_large_osc_control_bytes);
    std.debug.assert(retained_payload_max_bytes == parser.max_large_osc_control_bytes);
    std.debug.assert(retained_metadata_max_bytes == parser.max_metadata_control_bytes);
    std.debug.assert(title_max_bytes <= retained_metadata_max_bytes);
    std.debug.assert(hyperlink_target_max_count > 0);
}

pub fn byteCount(bytes: []const u8) u32 {
    std.debug.assert(bytes.len <= std.math.maxInt(u32));
    return @intCast(bytes.len);
}

fn hyperlinkCount(items: []const []u8) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

pub const State = struct {
    // Host consequence retention is heap-backed today, but every retained path
    // is bounded by this file's product capacity constants before allocation.
    pub const DcsPayloadOwned = struct {
        kind: action_vocabulary.DcsPayloadKind,
        payload: []u8,
    };

    colors: OscColorNs.TerminalColorState = .{},
    pending_output: std.ArrayList(u8),
    hyperlink_targets: std.ArrayList([]u8),
    pending_clipboard: ?ClipboardRequest = null,
    current_title: ?[]u8 = null,
    locator: LocatorNs.Locator = .{},
    media_copy_request: ?u16 = null,
    dcs_payload: ?DcsPayloadOwned = null,
    legacy_control: ?action_vocabulary.LegacyControlKind = null,

    pub fn init() State {
        return .{
            .pending_output = std.ArrayList(u8).empty,
            .hyperlink_targets = std.ArrayList([]u8).empty,
        };
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        for (self.hyperlink_targets.items) |uri| allocator.free(uri);
        self.hyperlink_targets.deinit(allocator);
        if (self.pending_clipboard) |req| allocator.free(req.raw);
        if (self.current_title) |title| allocator.free(title);
        if (self.dcs_payload) |payload| allocator.free(payload.payload);
        self.pending_output.deinit(allocator);
    }

    pub fn resetTerminalState(self: *State) void {
        self.locator = .{};
    }
};

pub fn pendingOutput(vt: anytype) []const u8 {
    return vt.host.pending_output.items;
}

pub fn appendPendingOutput(vt: anytype, bytes: []const u8) ApplyError!void {
    try appendOutput(&vt.host.pending_output, vt.allocator, bytes);
}

pub fn appendOutput(output: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: []const u8) ApplyError!void {
    try ensureAppendBound(byteCount(output.items), byteCount(bytes), pending_output_max_bytes);
    try output.appendSlice(allocator, bytes);
}

pub fn replaceOwned(allocator: std.mem.Allocator, current: *?[]u8, next: []const u8, max_len: u32) ApplyError![]const u8 {
    try ensureRetainedBound(byteCount(next), max_len);
    const owned = try allocator.dupe(u8, next);
    if (current.*) |old| allocator.free(old);
    current.* = owned;
    return owned;
}

pub fn replaceClipboard(vt: anytype, payload: []const u8) ApplyError!void {
    try ensureRetainedBound(byteCount(payload), retained_payload_max_bytes);
    const owned = try vt.allocator.dupe(u8, payload);
    if (vt.host.pending_clipboard) |req| vt.allocator.free(req.raw);
    vt.host.pending_clipboard = .{ .raw = owned };
}

pub fn replaceDcsPayload(vt: anytype, payload: action_vocabulary.DcsPayload) ApplyError!void {
    try ensureRetainedBound(byteCount(payload.payload), retained_payload_max_bytes);
    const owned = try vt.allocator.dupe(u8, payload.payload);
    if (vt.host.dcs_payload) |old| vt.allocator.free(old.payload);
    vt.host.dcs_payload = .{ .kind = payload.kind, .payload = owned };
}

pub fn internHyperlink(vt: anytype, uri: []const u8) ApplyError!u32 {
    for (vt.host.hyperlink_targets.items, 0..) |existing, idx| {
        if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
    }
    try ensureRetainedBound(byteCount(uri), retained_metadata_max_bytes);
    if (hyperlinkCount(vt.host.hyperlink_targets.items) >= hyperlink_target_max_count) {
        return error.ConsequenceLimit;
    }
    const owned = try vt.allocator.dupe(u8, uri);
    errdefer vt.allocator.free(owned);
    try vt.host.hyperlink_targets.append(vt.allocator, owned);
    return hyperlinkCount(vt.host.hyperlink_targets.items);
}

pub fn restorePendingOutput(output: *std.ArrayList(u8), len: u32) void {
    std.debug.assert(len <= byteCount(output.items));
    output.items.len = len;
}

pub fn copyPendingOutputInto(vt: anytype, out: []u8) CopyIntoResult {
    const pending = pendingOutput(vt);
    if (out.len < pending.len) return .{ .short = @intCast(pending.len) };
    if (pending.len != 0) @memcpy(out[0..pending.len], pending);
    return .{ .copied = @intCast(pending.len) };
}

pub fn clearPendingOutput(vt: anytype) void {
    vt.host.pending_output.clearRetainingCapacity();
}

pub fn hyperlinkUriForId(vt: anytype, link_id: u32) ?[]const u8 {
    if (link_id == 0) return null;
    const idx = link_id - 1;
    if (idx >= vt.host.hyperlink_targets.items.len) return null;
    return vt.host.hyperlink_targets.items[idx];
}

fn ensureAppendBound(current_len: u32, append_len: u32, max_len: u32) ApplyError!void {
    const next_len = std.math.add(u32, current_len, append_len) catch return error.ConsequenceLimit;
    try ensureRetainedBound(next_len, max_len);
}

fn ensureRetainedBound(len: u32, max_len: u32) ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}

pub fn pendingClipboardSet(vt: anytype) ?[]const u8 {
    if (vt.host.pending_clipboard) |req| return req.raw;
    return null;
}

pub fn clearPendingClipboardSet(vt: anytype) void {
    if (vt.host.pending_clipboard) |req| vt.allocator.free(req.raw);
    vt.host.pending_clipboard = null;
}

pub fn drainPendingClipboardSet(vt: anytype, allocator: std.mem.Allocator) !?[]u8 {
    const pending = pendingClipboardSet(vt) orelse return null;
    defer clearPendingClipboardSet(vt);
    return osc.decodeClipboardSet(allocator, pending) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
}

pub fn drainPendingClipboardSetInto(vt: anytype, out: []u8) ClipboardDrainResult {
    const pending = pendingClipboardSet(vt) orelse return .none;
    const decoded_len = osc.decodedClipboardSetSize(pending) catch return .failed;
    if (out.len < decoded_len) return .{ .short = decoded_len };
    const written = osc.decodeClipboardSetInto(pending, out) catch return .failed;
    clearPendingClipboardSet(vt);
    return .{ .copied = written };
}

pub fn mediaCopyRequest(vt: anytype) ?u16 {
    return vt.host.media_copy_request;
}

pub fn dcsPayloadKind(vt: anytype) ?action_vocabulary.DcsPayloadKind {
    if (vt.host.dcs_payload) |payload| return payload.kind;
    return null;
}

pub fn dcsPayload(vt: anytype) ?[]const u8 {
    if (vt.host.dcs_payload) |payload| return payload.payload;
    return null;
}

pub fn legacyControl(vt: anytype) ?action_vocabulary.LegacyControlKind {
    return vt.host.legacy_control;
}

pub fn terminalColorState(vt: anytype) OscColorNs.TerminalColorState {
    return vt.host.colors;
}

pub fn kittyClipboardMode(vt: anytype) bool {
    return vt.modes.kitty_clipboard;
}

pub fn reverseWraparoundMode(vt: anytype) bool {
    return vt.modes.reverse_wraparound_mode;
}

pub fn extendedReverseWraparoundMode(vt: anytype) bool {
    return vt.modes.extended_reverse_wraparound_mode;
}

pub fn pointerMode(vt: anytype) u2 {
    return vt.modes.pointer_mode;
}
