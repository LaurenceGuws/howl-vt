//! Host-facing consequence application.

const std = @import("std");
const input = @import("../input.zig");
const locator = @import("../control/locator.zig");
const osc_color = @import("../control/osc_color.zig");
const screen = @import("../screen.zig");
const kitty = @import("../kitty.zig");
const vocabulary = @import("../action/vocabulary.zig");

const ScreenNs = screen.Screen;
const KittyNs = kitty;
const LocatorNs = locator;
const OscColorNs = osc_color;
const DcsPayload = vocabulary.DcsPayload;
const HostAction = vocabulary.HostAction;

pub fn apply(vt: anytype, action: HostAction) void {
    var scratch: input.Scratch = .{};
    const allocator = vt.allocator;
    switch (action) {
        .color_control => |cmd| {
            switch (cmd.command) {
                21 => KittyNs.Color.handleKittyControl(allocator, &vt.host.colors, &vt.host.pending_output, cmd.payload),
                4 => OscColorNs.handleXtermPaletteControl(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.payload),
                5 => OscColorNs.handleXtermSpecialPaletteControl(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.payload),
                10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => OscColorNs.handleXtermDynamicColor(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.command, cmd.payload),
                104 => OscColorNs.resetXtermPalette(&vt.host.colors, cmd.payload),
                110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => OscColorNs.resetXtermDynamicColor(&vt.host.colors, cmd.command, cmd.payload),
                else => {},
            }
        },
        .hyperlink_set => |uri| vt.screen_state.active().setCurrentLinkId(internHyperlink(vt, uri)),
        .hyperlink_clear => vt.screen_state.active().setCurrentLinkId(0),
        .clipboard_set => |payload| setPendingClipboard(vt, payload),
        .locator_reporting => |cfg| LocatorNs.setReporting(&vt.host.locator, cfg.mode, cfg.unit),
        .locator_filter => |area| LocatorNs.setFilter(&vt.host.locator, area),
        .locator_events => |modes| LocatorNs.setEvents(&vt.host.locator, modes.params[0..modes.param_count]),
        .locator_request => |param| LocatorNs.appendReportForRequest(&vt.host.locator, allocator, &vt.host.pending_output, scratch.buf[0..], param),
        .media_copy_request => |param| vt.host.media_copy_request = param,
        .dcs_payload => |payload| setDcsPayload(vt, payload),
        .legacy_control => |kind| vt.host.legacy_control = kind,
        .reset_screen => resetTerminalState(vt),
    }
}

fn internHyperlink(vt: anytype, uri: []const u8) u32 {
    for (vt.host.hyperlink_targets.items, 0..) |existing, idx| {
        if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
    }
    const allocator = vt.allocator;
    const owned = allocator.dupe(u8, uri) catch return 0;
    vt.host.hyperlink_targets.append(allocator, owned) catch {
        allocator.free(owned);
        return 0;
    };
    return @intCast(vt.host.hyperlink_targets.items.len);
}

fn setPendingClipboard(vt: anytype, payload: []const u8) void {
    const allocator = vt.allocator;
    if (vt.host.pending_clipboard) |req| allocator.free(req.raw);
    const owned = allocator.dupe(u8, payload) catch {
        vt.host.pending_clipboard = null;
        return;
    };
    vt.host.pending_clipboard = .{ .raw = owned };
}

fn setDcsPayload(vt: anytype, payload: DcsPayload) void {
    const allocator = vt.allocator;
    if (vt.host.dcs_payload) |old| allocator.free(old.payload);
    const owned = allocator.dupe(u8, payload.payload) catch {
        vt.host.dcs_payload = null;
        return;
    };
    vt.host.dcs_payload = .{ .kind = payload.kind, .payload = owned };
}

fn resetTerminalState(vt: anytype) void {
    vt.screen_state.active().reset();
    vt.kitty.resetTerminalState();
    vt.host.locator = .{};
}
