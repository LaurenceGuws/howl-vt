const std = @import("std");
const host_state = @import("../host/state.zig");
const graphics = @import("../kitty/graphics.zig");
const kitty_state = @import("../kitty/state.zig");
const terminal_mod = @import("../terminal.zig");
const stream_harness = @import("stream_harness.zig");

const HostState = host_state;
const Graphics = graphics;
const KittyState = kitty_state;
const Terminal = terminal_mod.Terminal;
const StreamHarness = stream_harness.Harness;

fn pendingOutput(terminal: *const Terminal) []const u8 {
    return HostState.pendingOutput(terminal);
}

fn expectOnScreenRowAnchor(actual: Graphics.RowAnchor, expected: u16) !void {
    switch (actual) {
        .on_screen => |row| try std.testing.expectEqual(expected, row),
        .scrollback_above => return error.TestExpectedEqual,
        .below_screen => return error.TestExpectedEqual,
    }
}

fn expectScrollbackAboveRowAnchor(actual: Graphics.RowAnchor, expected: u32) !void {
    switch (actual) {
        .on_screen => return error.TestExpectedEqual,
        .scrollback_above => |rows| try std.testing.expectEqual(expected, rows),
        .below_screen => return error.TestExpectedEqual,
    }
}

fn expectBelowScreenRowAnchor(actual: Graphics.RowAnchor, expected: u32) !void {
    switch (actual) {
        .on_screen => return error.TestExpectedEqual,
        .scrollback_above => return error.TestExpectedEqual,
        .below_screen => |rows| try std.testing.expectEqual(expected, rows),
    }
}

test "kitty graphics query returns conservative unsupported reply" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=31;EINVAL:kitty graphics rendering unsupported\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics direct upload stores single base64 payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=d,f=24;QUJD\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), image.image_id);
    try std.testing.expectEqual(@as(u16, 24), image.format);
    try std.testing.expectEqual(@as(u32, 2), image.width);
    try std.testing.expectEqual(@as(u32, 1), image.height);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);
}

test "kitty graphics transmit and display stores image placement and moves cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[2;3H\x1b_Gi=7,p=4,s=2,v=1,a=T,t=d,f=24,c=4,r=2;QUJD\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7,p=4;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 4), placement.placement_id);
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 2), placement.anchor_col);
    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 6), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics unsupported action is rejected explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,a=a,s=2,v=1,t=d,f=24;QUJD\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;EINVAL:unsupported kitty graphics action\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
}

test "kitty graphics unsupported medium is rejected explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=f,f=24;L3RtcC9mb28=\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;EINVAL:unsupported kitty graphics medium\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
}

test "kitty graphics unsupported control key is rejected explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,a=p,U=1,c=2,r=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;EINVAL:unsupported kitty graphics control key\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics alt screen starts with separate empty state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));

    try stream.nextSlice("\x1b[?1049h");

    try std.testing.expect(terminal.screen_state.alt_active);
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsFrameCount(&terminal));
}

test "kitty graphics alt screen state does not leak back into main" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[?1049h");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");

    try std.testing.expect(terminal.screen_state.alt_active);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 8), KittyState.graphicsImageAt(&terminal, 0).?.image_id);

    try stream.nextSlice("\x1b[?1049l");

    try std.testing.expect(!terminal.screen_state.alt_active);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 7), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
}

test "kitty graphics alt screen clear drops previous alt state on re-entry" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[?1049h");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));

    try stream.nextSlice("\x1b[?1049l");
    try stream.nextSlice("\x1b[?1049h");

    try std.testing.expect(terminal.screen_state.alt_active);
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsFrameCount(&terminal));
}

test "kitty graphics RIS clears main and alt retained state" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[?1049h");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=8,p=2,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.imageCount());
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.alt.graphics.imageCount());
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.alt.graphics.frameCount());

    try stream.nextSlice("\x1bc");

    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.imageCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.frameCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.alt.graphics.imageCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.alt.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.alt.graphics.frameCount());
}

