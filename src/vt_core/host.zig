//! Responsibility: own non-grid host and protocol-edge consequences at the vt-core boundary.
//! Ownership: vt-core protocol-edge state and host-visible side effects.
//! Reason: keep host callbacks and protocol-edge state out of the main vt-core facade.

const std = @import("std");
const grid_owner = @import("../grid.zig");
const interpret_owner = @import("../interpret.zig");
const action_types = @import("../interpret/action_types.zig");
const kitty_owner = @import("../kitty.zig");
const locator_owner = @import("../locator.zig");
const osc_color_owner = @import("../osc_color.zig");

const DcsPayload = action_types.DcsPayload;
const GridNs = grid_owner;
const HostAction = interpret_owner.HostAction;
const KittyNs = kitty_owner;
const LocatorNs = locator_owner;
const OscColorNs = osc_color_owner;

pub const LinkOps = struct {
    ctx: *anyopaque,
    set_current_link_id: *const fn (ctx: *anyopaque, link_id: u32) void,
    intern_hyperlink: *const fn (ctx: *anyopaque, uri: []const u8) u32,
};

pub const ClipboardOps = struct {
    ctx: *anyopaque,
    set_pending_clipboard: *const fn (ctx: *anyopaque, payload: []const u8) void,
};

pub const DcsPayloadOps = struct {
    ctx: *anyopaque,
    set_dcs_payload: *const fn (ctx: *anyopaque, payload: DcsPayload) void,
};

pub const ResetOps = struct {
    ctx: *anyopaque,
    reset_terminal_state: *const fn (ctx: *anyopaque) void,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    terminal_colors: *OscColorNs.State,
    pending_output: *std.ArrayList(u8),
    encode_buf: []u8,
    active_state: *GridNs.GridModel,
    link_ops: LinkOps,
    clipboard_ops: ClipboardOps,
    locator: *LocatorNs.State,
    media_copy_request: *?u16,
    dcs_payload_ops: DcsPayloadOps,
    legacy_control: *?interpret_owner.LegacyControlKind,
    reset_ops: ResetOps,
};

pub fn apply(ctx: Context, action: HostAction) void {
    switch (action) {
        .terminal_color_control => |cmd| {
            switch (cmd.command) {
                21 => KittyNs.Color.handleKittyControl(ctx.allocator, ctx.terminal_colors, ctx.pending_output, cmd.payload),
                4 => OscColorNs.handleXtermPaletteControl(ctx.allocator, ctx.terminal_colors, ctx.pending_output, ctx.encode_buf, cmd.payload),
                10 => OscColorNs.handleXtermSpecialColor(ctx.allocator, ctx.terminal_colors, ctx.pending_output, ctx.encode_buf, .foreground, cmd.payload),
                11 => OscColorNs.handleXtermSpecialColor(ctx.allocator, ctx.terminal_colors, ctx.pending_output, ctx.encode_buf, .background, cmd.payload),
                12 => OscColorNs.handleXtermSpecialColor(ctx.allocator, ctx.terminal_colors, ctx.pending_output, ctx.encode_buf, .cursor, cmd.payload),
                104 => OscColorNs.resetXtermPalette(ctx.terminal_colors, cmd.payload),
                110 => ctx.terminal_colors.foreground = GridNs.default_fg,
                111 => ctx.terminal_colors.background = GridNs.default_bg,
                112 => ctx.terminal_colors.cursor = null,
                else => {},
            }
        },
        .hyperlink_set => |uri| {
            ctx.link_ops.set_current_link_id(ctx.link_ops.ctx, ctx.link_ops.intern_hyperlink(ctx.link_ops.ctx, uri));
        },
        .hyperlink_clear => {
            ctx.link_ops.set_current_link_id(ctx.link_ops.ctx, 0);
        },
        .clipboard_set => |payload| {
            ctx.clipboard_ops.set_pending_clipboard(ctx.clipboard_ops.ctx, payload);
        },
        .locator_reporting => |cfg| {
            LocatorNs.setReporting(ctx.locator, cfg.mode, cfg.unit);
        },
        .locator_filter => |area| {
            LocatorNs.setFilter(ctx.locator, area);
        },
        .locator_events => |modes| {
            LocatorNs.setEvents(ctx.locator, modes.params[0..modes.param_count]);
        },
        .locator_request => |param| {
            LocatorNs.appendReportForRequest(ctx.locator, ctx.allocator, ctx.pending_output, ctx.encode_buf, param);
        },
        .media_copy_request => |param| {
            ctx.media_copy_request.* = param;
        },
        .dcs_payload => |payload| {
            ctx.dcs_payload_ops.set_dcs_payload(ctx.dcs_payload_ops.ctx, payload);
        },
        .legacy_control => |kind| {
            ctx.legacy_control.* = kind;
        },
        .reset_screen => {
            ctx.reset_ops.reset_terminal_state(ctx.reset_ops.ctx);
        },
    }
}
