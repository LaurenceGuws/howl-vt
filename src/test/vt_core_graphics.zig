//! Kitty graphics behavior tests.

const std = @import("std");
const vt = @import("vt_core");

test "kitty graphics query returns conservative unsupported reply" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1b_Gi=31;EINVAL:kitty graphics rendering unsupported\x1b\\", vt_core.pendingOutput());
}

test "kitty graphics direct upload stores single base64 payload" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=7,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyGraphicsImageCount());
    const image = vt_core.kittyGraphicsImageAt(0).?;
    try std.testing.expectEqual(@as(u32, 7), image.image_id);
    try std.testing.expectEqual(@as(u16, 24), image.format);
    try std.testing.expectEqual(@as(u32, 2), image.width);
    try std.testing.expectEqual(@as(u32, 1), image.height);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);
}

test "kitty graphics direct upload assembles chunked base64 payload" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=9,s=2,v=1,t=d,f=24,m=1;QU\x1b\\");
    vt_core.feedSlice("\x1b_Gm=0;JD\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyGraphicsImageCount());
    const image = vt_core.kittyGraphicsImageAt(0).?;
    try std.testing.expectEqual(@as(u32, 9), image.image_id);
    try std.testing.expectEqual(@as(u16, 24), image.format);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);
}

test "kitty graphics upload with same image id replaces image and placements" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    vt_core.feedSlice("\x1b_Ga=p,i=7,p=3,c=2,r=1\x1b\\");
    vt_core.feedSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyGraphicsImageCount());
    try std.testing.expectEqualStrings("BBBB", vt_core.kittyGraphicsImageAt(0).?.base64_payload);
    try std.testing.expectEqual(@as(usize, 0), vt_core.kittyGraphicsPlacementCount());
}

test "kitty graphics place stores metadata and replies by image id" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    vt_core.feedSlice("\x1b[2;3H");
    vt_core.feedSlice("\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", vt_core.pendingOutput());
    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyGraphicsPlacementCount());
    const placement = vt_core.kittyGraphicsPlacementAt(0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try std.testing.expectEqual(@as(u16, 1), placement.row);
    try std.testing.expectEqual(@as(u16, 2), placement.col);
    try std.testing.expectEqual(@as(u32, 4), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
}

test "kitty graphics place missing image replies ENOENT" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Ga=p,i=404\x1b\\");
    vt_core.apply();

    try std.testing.expectEqualStrings("\x1b_Gi=404;ENOENT:image not found\x1b\\", vt_core.pendingOutput());
}

test "kitty graphics delete by image id removes image and placements" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    vt_core.feedSlice("\x1b_Ga=p,i=7,p=3\x1b\\");
    vt_core.feedSlice("\x1b_Ga=d,d=i,i=7\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 0), vt_core.kittyGraphicsImageCount());
    try std.testing.expectEqual(@as(usize, 0), vt_core.kittyGraphicsPlacementCount());
}

test "kitty graphics image numbers allocate ids and place newest image" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    vt_core.feedSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    vt_core.feedSlice("\x1b_Ga=p,I=13,p=2\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 2), vt_core.kittyGraphicsImageCount());
    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13;OK\x1b\\\x1b_Gi=2,I=13;OK\x1b\\\x1b_Gi=2;OK\x1b\\", vt_core.pendingOutput());
    try std.testing.expectEqual(@as(u32, 2), vt_core.kittyGraphicsPlacementAt(0).?.image_id);
}

test "kitty graphics deletion selectors remove matching placements" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 5, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    vt_core.feedSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=1,c=4,r=2,z=5\x1b\\");
    vt_core.feedSlice("\x1b[5;10H\x1b_Ga=p,i=7,p=2,c=1,r=1,z=2\x1b\\");
    vt_core.feedSlice("\x1b_Ga=d,d=p,x=4,y=2\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyGraphicsPlacementCount());
    try std.testing.expectEqual(@as(u32, 2), vt_core.kittyGraphicsPlacementAt(0).?.placement_id);
}

test "kitty graphics animation frame upload stores frame metadata" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 16);
    defer vt_core.deinit();

    vt_core.feedSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    vt_core.feedSlice("\x1b_Ga=f,i=7,p=3,s=1,v=1,t=d,f=24;CCCC\x1b\\");
    vt_core.apply();

    try std.testing.expectEqual(@as(usize, 1), vt_core.kittyGraphicsFrameCount());
    const frame = vt_core.kittyGraphicsFrameAt(0).?;
    try std.testing.expectEqual(@as(u32, 7), frame.image_id);
    try std.testing.expectEqual(@as(u32, 3), frame.frame_number);
    try std.testing.expectEqualStrings("CCCC", frame.base64_payload);
}