test "kitty graphics RIS aborts partial upload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=d,f=24,m=1;QU\x1b\\");
    try std.testing.expect(terminal.kitty.main.graphics.upload != null);

    try stream.nextSlice("\x1bc");

    try std.testing.expect(terminal.kitty.main.graphics.upload == null);
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.imageCount());

    try stream.nextSlice("\x1b_Gi=9,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.imageCount());
    try std.testing.expectEqual(@as(u32, 9), terminal.kitty.main.graphics.imageAt(0).?.image_id);
}

test "kitty graphics direct upload assembles chunked base64 payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=9,s=2,v=1,t=d,f=24,m=1;QU\x1b\\");
    try stream.nextSlice("\x1b_Gm=0;JD\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 9), image.image_id);
    try std.testing.expectEqual(@as(u16, 24), image.format);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);
}

test "kitty graphics chunk upload retains first placement metadata until completion" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=9,s=11,v=13,t=d,f=24,p=5,x=2,y=4,w=6,h=8,X=3,Y=5,c=10,r=12,z=-7,m=1;Q\x1b\\");
    {
        const upload = terminal.kitty.main.graphics.upload.?;
        try std.testing.expectEqual(@as(u32, 5), upload.placement_id);
        try std.testing.expectEqual(@as(u32, 2), upload.source_x);
        try std.testing.expectEqual(@as(u32, 4), upload.source_y);
        try std.testing.expectEqual(@as(u32, 6), upload.source_width);
        try std.testing.expectEqual(@as(u32, 8), upload.source_height);
        try std.testing.expectEqual(@as(u32, 3), upload.cell_x_offset);
        try std.testing.expectEqual(@as(u32, 5), upload.cell_y_offset);
        try std.testing.expectEqual(@as(u32, 10), upload.columns);
        try std.testing.expectEqual(@as(u32, 12), upload.rows);
        try std.testing.expectEqual(@as(i32, -7), upload.z_index);
        try std.testing.expectEqual(@as(u16, 0), upload.anchor_row);
        try std.testing.expectEqual(@as(u16, 0), upload.anchor_col);
    }

    try stream.nextSlice("\x1b[3;4H");
    try stream.nextSlice("\x1b_Gp=99,x=1,y=1,w=1,h=1,X=1,Y=1,c=1,r=1,z=9,m=1;U\x1b\\");
    {
        const upload = terminal.kitty.main.graphics.upload.?;
        try std.testing.expectEqual(@as(u32, 5), upload.placement_id);
        try std.testing.expectEqual(@as(u32, 2), upload.source_x);
        try std.testing.expectEqual(@as(u32, 4), upload.source_y);
        try std.testing.expectEqual(@as(u32, 6), upload.source_width);
        try std.testing.expectEqual(@as(u32, 8), upload.source_height);
        try std.testing.expectEqual(@as(u32, 3), upload.cell_x_offset);
        try std.testing.expectEqual(@as(u32, 5), upload.cell_y_offset);
        try std.testing.expectEqual(@as(u32, 10), upload.columns);
        try std.testing.expectEqual(@as(u32, 12), upload.rows);
        try std.testing.expectEqual(@as(i32, -7), upload.z_index);
        try std.testing.expectEqual(@as(u16, 0), upload.anchor_row);
        try std.testing.expectEqual(@as(u16, 0), upload.anchor_col);
    }

    try stream.nextSlice("\x1b_Gm=0;J\x1b\\");

    try std.testing.expect(terminal.kitty.main.graphics.upload == null);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJ", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics transmit and display chunk completion uses first placement metadata" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 6, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[2;3H\x1b_GI=13,p=5,s=11,v=13,a=T,t=d,f=24,x=2,y=4,w=6,h=8,X=3,Y=5,c=4,r=2,z=-7,m=1;Q\x1b\\");
    try stream.nextSlice("\x1b[5;9H\x1b_Gp=99,x=1,y=1,w=1,h=1,X=1,Y=1,c=1,r=1,z=9,m=0;U\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13,p=5;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 1), placement.image_id);
    try std.testing.expectEqual(@as(u32, 5), placement.placement_id);
    try std.testing.expectEqual(@as(i32, -7), placement.z_index);
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 2), placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 2), placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.source_height);
    try std.testing.expectEqual(@as(u32, 3), placement.cell_x_offset);
    try std.testing.expectEqual(@as(u32, 5), placement.cell_y_offset);
    try std.testing.expectEqual(@as(u32, 4), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
    try std.testing.expectEqual(@as(u16, 5), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 12), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics upload with same image id replaces image and placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,c=2,r=1\x1b\\");
    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;BBBB\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("BBBB", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics place stores metadata and replies with placement id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7,p=3;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try std.testing.expectEqual(@as(i32, 0), placement.z_index);
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 2), placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 0), placement.source_x);
    try std.testing.expectEqual(@as(u32, 0), placement.source_y);
    try std.testing.expectEqual(@as(u32, 1), placement.source_width);
    try std.testing.expectEqual(@as(u32, 1), placement.source_height);
    try std.testing.expectEqual(@as(u32, 0), placement.cell_x_offset);
    try std.testing.expectEqual(@as(u32, 0), placement.cell_y_offset);
    try std.testing.expectEqual(@as(u32, 4), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
    try std.testing.expectEqual(@as(u32, 4), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);
}

