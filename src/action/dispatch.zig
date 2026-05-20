//! Parent-owned action routing control spine.

const std = @import("std");
const host = @import("../host/apply.zig");
const action_mod = @import("../action.zig");
const kitty = @import("../kitty.zig");
const mode = @import("../control/mode.zig");
const report = @import("../control/report.zig");

pub const ApplySummary = struct {
    applied: u32,
    remaining_events: u32,
    latest_title: ?[]const u8,
};

// Zero max_events is a query-only pass. The owner thread chooses the apply
// slice size; VT only enforces that bound exactly and reports the true
// remaining queue depth so the next turn stays explicit.
pub fn applyLimit(vt: anytype, max_events: u32) ApplySummary {
    const queued = vt.parser.eventCount();
    if (max_events == 0) {
        return .{
            .applied = 0,
            .remaining_events = queued,
            .latest_title = null,
        };
    }

    const count = @min(max_events, queued);
    if (count == 0) return .{ .applied = 0, .remaining_events = 0, .latest_title = null };

    std.debug.assert(count <= max_events);
    std.debug.assert(count <= queued);

    var latest_title: ?[]const u8 = null;
    var iter = vt.parser.iterator();
    var remaining_to_apply = count;
    while (remaining_to_apply > 0) : (remaining_to_apply -= 1) {
        const ev = iter.next() orelse unreachable;
        latest_title = latestTitle(vt, latest_title, ev);
        applyEvent(vt, ev);
    }
    vt.parser.dropPrefix(count);
    const remaining = vt.parser.eventCount();
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    return .{ .applied = count, .remaining_events = remaining, .latest_title = latest_title };
}

fn latestTitle(vt: anytype, current: ?[]const u8, event: action_mod.Event) ?[]const u8 {
    switch (event) {
        .osc => |osc_event| {
            if (osc_event.kind != .title) return current;
            const owned = vt.allocator.dupe(u8, osc_event.payload) catch return current;
            if (vt.host.current_title) |old| vt.allocator.free(old);
            vt.host.current_title = owned;
            return owned;
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
    const screen_ev = action_mod.screenAction(sem_ev) orelse unreachable;
    vt.screen_state.active().applyScreen(screen_ev);
}
