//! Parent-owned action routing control spine.

const std = @import("std");
const screen_mod = @import("../screen.zig");
const host = @import("../host/apply.zig");
const action_mod = @import("../action.zig");
const kitty = @import("../kitty.zig");
const mode = @import("../control/mode.zig");
const report = @import("../control/report.zig");

const Screen = screen_mod.Screen;

pub const ApplySummary = struct {
    applied: u32,
    remaining_events: u32,
    latest_title: ?[]const u8,
};

// Zero max_events is a query-only pass. The owner thread chooses the apply
// slice size; VT only enforces that bound exactly and reports the true
// remaining queue depth so the next turn stays explicit.
pub fn applyLimit(vt: anytype, max_events: u32) ApplySummary {
    if (max_events == 0) {
        return .{
            .applied = 0,
            .remaining_events = vt.parser_queue.eventCount(),
            .latest_title = null,
        };
    }

    const count = @min(max_events, vt.parser_queue.eventCount());
    if (count == 0) return .{ .applied = 0, .remaining_events = 0, .latest_title = null };

    std.debug.assert(count <= max_events);
    std.debug.assert(count <= vt.parser_queue.eventCount());

    var latest_title: ?[]const u8 = null;
    for (vt.parser_queue.prefix(count)) |ev| {
        latest_title = latestTitle(latest_title, ev);
        applyEvent(vt, ev);
    }
    vt.parser_queue.dropPrefix(count);
    const remaining = vt.parser_queue.eventCount();
    std.debug.assert(remaining + count >= count);
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    return .{ .applied = count, .remaining_events = remaining, .latest_title = latest_title };
}

pub fn applyToScreen(queue: anytype, screen: *Screen) void {
    while (applyToScreenLimit(queue, screen, std.math.maxInt(u32)) != 0) {}
}

pub fn applyToScreenLimit(queue: anytype, screen: *Screen, max_events: u32) u32 {
    if (max_events == 0) return 0;
    const count = @min(max_events, queue.eventCount());
    for (queue.prefix(count)) |ev| {
        if (action_mod.process(ev)) |sem_ev| {
            if (action_mod.screenAction(sem_ev)) |screen_ev| screen.applyScreen(screen_ev);
        }
    }
    queue.dropPrefix(count);
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
