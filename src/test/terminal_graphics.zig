//! Kitty graphics behavior tests.

const std = @import("std");
const action = @import("../action.zig");
const host_state = @import("../host/state.zig");
const kitty_state = @import("../kitty/state.zig");
const terminal_mod = @import("../terminal.zig");

const Action = action;
const HostState = host_state;
const KittyState = kitty_state;
const Terminal = terminal_mod.Terminal;

fn feedSlice(terminal: *Terminal, bytes: []const u8) void {
    terminal.parser.feedSlice(bytes) catch unreachable;
}

fn apply(terminal: *Terminal) void {
    Action.apply(terminal);
}

fn pendingOutput(terminal: *const Terminal) []const u8 {
    return HostState.pendingOutput(terminal);
}

test "kitty graphics query returns conservative unsupported reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\");
    apply(&terminal);

    try std.testing.expectEqualStrings("\x1b_Gi=31;EINVAL:kitty graphics rendering unsupported\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics direct upload stores single base64 payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=7,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 1), KittyState.graphicsImageCount(&terminal));
    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), image.image_id);
    try std.testing.expectEqual(@as(u16, 24), image.format);
    try std.testing.expectEqual(@as(u32, 2), image.width);
    try std.testing.expectEqual(@as(u32, 1), image.height);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);
}

test "kitty graphics direct upload assembles chunked base64 payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=9,s=2,v=1,t=d,f=24,m=1;QU\x1b\\");
    feedSlice(&terminal, "\x1b_Gm=0;JD\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 1), KittyState.graphicsImageCount(&terminal));
    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 9), image.image_id);
    try std.testing.expectEqual(@as(u16, 24), image.format);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);
}

test "kitty graphics upload with same image id replaces image and placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    feedSlice(&terminal, "\x1b_Ga=p,i=7,p=3,c=2,r=1\x1b\\");
    feedSlice(&terminal, "\x1b_Gi=7,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("BBBB", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectEqual(@as(usize, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics place stores metadata and replies by image id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    feedSlice(&terminal, "\x1b[2;3H");
    feedSlice(&terminal, "\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\");
    apply(&terminal);

    try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(usize, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try std.testing.expectEqual(@as(u16, 1), placement.row);
    try std.testing.expectEqual(@as(u16, 2), placement.col);
    try std.testing.expectEqual(@as(u32, 4), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
}

test "kitty graphics place missing image replies ENOENT" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Ga=p,i=404\x1b\\");
    apply(&terminal);

    try std.testing.expectEqualStrings("\x1b_Gi=404;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics delete by image id removes image and placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    feedSlice(&terminal, "\x1b_Ga=p,i=7,p=3\x1b\\");
    feedSlice(&terminal, "\x1b_Ga=d,d=i,i=7\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(usize, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics image numbers allocate ids and place newest image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    feedSlice(&terminal, "\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    feedSlice(&terminal, "\x1b_Ga=p,I=13,p=2\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13;OK\x1b\\\x1b_Gi=2,I=13;OK\x1b\\\x1b_Gi=2;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementAt(&terminal, 0).?.image_id);
}

test "kitty graphics deletion selectors remove matching placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    feedSlice(&terminal, "\x1b[2;3H\x1b_Ga=p,i=7,p=1,c=4,r=2,z=5\x1b\\");
    feedSlice(&terminal, "\x1b[5;10H\x1b_Ga=p,i=7,p=2,c=1,r=1,z=2\x1b\\");
    feedSlice(&terminal, "\x1b_Ga=d,d=p,x=4,y=2\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 1), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementAt(&terminal, 0).?.placement_id);
}

test "kitty graphics animation frame upload stores frame metadata" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();

    feedSlice(&terminal, "\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    feedSlice(&terminal, "\x1b_Ga=f,i=7,p=3,s=1,v=1,t=d,f=24;CCCC\x1b\\");
    apply(&terminal);

    try std.testing.expectEqual(@as(usize, 1), KittyState.graphicsFrameCount(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), frame.image_id);
    try std.testing.expectEqual(@as(u32, 3), frame.frame_number);
    try std.testing.expectEqualStrings("CCCC", frame.base64_payload);
}
