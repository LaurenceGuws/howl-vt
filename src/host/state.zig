const std = @import("std");
const locator = @import("../control/locator.zig");
const osc_color = @import("../control/osc_color.zig");
const input = @import("../input.zig");
const action = @import("../action.zig");
const osc = @import("../xterm/osc.zig");

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

pub const State = struct {
    pub const DcsPayloadOwned = struct {
        kind: action.DcsPayloadKind,
        payload: []u8,
    };

    colors: OscColorNs.State = .{},
    pending_output: std.ArrayList(u8),
    hyperlink_targets: std.ArrayList([]u8),
    pending_clipboard: ?ClipboardRequest = null,
    current_title: ?[]u8 = null,
    locator: LocatorNs.State = .{},
    media_copy_request: ?u16 = null,
    dcs_payload: ?DcsPayloadOwned = null,
    legacy_control: ?action.LegacyControlKind = null,

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
};

pub fn pendingOutput(vt: anytype) []const u8 {
    return vt.host.pending_output.items;
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

pub fn dcsPayloadKind(vt: anytype) ?action.DcsPayloadKind {
    if (vt.host.dcs_payload) |payload| return payload.kind;
    return null;
}

pub fn dcsPayload(vt: anytype) ?[]const u8 {
    if (vt.host.dcs_payload) |payload| return payload.payload;
    return null;
}

pub fn legacyControl(vt: anytype) ?action.LegacyControlKind {
    return vt.host.legacy_control;
}

pub fn terminalColorState(vt: anytype) OscColorNs.State {
    return vt.host.colors;
}

pub fn kittyClipboardMode(vt: anytype) bool {
    return vt.modes.kitty_clipboard;
}

pub fn sixelDisplayMode(vt: anytype) bool {
    return vt.modes.sixel_display_mode;
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