test "kitty graphics place moves cursor by effective placement rectangle" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\");

    try std.testing.expectEqual(@as(u16, 2), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 6), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics next physical placement anchors at moved cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\\x1b_Ga=p,i=7,p=4\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementCount(&terminal));
    const first = KittyState.graphicsPlacementAt(&terminal, 0).?;
    const second = KittyState.graphicsPlacementAt(&terminal, 1).?;
    try expectOnScreenRowAnchor(first.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 2), first.anchor_col);
    try expectOnScreenRowAnchor(second.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 6), second.anchor_col);
}

test "kitty graphics same image and placement id replaces placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,c=2,r=1\x1b\\");
    try stream.nextSlice("\x1b[4;5H");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,c=6,r=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try expectOnScreenRowAnchor(placement.anchor_row, 3);
    try std.testing.expectEqual(@as(u16, 4), placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 6), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
    try std.testing.expectEqual(@as(u32, 6), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);
}

test "kitty graphics place retains physical placement truth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=11,v=13,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[3;5H");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,x=2,y=4,w=6,h=8,X=3,Y=5,c=10,r=12,z=-7\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 9), placement.placement_id);
    try std.testing.expectEqual(@as(i32, -7), placement.z_index);
    try expectOnScreenRowAnchor(placement.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 2), placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.source_height);
    try std.testing.expectEqual(@as(u32, 3), placement.cell_x_offset);
    try std.testing.expectEqual(@as(u32, 5), placement.cell_y_offset);
    try std.testing.expectEqual(@as(u32, 10), placement.columns);
    try std.testing.expectEqual(@as(u32, 12), placement.rows);
    try std.testing.expectEqual(@as(u32, 10), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 12), placement.effective_rows);
}

test "kitty graphics row anchor represents on-screen and retained above-screen rows" {
    try expectOnScreenRowAnchor(Graphics.RowAnchor.initOnScreen(4), 4);

    const retained: Graphics.RowAnchor = .{ .scrollback_above = 3 };
    try expectScrollbackAboveRowAnchor(retained, 3);

    const below: Graphics.RowAnchor = .{ .below_screen = 2 };
    try expectBelowScreenRowAnchor(below, 2);
}

test "kitty graphics line feed full-page scroll moves placement up" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[3;1H\n");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 0);
    try std.testing.expectEqual(@as(u16, 2), placement.anchor_col);
}

