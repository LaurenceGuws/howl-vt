//! Responsibility: own non-grid host and protocol-edge consequences at the vt-core boundary.
//! Ownership: vt-core protocol-edge state and host-visible side effects.
//! Reason: keep host callbacks and protocol-edge state out of the main vt-core facade.

const std = @import("std");
const grid_owner = @import("../grid.zig");
const interpret_owner = @import("../interpret.zig");
const kitty_owner = @import("../kitty.zig");
const locator_owner = @import("../locator.zig");
const osc_color_owner = @import("../osc_color.zig");

const GridNs = grid_owner.Grid;
const HostAction = interpret_owner.Interpret.HostAction;
const KittyNs = kitty_owner.Kitty;
const LocatorNs = locator_owner.Locator;
const OscColorNs = osc_color_owner.OscColor;

pub const VtCoreHost = struct {
    pub fn apply(self: anytype, action: HostAction) void {
        switch (action) {
            .terminal_color_control => |cmd| {
                switch (cmd.command) {
                    21 => KittyNs.Color.handleKittyControl(self.allocator, &self.host.terminal_colors, &self.host.pending_output, cmd.payload),
                    4 => OscColorNs.handleXtermPaletteControl(self.allocator, &self.host.terminal_colors, &self.host.pending_output, self.encode.buf[0..], cmd.payload),
                    10 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.host.terminal_colors, &self.host.pending_output, self.encode.buf[0..], .foreground, cmd.payload),
                    11 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.host.terminal_colors, &self.host.pending_output, self.encode.buf[0..], .background, cmd.payload),
                    12 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.host.terminal_colors, &self.host.pending_output, self.encode.buf[0..], .cursor, cmd.payload),
                    104 => OscColorNs.resetXtermPalette(&self.host.terminal_colors, cmd.payload),
                    110 => self.host.terminal_colors.foreground = GridNs.default_fg,
                    111 => self.host.terminal_colors.background = GridNs.default_bg,
                    112 => self.host.terminal_colors.cursor = null,
                    else => {},
                }
            },
            .hyperlink_set => |uri| {
                activeStateMut(self).setCurrentLinkId(internHyperlink(self, uri));
            },
            .hyperlink_clear => {
                activeStateMut(self).setCurrentLinkId(0);
            },
            .clipboard_set => |payload| {
                setPendingClipboard(self, payload);
            },
            .locator_reporting => |cfg| {
                LocatorNs.setReporting(&self.host.locator, cfg.mode, cfg.unit);
            },
            .locator_filter => |area| {
                LocatorNs.setFilter(&self.host.locator, area);
            },
            .locator_events => |modes| {
                LocatorNs.setEvents(&self.host.locator, modes.params[0..modes.param_count]);
            },
            .locator_request => |param| {
                LocatorNs.appendReportForRequest(&self.host.locator, self.allocator, &self.host.pending_output, self.encode.buf[0..], param);
            },
            .media_copy_request => |param| {
                self.host.media_copy_request = param;
            },
            .dcs_payload => |payload| {
                setDcsPayload(self, payload);
            },
            .reset_screen => {
                resetTerminalState(self);
            },
        }
    }

    fn activeStateMut(self: anytype) *GridNs.GridModel {
        return self.screen_state.active();
    }

    fn internHyperlink(self: anytype, uri: []const u8) u32 {
        for (self.host.hyperlink_targets.items, 0..) |existing, idx| {
            if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
        }
        const owned = self.allocator.dupe(u8, uri) catch return 0;
        self.host.hyperlink_targets.append(self.allocator, owned) catch {
            self.allocator.free(owned);
            return 0;
        };
        return @intCast(self.host.hyperlink_targets.items.len);
    }

    fn setPendingClipboard(self: anytype, payload: []const u8) void {
        if (self.host.pending_clipboard) |req| self.allocator.free(req.raw);
        const owned = self.allocator.dupe(u8, payload) catch {
            self.host.pending_clipboard = null;
            return;
        };
        self.host.pending_clipboard = .{ .raw = owned };
    }

    fn setDcsPayload(self: anytype, payload: anytype) void {
        if (self.host.dcs_payload) |old| self.allocator.free(old.payload);
        const owned = self.allocator.dupe(u8, payload.payload) catch {
            self.host.dcs_payload = null;
            return;
        };
        self.host.dcs_payload = .{ .kind = payload.kind, .payload = owned };
    }

    fn resetTerminalState(self: anytype) void {
        activeStateMut(self).reset();
        self.kitty.resetTerminalState();
        self.host.locator = .{};
    }
};
