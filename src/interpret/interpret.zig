//! Responsibility: export the interpret domain owner surface.
//! Ownership: interpret package boundary.
//! Reason: keep one canonical owner for parser-to-grid translation flow.

const parser_events = @import("parser_events.zig");
const actions = @import("actions/actions.zig");
const apply_flow = @import("apply_flow.zig");
const std = @import("std");
const grid = @import("../grid/grid.zig");
const types = @import("actions/types.zig");
const kitty = @import("../kitty/kitty.zig");
const locator = @import("../locator.zig");
const osc_color = @import("../osc_color.zig");

const GridNs = grid.Grid;
const KittyNs = kitty;
const LocatorNs = locator;
const OscColorNs = osc_color;
const DcsPayload = types.DcsPayload;

/// Canonical interpret domain owner.
/// Parser event payload.
pub const Event = parser_events.Event;
/// Parser event queue owner.
pub const ParserEvents = parser_events.ParserEvents;
/// Semantic event payload.
pub const SemanticEvent = actions.SemanticEvent;
/// Grid-directed action subset.
pub const ScreenAction = actions.ScreenAction;
/// Report and query action subset.
pub const ReportAction = actions.ReportAction;
/// Mode and state action subset.
pub const ModeAction = actions.ModeAction;
/// Kitty-family action subset.
pub const KittyAction = actions.KittyAction;
/// Host/protocol-edge action subset.
pub const HostAction = actions.HostAction;
/// DCS payload classification.
pub const DcsPayloadKind = actions.DcsPayloadKind;
/// Legacy C0/ESC host-neutral control classification.
pub const LegacyControlKind = actions.LegacyControlKind;
/// ESC-final action subset.
pub const EscAction = actions.EscAction;
/// End-to-end interpretation apply-flow owner.
pub const ApplyFlow = apply_flow.ApplyFlow;

/// One-shot action mapping function.
pub const process = actions.process;
/// Convert terminal events into grid-directed actions.
pub const screenAction = actions.screenAction;
/// Convert terminal events into report/query actions.
pub const reportAction = actions.reportAction;
/// Convert terminal events into mode/state actions.
pub const modeAction = actions.modeAction;
/// Convert terminal events into kitty-family actions.
pub const kittyAction = actions.kittyAction;
/// Convert terminal events into host/protocol-edge actions.
pub const hostAction = actions.hostAction;

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