test "kitty graphics full-page scroll retains placement above main screen" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 1);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[1;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[3;1H\n");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    switch (placement.anchor_row) {
        .on_screen => return error.TestExpectedEqual,
        .scrollback_above => |rows| try std.testing.expectEqual(@as(u32, 1), rows),
        .below_screen => return error.TestExpectedEqual,
    }

    try stream.nextSlice("\x1b[3;1H\n");
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.placementCount());
}

test "kitty graphics scroll up lines applies full-page upward movement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 4, 16, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[3;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[2S");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 0);
}

test "kitty graphics reverse index re-enters retained placement from scrollback" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[1;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[3;1H\n");
    try expectScrollbackAboveRowAnchor(terminal.kitty.main.graphics.placementAt(0).?.anchor_row, 1);

    try stream.nextSlice("\x1b[1;1H\x1bM");
    try expectOnScreenRowAnchor(terminal.kitty.main.graphics.placementAt(0).?.anchor_row, 0);
}

test "kitty graphics scroll down lines moves placement below page without deleting" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[2T");

    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    try expectBelowScreenRowAnchor(terminal.kitty.main.graphics.placementAt(0).?.anchor_row, 0);
}

test "kitty graphics upward scroll re-enters below-page placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[2T");
    try expectBelowScreenRowAnchor(terminal.kitty.main.graphics.placementAt(0).?.anchor_row, 0);

    try stream.nextSlice("\x1b[3;1H\n");
    try expectOnScreenRowAnchor(terminal.kitty.main.graphics.placementAt(0).?.anchor_row, 2);
}

test "kitty graphics margin line feed clips top for fully enclosed placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 5, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 10);
    try stream.nextSlice("\x1b_Gi=7,s=10,v=30,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;4r\x1b[2;3H\x1b_Ga=p,i=7,p=3,r=2\x1b\\");
    try stream.nextSlice("\x1b[4;1H\n");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u32, 10), placement.source_y);
    try std.testing.expectEqual(@as(u32, 20), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);
}

test "kitty graphics margin reverse index clips bottom for fully enclosed placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 5, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 10);
    try stream.nextSlice("\x1b_Gi=7,s=10,v=30,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;4r\x1b[3;3H\x1b_Ga=p,i=7,p=3,r=2\x1b\\");
    try stream.nextSlice("\x1b[2;1H\x1bM");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 3);
    try std.testing.expectEqual(@as(u32, 0), placement.source_y);
    try std.testing.expectEqual(@as(u32, 20), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);
}

test "kitty graphics scroll up lines skips placement not fully inside margins" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 5, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 10);
    try stream.nextSlice("\x1b_Gi=7,s=10,v=30,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;4r\x1b[1;3H\x1b_Ga=p,i=7,p=3,r=2\x1b\\");
    try stream.nextSlice("\x1b[1S");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 0);
    try std.testing.expectEqual(@as(u32, 0), placement.source_y);
    try std.testing.expectEqual(@as(u32, 30), placement.source_height);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);
}

test "kitty graphics scroll down lines clips bottom for fully enclosed placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 5, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 10);
    try stream.nextSlice("\x1b_Gi=7,s=10,v=30,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;4r\x1b[3;3H\x1b_Ga=p,i=7,p=3,r=2\x1b\\");
    try stream.nextSlice("\x1b[1T");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 3);
    try std.testing.expectEqual(@as(u32, 0), placement.source_y);
    try std.testing.expectEqual(@as(u32, 20), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);
}

test "kitty graphics erase display 2 clears visible physical placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 4);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());

    try stream.nextSlice("\x1b[2J");
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.placementCount());
}

test "kitty graphics erase display 3 keeps fully scrolled-above placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[1;3H\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b[3;1H\n\n");
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());

    try stream.nextSlice("\x1b[3J");
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    switch (terminal.kitty.main.graphics.placementAt(0).?.anchor_row) {
        .on_screen => return error.TestExpectedEqual,
        .scrollback_above => |rows| try std.testing.expectEqual(@as(u32, 2), rows),
        .below_screen => return error.TestExpectedEqual,
    }
}

