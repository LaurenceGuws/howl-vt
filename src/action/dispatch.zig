//! Parent-owned action routing control spine.

const std = @import("std");
const grid_mod = @import("../grid.zig");
const host = @import("../host/apply.zig");
const action_mod = @import("../action.zig");
const kitty = @import("../kitty.zig");
const mode = @import("../control/mode.zig");
const report = @import("../control/report.zig");

const Grid = grid_mod.Grid;

pub const ApplySummary = struct {
    applied: usize,
    remaining_events: usize,
    latest_title: ?[]const u8,
};

pub fn applyLimit(vt: anytype, max_events: usize) ApplySummary {
    if (max_events == 0) {
        return .{
            .applied = 0,
            .remaining_events = vt.parser_state.apply_flow.events().len,
            .latest_title = null,
        };
    }

    const count = @min(max_events, vt.parser_state.apply_flow.events().len);
    if (count == 0) return .{ .applied = 0, .remaining_events = 0, .latest_title = null };

    std.debug.assert(count <= max_events);
    std.debug.assert(count <= vt.parser_state.apply_flow.events().len);

    var latest_title: ?[]const u8 = null;
    for (vt.parser_state.apply_flow.events()[0..count]) |ev| {
        latest_title = latestTitle(latest_title, ev);
        applyEvent(vt, ev);
    }
    vt.parser_state.apply_flow.parsed_events.dropPrefix(count);
    const remaining = vt.parser_state.apply_flow.events().len;
    std.debug.assert(remaining + count >= count);
        vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    return .{ .applied = count, .remaining_events = remaining, .latest_title = latest_title };
}

pub fn applyToScreen(flow: anytype, screen: *Grid) void {
    _ = applyToScreenLimit(flow, screen, std.math.maxInt(usize));
}

pub fn applyToScreenLimit(flow: anytype, screen: *Grid, max_events: usize) usize {
    if (max_events == 0) return 0;
    const count = @min(max_events, flow.events().len);
    for (flow.events()[0..count]) |ev| {
        if (action_mod.process(ev)) |sem_ev| {
            if (action_mod.screenAction(sem_ev)) |screen_ev| screen.applyScreen(screen_ev);
        }
    }
    flow.parsed_events.dropPrefix(count);
    return count;
}

fn latestTitle(current: ?[]const u8, event: action_mod.Event) ?[]const u8 {
    switch (event) {
        .osc => |osc_event| {
            if (osc_event.kind == .title) return osc_event.payload;
        },
        else => {},
    }
    return current;
}

fn applyEvent(vt: anytype, event: action_mod.Event) void {
    const sem_ev = action_mod.process(event) orelse return;
    if (action_mod.reportAction(sem_ev)) |report_action| {
        report.apply(vt, report_action);
        return;
    }
    if (action_mod.kittyAction(sem_ev)) |kitty_action| {
        kitty.apply(vt, kitty_action);
        return;
    }
    if (action_mod.modeAction(sem_ev)) |mode_action| {
        mode.apply(vt, mode_action);
        return;
    }
    if (action_mod.hostAction(sem_ev)) |host_action| {
        host.apply(vt, host_action);
        return;
    }
    std.debug.assert(action_mod.screenAction(sem_ev) != null);
    if (action_mod.screenAction(sem_ev)) |screen_ev| vt.screen_state.active().applyScreen(screen_ev);
}
