//! Parser actions copied into owned buffers.

const std = @import("std");
const parser_mod = @import("main.zig");

pub fn appendOwnedPhases(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    actions: *std.ArrayList(parser_mod.Action),
    phases: parser_mod.PhaseActions,
) error{OutOfMemory}!void {
    for (phases) |phase| {
        if (phase) |action| try appendOwnedAction(allocator, arena, actions, action);
    }
}

fn appendOwnedAction(
    allocator: std.mem.Allocator,
    arena: std.mem.Allocator,
    actions: *std.ArrayList(parser_mod.Action),
    action: parser_mod.Action,
) error{OutOfMemory}!void {
    switch (action) {
        .osc_dispatch => |osc| {
            const owned = try arena.dupe(u8, osc.data);
            try actions.append(allocator, .{ .osc_dispatch = .{ .data = owned, .term = osc.term } });
        },
        else => try actions.append(allocator, action),
    }
}
