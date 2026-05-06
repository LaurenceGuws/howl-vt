//! Responsibility: handle non-grid host/protocol edge semantic consequences for vt-core.
//! Ownership: root dispatch helper for protocol edge state and host-visible side effects.
//! Reason: keep host/protocol edge handling out of the main root dispatcher.

const std = @import("std");
const grid_owner = @import("grid.zig");
const interpret_owner = @import("interpret.zig");
const kitty_owner = @import("kitty.zig");
const locator_owner = @import("locator.zig");
const osc_color_owner = @import("osc_color.zig");

const GridNs = grid_owner.Grid;
const HostAction = interpret_owner.Interpret.HostAction;
const KittyNs = kitty_owner.Kitty;
const LocatorNs = locator_owner.Locator;
const OscColorNs = osc_color_owner.OscColor;

pub const RootHostDispatch = struct {
    pub fn apply(self: anytype, action: HostAction) void {
        switch (action) {
            .terminal_color_control => |cmd| {
                switch (cmd.command) {
                    21 => KittyNs.Color.handleKittyControl(self.allocator, &self.terminal_colors, &self.pending_output, cmd.payload),
                    4 => OscColorNs.handleXtermPaletteControl(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], cmd.payload),
                    10 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], .foreground, cmd.payload),
                    11 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], .background, cmd.payload),
                    12 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], .cursor, cmd.payload),
                    104 => OscColorNs.resetXtermPalette(&self.terminal_colors, cmd.payload),
                    110 => self.terminal_colors.foreground = GridNs.default_fg,
                    111 => self.terminal_colors.background = GridNs.default_bg,
                    112 => self.terminal_colors.cursor = null,
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
                LocatorNs.setReporting(&self.locator, cfg.mode, cfg.unit);
            },
            .locator_filter => |area| {
                LocatorNs.setFilter(&self.locator, area);
            },
            .locator_events => |modes| {
                LocatorNs.setEvents(&self.locator, modes.params[0..modes.param_count]);
            },
            .locator_request => |param| {
                LocatorNs.appendReportForRequest(&self.locator, self.allocator, &self.pending_output, self.encode_buf[0..], param);
            },
            .reset_screen => {
                resetTerminalState(self);
            },
        }
    }

    fn activeStateMut(self: anytype) @TypeOf(&self.primary_state) {
        return if (self.alt_active) &self.alt_state else &self.primary_state;
    }

    fn internHyperlink(self: anytype, uri: []const u8) u32 {
        for (self.hyperlink_targets.items, 0..) |existing, idx| {
            if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
        }
        const owned = self.allocator.dupe(u8, uri) catch return 0;
        self.hyperlink_targets.append(self.allocator, owned) catch {
            self.allocator.free(owned);
            return 0;
        };
        return @intCast(self.hyperlink_targets.items.len);
    }

    fn setPendingClipboard(self: anytype, payload: []const u8) void {
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        const owned = self.allocator.dupe(u8, payload) catch {
            self.pending_clipboard = null;
            return;
        };
        self.pending_clipboard = .{ .raw = owned };
    }

    fn resetTerminalState(self: anytype) void {
        activeStateMut(self).reset();
        self.kitty_main.pointer.len = 0;
        self.kitty_alt.pointer.len = 0;
        self.kitty.color_stack_depth = 0;
        self.locator = .{};
    }
};