test "kitty graphics screen-owned cell pixel geometry propagates to both screens" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try std.testing.expect(terminal.screen_state.primary.cellPixelSize() == null);
    try std.testing.expect(terminal.screen_state.alternate.cellPixelSize() == null);

    terminal.setCellPixelSize(11, 19);

    try std.testing.expectEqual(@as(u32, 11), terminal.screen_state.primary.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), terminal.screen_state.primary.cellPixelSize().?.height);
    try std.testing.expectEqual(@as(u32, 11), terminal.screen_state.alternate.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), terminal.screen_state.alternate.cellPixelSize().?.height);

    try stream.nextSlice("\x1b[?1049h\x1bc\x1b[?1049l");

    try std.testing.expectEqual(@as(u32, 11), terminal.screen_state.primary.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), terminal.screen_state.primary.cellPixelSize().?.height);
    try std.testing.expectEqual(@as(u32, 11), terminal.screen_state.alternate.cellPixelSize().?.width);
    try std.testing.expectEqual(@as(u32, 19), terminal.screen_state.alternate.cellPixelSize().?.height);
}

test "kitty graphics placement resolves deterministic dest geometry when cell size is known" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 3, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 20);
    try stream.nextSlice("\x1b_Gi=7,s=40,v=20,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,X=2,Y=5,c=2\x1b\\");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    const geometry = placement.resolveDestGeometry(terminal.screen_state.primary.cellPixelSize()).?;
    try std.testing.expectEqual(@as(u32, 2), geometry.left_px);
    try std.testing.expectEqual(@as(u32, 5), geometry.top_px);
    try std.testing.expectEqual(@as(u32, 22), geometry.right_px);
    try std.testing.expectEqual(@as(u32, 16), geometry.bottom_px);
}

test "kitty graphics placement geometry stays unresolved without cell size" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=40,v=20,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,X=2,Y=5,c=2\x1b\\");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expect(placement.resolveDestGeometry(terminal.screen_state.primary.cellPixelSize()) == null);
}

test "kitty graphics place defaults crop truth from uploaded image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=11,v=13,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=2\x1b\\");

    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 0), placement.columns);
    try std.testing.expectEqual(@as(u32, 0), placement.rows);
    try std.testing.expectEqual(@as(u32, 11), placement.source_width);
    try std.testing.expectEqual(@as(u32, 13), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);
}

test "kitty graphics place missing image replies ENOENT" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Ga=p,i=404\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=404;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics place missing image with placement id replies ENOENT with p" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Ga=p,i=404,p=7\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=404,p=7;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics place missing image number with placement id replies without fake image id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Ga=p,I=404,p=7\x1b\\");

    try std.testing.expectEqualStrings("\x1b_GI=404,p=7;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics delete by image id removes image and placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=i,i=7\x1b\\");

    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics image numbers allocate ids and place newest image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,I=13,p=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13;OK\x1b\\\x1b_Gi=2,I=13;OK\x1b\\\x1b_Gi=2,I=13,p=2;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementAt(&terminal, 0).?.image_id);
}

test "kitty graphics place without placement id keeps image-number reply shape" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,I=13\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13;OK\x1b\\\x1b_Gi=1,I=13;OK\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics deletion selectors remove matching placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=1,c=4,r=2,z=5\x1b\\");
    try stream.nextSlice("\x1b[5;10H\x1b_Ga=p,i=7,p=2,c=1,r=1,z=2\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=p,x=4,y=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementAt(&terminal, 0).?.placement_id);
}

test "kitty graphics animation frame upload stores frame metadata" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,p=3,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsFrameCount(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), frame.image_id);
    try std.testing.expectEqual(@as(u32, 3), frame.frame_number);
    try std.testing.expectEqualStrings("CCCC", frame.base64_payload);
}

