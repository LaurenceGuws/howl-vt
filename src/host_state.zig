const std = @import("std");
const dcs_payload = @import("dcs_payload.zig");
const legacy_control = @import("legacy_control.zig");
const locator = @import("locator.zig");
const osc_color = @import("osc_color.zig");
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

/// Retains bounded terminal consequences for later host inspection or drain.
///
/// `allocator` is borrowed for the State lifetime and owns every retained
/// allocation; caller-selected drain allocators own only returned buffers.
pub const State = struct {
    // Host consequence retention is heap-backed today, but every retained path
    // is bounded by this file's product capacity constants before allocation.
    pub const DcsPayloadOwned = struct {
        kind: dcs_payload.DcsPayloadKind,
        payload: []u8,
    };

    allocator: std.mem.Allocator,
    colors: OscColorNs.TerminalColorState = .{},
    pending_output: std.ArrayList(u8),
    hyperlink_targets: std.ArrayList([]u8),
    pending_clipboard: ?ClipboardRequest = null,
    current_title: ?[]u8 = null,
    locator: LocatorNs.Locator = .{},
    media_copy_request: ?u16 = null,
    dcs_payload: ?DcsPayloadOwned = null,
    legacy_control: ?legacy_control.LegacyControlKind = null,

    /// Initialize empty consequence state borrowing `allocator` until deinit.
    pub fn init(allocator: std.mem.Allocator) State {
        return .{
            .allocator = allocator,
            .pending_output = std.ArrayList(u8).empty,
            .hyperlink_targets = std.ArrayList([]u8).empty,
        };
    }

    /// Release every retained allocation through the initializer allocator.
    pub fn deinit(self: *State) void {
        for (self.hyperlink_targets.items) |uri| self.allocator.free(uri);
        self.hyperlink_targets.deinit(self.allocator);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        if (self.current_title) |title| self.allocator.free(title);
        if (self.dcs_payload) |payload| self.allocator.free(payload.payload);
        self.pending_output.deinit(self.allocator);
    }

    /// Reset host-observed state governed by terminal reset.
    pub fn resetTerminalState(self: *State) void {
        self.locator = .{};
    }

    /// Borrow pending terminal reply bytes until the next State mutation.
    pub fn pendingOutput(self: *const State) []const u8 {
        return self.pending_output.items;
    }

    /// Append bounded reply bytes transactionally through the State allocator.
    pub fn appendPendingOutput(self: *State, bytes: []const u8) ApplyError!void {
        try appendOutput(&self.pending_output, self.allocator, bytes);
    }

    /// Replace the retained clipboard request after bounds and allocation succeed.
    pub fn replaceClipboard(self: *State, payload: []const u8) ApplyError!void {
        try ensureRetainedBound(byteCount(payload), retained_payload_max_bytes);
        const owned = try self.allocator.dupe(u8, payload);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = .{ .raw = owned };
    }

    /// Replace the retained DCS payload after bounds and allocation succeed.
    pub fn replaceDcsPayload(self: *State, payload: dcs_payload.DcsPayload) ApplyError!void {
        try ensureRetainedBound(byteCount(payload.payload), retained_payload_max_bytes);
        const owned = try self.allocator.dupe(u8, payload.payload);
        if (self.dcs_payload) |old| self.allocator.free(old.payload);
        self.dcs_payload = .{ .kind = payload.kind, .payload = owned };
    }

    /// Return a stable nonzero URI identity, preserving existing identities on failure.
    pub fn internHyperlink(self: *State, uri: []const u8) ApplyError!u32 {
        for (self.hyperlink_targets.items, 0..) |existing, idx| {
            if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
        }
        try ensureRetainedBound(byteCount(uri), retained_metadata_max_bytes);
        if (hyperlinkCount(self.hyperlink_targets.items) >= hyperlink_target_max_count) return error.ConsequenceLimit;
        const owned = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(owned);
        try self.hyperlink_targets.append(self.allocator, owned);
        return hyperlinkCount(self.hyperlink_targets.items);
    }

    /// Copy pending replies into caller memory without consuming them.
    pub fn copyPendingOutputInto(self: *const State, out: []u8) CopyIntoResult {
        const pending = self.pendingOutput();
        if (out.len < pending.len) return .{ .short = @intCast(pending.len) };
        if (pending.len != 0) @memcpy(out[0..pending.len], pending);
        return .{ .copied = @intCast(pending.len) };
    }

    /// Consume pending replies while retaining their allocation capacity.
    pub fn clearPendingOutput(self: *State) void {
        self.pending_output.clearRetainingCapacity();
    }

    /// Borrow the URI for a retained nonzero identity, or return null.
    pub fn hyperlinkUriForId(self: *const State, link_id: u32) ?[]const u8 {
        if (link_id == 0) return null;
        const idx = link_id - 1;
        if (idx >= self.hyperlink_targets.items.len) return null;
        return self.hyperlink_targets.items[idx];
    }

    /// Borrow the pending raw clipboard request until the next State mutation.
    pub fn pendingClipboardSet(self: *const State) ?[]const u8 {
        if (self.pending_clipboard) |req| return req.raw;
        return null;
    }

    /// Consume and release the pending raw clipboard request.
    pub fn clearPendingClipboardSet(self: *State) void {
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = null;
    }

    /// Decode into caller-owned memory; allocation failure preserves the request.
    pub fn drainPendingClipboardSet(self: *State, allocator: std.mem.Allocator) error{OutOfMemory}!?[]u8 {
        const pending = self.pendingClipboardSet() orelse return null;
        const decoded = osc.decodeClipboardSet(allocator, pending) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.clearPendingClipboardSet();
                return null;
            },
        };
        self.clearPendingClipboardSet();
        return decoded;
    }

    /// Decode into caller memory and consume only after a complete copy.
    pub fn drainPendingClipboardSetInto(self: *State, out: []u8) ClipboardDrainResult {
        const pending = self.pendingClipboardSet() orelse return .none;
        const decoded_len = osc.decodedClipboardSetSize(pending) catch return .failed;
        if (out.len < decoded_len) return .{ .short = decoded_len };
        const written = osc.decodeClipboardSetInto(pending, out) catch return .failed;
        self.clearPendingClipboardSet();
        return .{ .copied = written };
    }

    /// Return the most recently retained media-copy request.
    pub fn mediaCopyRequest(self: *const State) ?u16 {
        return self.media_copy_request;
    }

    /// Return the retained DCS payload kind, if any.
    pub fn dcsPayloadKind(self: *const State) ?dcs_payload.DcsPayloadKind {
        if (self.dcs_payload) |payload| return payload.kind;
        return null;
    }

    /// Borrow the retained DCS payload bytes, if any.
    pub fn dcsPayload(self: *const State) ?[]const u8 {
        if (self.dcs_payload) |payload| return payload.payload;
        return null;
    }

    /// Return the most recently observed legacy control kind.
    pub fn legacyControl(self: *const State) ?legacy_control.LegacyControlKind {
        return self.legacy_control;
    }

    /// Return a value snapshot of host-observable terminal colors.
    pub fn terminalColorState(self: *const State) OscColorNs.TerminalColorState {
        return self.colors;
    }
};

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

