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
        .csi_dispatch => |csi| {
            const params = try dupeArenaSlice(arena, i32, csi.params[0..csi.count]);
            const intermediates = try dupeArenaSlice(arena, u8, csi.intermediates[0..csi.intermediates_len]);
            try actions.append(allocator, .{ .csi_dispatch = .{
                .final = csi.final,
                .params = params,
                .separators = csi.separators,
                .count = csi.count,
                .leader = csi.leader,
                .private = csi.private,
                .intermediates = intermediates,
                .intermediates_len = csi.intermediates_len,
            } });
        },
        .dcs_hook => |hook| {
            const params = try dupeArenaSlice(arena, i32, hook.params[0..hook.count]);
            const intermediates = try dupeArenaSlice(arena, u8, hook.intermediates[0..hook.intermediates_len]);
            try actions.append(allocator, .{ .dcs_hook = .{
                .final = hook.final,
                .params = params,
                .count = hook.count,
                .intermediates = intermediates,
                .intermediates_len = hook.intermediates_len,
            } });
        },
        .osc_dispatch => |osc| {
            const owned = try arena.dupe(u8, osc.data);
            try actions.append(allocator, .{ .osc_dispatch = .{ .data = owned, .term = osc.term } });
        },
        else => try actions.append(allocator, action),
    }
}

fn dupeArenaSlice(arena: std.mem.Allocator, comptime T: type, data: []const T) error{OutOfMemory}![]const T {
    if (data.len == 0) return &.{};
    return try arena.dupe(T, data);
}
