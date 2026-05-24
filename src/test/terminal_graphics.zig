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

test "kitty graphics place stores metadata and replies by image id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try std.testing.expectEqual(@as(u16, 1), placement.row);
    try std.testing.expectEqual(@as(u16, 2), placement.col);
    try std.testing.expectEqual(@as(u32, 4), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
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
    try std.testing.expectEqual(@as(u16, 3), placement.row);
    try std.testing.expectEqual(@as(u16, 4), placement.col);
    try std.testing.expectEqual(@as(u32, 6), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
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
    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13;OK\x1b\\\x1b_Gi=2,I=13;OK\x1b\\\x1b_Gi=2;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementAt(&terminal, 0).?.image_id);
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
        try state.handle(allocator, .{ .row = 0, .col = 0 }, &output, encode_buf[0..], .{
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
        try state.handle(allocator, .{ .row = 0, .col = 0 }, &output, encode_buf[0..], .{
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
