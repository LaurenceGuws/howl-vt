const std = @import("std");
const locator = @import("../control/locator.zig");
const osc_color = @import("../control/osc_color.zig");
const screen = @import("../terminal/screen.zig");
const kitty_color = @import("../kitty/color.zig");
const input_encode = @import("../input/encode.zig");
const vocabulary = @import("../action/vocabulary.zig");

const ScreenNs = screen.Screen;
const LocatorNs = locator;
const OscColorNs = osc_color;
const DcsPayload = vocabulary.DcsPayload;
const HostAction = vocabulary.HostAction;
const HostState = @import("state.zig");

pub fn apply(vt: anytype, action: HostAction) HostState.ApplyError!void {
    var scratch: input_encode.Scratch = .{};
    const allocator = vt.allocator;
    switch (action) {
        .title_set => |title| try setCurrentTitle(vt, title),
        .color_control => |cmd| {
            switch (cmd.command) {
                21 => try kitty_color.handleKittyControl(allocator, &vt.host.colors, &vt.host.pending_output, cmd.payload),
                4 => try OscColorNs.handleXtermPaletteControl(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.payload),
                5 => try OscColorNs.handleXtermSpecialPaletteControl(allocator, &vt.host.colors, &vt.host.pending_output, scratch.buf[0..], cmd.payload),
                10, 11, 12, 13, 14, 15, 16, 17, 18, 19 => try OscColorNs.handleXtermDynamicColor(
                    allocator,
                    &vt.host.colors,
                    &vt.host.pending_output,
                    scratch.buf[0..],
                    cmd.command,
                    cmd.payload,
                ),
                104 => OscColorNs.resetXtermPalette(&vt.host.colors, cmd.payload),
                110, 111, 112, 113, 114, 115, 116, 117, 118, 119 => OscColorNs.resetXtermDynamicColor(&vt.host.colors, cmd.command, cmd.payload),
                else => {},
            }
        },
        .hyperlink_set => |uri| vt.screen_state.active().setCurrentLinkId(try HostState.internHyperlink(vt, uri)),
        .hyperlink_clear => vt.screen_state.active().setCurrentLinkId(0),
        .clipboard_set => |payload| try HostState.replaceClipboard(vt, payload),
        .locator_reporting => |cfg| LocatorNs.setReporting(&vt.host.locator, cfg.mode, cfg.unit),
        .locator_filter => |area| LocatorNs.setFilter(&vt.host.locator, area),
        .locator_events => |modes| LocatorNs.setEvents(&vt.host.locator, modes.params[0..modes.param_count]),
        .locator_request => |param| try LocatorNs.appendReportForRequest(&vt.host.locator, allocator, &vt.host.pending_output, scratch.buf[0..], param),
        .media_copy_request => |param| vt.host.media_copy_request = param,
        .dcs_payload => |payload| try HostState.replaceDcsPayload(vt, payload),
        .legacy_control => |kind| vt.host.legacy_control = kind,
    }
}

pub fn setCurrentTitle(vt: anytype, title: []const u8) HostState.ApplyError!void {
    _ = try HostState.replaceOwned(vt.allocator, &vt.host.current_title, title, HostState.title_max_bytes);
}