test "kitty graphics image count cap is explicit" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    var image_id: u32 = 1;
    while (image_id <= Graphics.image_max_count) : (image_id += 1) {
        _ = try state.handle(allocator, .{ .row = 0, .col = 0 }, &output, encode_buf[0..], .{
            .action = 't',
            .image_id = image_id,
            .image_number = 0,
            .placement_id = 0,
            .format = 24,
            .width = 1,
            .height = 1,
            .columns = 0,
            .rows = 0,
            .x = 0,
            .y = 0,
            .z = 0,
            .medium = 'd',
            .more_chunks = false,
            .quiet = true,
            .delete_target = 0,
            .payload = "A",
        });
    }

    try std.testing.expectEqual(Graphics.image_max_count, state.imageCount());
    try std.testing.expectError(error.ConsequenceLimit, state.handle(allocator, .{ .row = 0, .col = 0 }, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = Graphics.image_max_count + 1,
        .image_number = 0,
        .placement_id = 0,
        .format = 24,
        .width = 1,
        .height = 1,
        .columns = 0,
        .rows = 0,
        .x = 0,
        .y = 0,
        .z = 0,
        .medium = 'd',
        .more_chunks = false,
        .quiet = true,
        .delete_target = 0,
        .payload = "A",
    }));
    try std.testing.expectEqual(Graphics.image_max_count, state.imageCount());
}

test "kitty graphics placement cap propagates through feed" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");

    var placement_count: u32 = 0;
    while (placement_count < Graphics.placement_max_count) : (placement_count += 1) {
        try stream.nextSlice("\x1b_Ga=p,i=7,q=1\x1b\\");
    }

    try std.testing.expectEqual(Graphics.placement_max_count, KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice("\x1b_Ga=p,i=7,q=1\x1b\\"));
    try std.testing.expectEqual(Graphics.placement_max_count, KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics upload byte cap propagates and aborts upload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const chunk_len = (Graphics.upload_max_bytes / 2) + 1;
    var first = std.ArrayList(u8).empty;
    defer first.deinit(allocator);
    try first.appendSlice(allocator, "\x1b_Gi=7,s=1,v=1,t=d,f=24,m=1;");
    try first.appendNTimes(allocator, 'A', chunk_len);
    try first.appendSlice(allocator, "\x1b\\");

    var second = std.ArrayList(u8).empty;
    defer second.deinit(allocator);
    try second.appendSlice(allocator, "\x1b_Gm=0;");
    try second.appendNTimes(allocator, 'B', chunk_len);
    try second.appendSlice(allocator, "\x1b\\");

    try stream.nextSlice(first.items);
    try std.testing.expectError(error.ConsequenceLimit, stream.nextSlice(second.items));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));

    try stream.nextSlice("\x1b_Gi=9,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 9), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
}

test "kitty graphics frame count cap is explicit" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    var frame_number: u32 = 1;
    while (frame_number <= Graphics.frame_max_count) : (frame_number += 1) {
        _ = try state.handle(allocator, .{ .row = 0, .col = 0 }, &output, encode_buf[0..], .{
            .action = 'f',
            .image_id = 7,
            .image_number = 0,
            .placement_id = frame_number,
            .format = 24,
            .width = 1,
            .height = 1,
            .columns = 0,
            .rows = 0,
            .x = 0,
            .y = 0,
            .z = 0,
            .medium = 'd',
            .more_chunks = false,
            .quiet = true,
            .delete_target = 0,
            .payload = "A",
        });
    }

    try std.testing.expectEqual(Graphics.frame_max_count, state.frameCount());
    try std.testing.expectError(error.ConsequenceLimit, state.handle(allocator, .{ .row = 0, .col = 0 }, &output, encode_buf[0..], .{
        .action = 'f',
        .image_id = 7,
        .image_number = 0,
        .placement_id = Graphics.frame_max_count + 1,
        .format = 24,
        .width = 1,
        .height = 1,
        .columns = 0,
        .rows = 0,
        .x = 0,
        .y = 0,
        .z = 0,
        .medium = 'd',
        .more_chunks = false,
        .quiet = true,
        .delete_target = 0,
        .payload = "A",
    }));
    try std.testing.expectEqual(Graphics.frame_max_count, state.frameCount());
}