pub fn restorePendingOutput(output: *std.ArrayList(u8), len: u32) void {
    std.debug.assert(len <= byteCount(output.items));
    output.items.len = len;
}

fn ensureAppendBound(current_len: u32, append_len: u32, max_len: u32) ApplyError!void {
    const next_len = std.math.add(u32, current_len, append_len) catch return error.ConsequenceLimit;
    try ensureRetainedBound(next_len, max_len);
}

fn ensureRetainedBound(len: u32, max_len: u32) ApplyError!void {
    if (len > max_len) return error.ConsequenceLimit;
}

test "clipboard replacement preserves the retained request on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, replaceClipboardAllocation, .{});
}

fn replaceClipboardAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try state.replaceClipboard("c;b2xk");
    state.replaceClipboard("c;bmV3") catch |err| {
        try std.testing.expectEqualStrings("c;b2xk", state.pendingClipboardSet().?);
        return err;
    };
    try std.testing.expectEqualStrings("c;bmV3", state.pendingClipboardSet().?);
}

test "hyperlink interning preserves prior identities on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, internHyperlinkAllocation, .{});
}

fn internHyperlinkAllocation(allocator: std.mem.Allocator) !void {
    var state = State.init(allocator);
    defer state.deinit();
    try std.testing.expectEqual(@as(u32, 1), try state.internHyperlink("https://one.example"));
    _ = state.internHyperlink("https://two.example") catch |err| {
        try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(1).?);
        try std.testing.expectEqual(@as(?[]const u8, null), state.hyperlinkUriForId(2));
        return err;
    };
    try std.testing.expectEqualStrings("https://one.example", state.hyperlinkUriForId(1).?);
    try std.testing.expectEqualStrings("https://two.example", state.hyperlinkUriForId(2).?);
}

test "clipboard drain preserves the retained request on allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, drainClipboardAllocation, .{});
}

fn drainClipboardAllocation(result_allocator: std.mem.Allocator) !void {
    var state = State.init(std.testing.allocator);
    defer state.deinit();
    try state.replaceClipboard("c;SG93bA==");
    const decoded = state.drainPendingClipboardSet(result_allocator) catch |err| {
        try std.testing.expectEqualStrings("c;SG93bA==", state.pendingClipboardSet().?);
        return err;
    };
    defer result_allocator.free(decoded.?);
    try std.testing.expectEqualStrings("Howl", decoded.?);
    try std.testing.expectEqual(@as(?[]const u8, null), state.pendingClipboardSet());
}
