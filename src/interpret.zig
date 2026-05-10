//! Parser events to semantic events and owner actions.

const parsed_events = @import("interpret/parsed_events.zig");
const action_map = @import("interpret/actions/map.zig");
const apply_flow = @import("interpret/apply_flow.zig");
const event = @import("interpret/event.zig");
const std = @import("std");
const control = @import("control.zig");
const grid = @import("grid.zig");
const kitty = @import("kitty.zig");

const GridNs = grid.Grid;
const KittyNs = kitty;
const LocatorNs = control.Locator;
const OscColorNs = control.OscColor;
const DcsPayload = event.DcsPayload;

pub const Event = parsed_events.Event;
pub const ParsedEvents = parsed_events.ParsedEvents;
pub const SemanticEvent = action_map.SemanticEvent;
pub const ScreenAction = action_map.ScreenAction;
pub const ReportAction = action_map.ReportAction;
pub const ModeAction = action_map.ModeAction;
pub const KittyAction = action_map.KittyAction;
pub const HostAction = action_map.HostAction;
pub const DcsPayloadKind = action_map.DcsPayloadKind;
pub const KittyGraphicsCommand = event.KittyGraphicsCommand;
pub const KittyNotificationCommand = event.KittyNotificationCommand;
pub const KittyShellMark = event.KittyShellMark;
pub const LegacyControlKind = action_map.LegacyControlKind;
pub const EscAction = action_map.EscAction;
pub const ApplyFlow = apply_flow.ApplyFlow;
pub const Osc = @import("interpret/actions/osc.zig");

pub const process = action_map.process;
pub const screenAction = action_map.screenAction;
pub const reportAction = action_map.reportAction;
pub const modeAction = action_map.modeAction;
pub const kittyAction = action_map.kittyAction;
pub const hostAction = action_map.hostAction;

pub fn applyHost(vt: anytype, action: HostAction) void {
    switch (action) {
        .color_control => |cmd| {
            switch (cmd.command) {
                21 => KittyNs.Color.handleKittyControl(vt.allocator, &vt.host.colors, &vt.host.pending_output, cmd.payload),
                4 => OscColorNs.handleXtermPaletteControl(vt.allocator, &vt.host.colors, &vt.host.pending_output, vt.encode.buf[0..], cmd.payload),
                10 => OscColorNs.handleXtermSpecialColor(vt.allocator, &vt.host.colors, &vt.host.pending_output, vt.encode.buf[0..], .foreground, cmd.payload),
                11 => OscColorNs.handleXtermSpecialColor(vt.allocator, &vt.host.colors, &vt.host.pending_output, vt.encode.buf[0..], .background, cmd.payload),
                12 => OscColorNs.handleXtermSpecialColor(vt.allocator, &vt.host.colors, &vt.host.pending_output, vt.encode.buf[0..], .cursor, cmd.payload),
                104 => OscColorNs.resetXtermPalette(&vt.host.colors, cmd.payload),
                110 => vt.host.colors.foreground = GridNs.default_fg,
                111 => vt.host.colors.background = GridNs.default_bg,
                112 => vt.host.colors.cursor = null,
                else => {},
            }
        },
        .hyperlink_set => |uri| vt.screen_state.active().setCurrentLinkId(internHyperlink(vt, uri)),
        .hyperlink_clear => vt.screen_state.active().setCurrentLinkId(0),
        .clipboard_set => |payload| setPendingClipboard(vt, payload),
        .locator_reporting => |cfg| LocatorNs.setReporting(&vt.host.locator, cfg.mode, cfg.unit),
        .locator_filter => |area| LocatorNs.setFilter(&vt.host.locator, area),
        .locator_events => |modes| LocatorNs.setEvents(&vt.host.locator, modes.params[0..modes.param_count]),
        .locator_request => |param| LocatorNs.appendReportForRequest(&vt.host.locator, vt.allocator, &vt.host.pending_output, vt.encode.buf[0..], param),
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
    const owned = vt.allocator.dupe(u8, uri) catch return 0;
    vt.host.hyperlink_targets.append(vt.allocator, owned) catch {
        vt.allocator.free(owned);
        return 0;
    };
    return @intCast(vt.host.hyperlink_targets.items.len);
}

fn setPendingClipboard(vt: anytype, payload: []const u8) void {
    if (vt.host.pending_clipboard) |req| vt.allocator.free(req.raw);
    const owned = vt.allocator.dupe(u8, payload) catch {
        vt.host.pending_clipboard = null;
        return;
    };
    vt.host.pending_clipboard = .{ .raw = owned };
}

fn setDcsPayload(vt: anytype, payload: DcsPayload) void {
    if (vt.host.dcs_payload) |old| vt.allocator.free(old.payload);
    const owned = vt.allocator.dupe(u8, payload.payload) catch {
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
