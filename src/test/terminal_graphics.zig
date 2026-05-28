const std = @import("std");
const host_state = @import("../host/state.zig");
const graphics = @import("../kitty/graphics.zig");
const kitty_state = @import("../kitty/state.zig");
const screen_mod = @import("../screen.zig");
const terminal_mod = @import("../terminal.zig");
const stream_harness = @import("stream_harness.zig");
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
});

const HostState = host_state;
const Graphics = graphics;
const KittyState = kitty_state;
const Screen = screen_mod.Screen;
const Terminal = terminal_mod.Terminal;
const StreamHarness = stream_harness.Harness;

fn pendingOutput(terminal: *const Terminal) []const u8 {
    return HostState.pendingOutput(terminal);
}

fn base64Owned(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const encoded = try allocator.alloc(u8, std.base64.standard.Encoder.calcSize(bytes.len));
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    return encoded;
}

const zlib_rgb_abc = [_]u8{ 0x78, 0x9c, 0x73, 0x74, 0x72, 0x06, 0x00, 0x01, 0x8d, 0x00, 0xc7 };
const zlib_rgba_abcd = [_]u8{ 0x78, 0x9c, 0x73, 0x74, 0x72, 0x76, 0x01, 0x00, 0x02, 0x98, 0x01, 0x0b };
const png_rgba_11223344 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMQVDJ2AQABWQCrEyolqwAAAABJRU5ErkJggg==";
const howl_app_icon_rel_path = "../howl-linux-host/assets/icon/howl_window_icon.png";

fn writeSharedMemory(name: [:0]const u8, bytes: []const u8) !void {
    const fd = c.shm_open(name, c.O_CREAT | c.O_RDWR, 0o600);
    if (fd < 0) return error.Unexpected;
    defer _ = c.close(fd);
    errdefer _ = c.shm_unlink(name);
    if (c.ftruncate(fd, @intCast(bytes.len)) != 0) return error.Unexpected;
    if (c.pwrite(fd, bytes.ptr, bytes.len, 0) != bytes.len) return error.Unexpected;
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

fn retainedPayload(allocator: std.mem.Allocator, len: usize, byte: u8) ![]u8 {
    const payload = try allocator.alloc(u8, len);
    @memset(payload, byte);
    return payload;
}

fn appendTestImage(state: *Graphics.State, allocator: std.mem.Allocator, image_id: u32, payload_len: usize) !void {
    try state.images.append(allocator, .{
        .image_id = image_id,
        .image_number = 0,
        .format = 24,
        .width = 1,
        .height = 1,
        .base64_payload = try retainedPayload(allocator, payload_len, 'A'),
    });
}

fn appendTestPlacement(state: *Graphics.State, allocator: std.mem.Allocator, image_id: u32) !void {
    try state.placements.append(allocator, .{
        .image_id = image_id,
        .placement_id = image_id,
        .z_index = 0,
        .anchor_row = Graphics.RowAnchor.initOnScreen(0),
        .anchor_col = 0,
        .source_x = 0,
        .source_y = 0,
        .source_width = 1,
        .source_height = 1,
        .cell_x_offset = 0,
        .cell_y_offset = 0,
        .columns = 1,
        .rows = 1,
        .effective_columns = 1,
        .effective_rows = 1,
    });
}

fn appendTestVirtualPlacement(state: *Graphics.State, allocator: std.mem.Allocator, image_id: u32) !void {
    try state.virtual_placements.append(allocator, .{
        .image_id = image_id,
        .placement_id = image_id,
        .source_x = 0,
        .source_y = 0,
        .source_width = 1,
        .source_height = 1,
        .columns = 1,
        .rows = 1,
    });
}

fn imageIndexById(state: *const Graphics.State, image_id: u32) ?u32 {
    var idx: u32 = 0;
    while (idx < state.imageCount()) : (idx += 1) {
        if (state.imageAt(idx).?.image_id == image_id) return idx;
    }
    return null;
}

fn setPlaceholderCell(
    terminal: *Terminal,
    row: u16,
    col: u16,
    image_color: Screen.Color,
    placement_id: u8,
    row_diacritic: ?u21,
    col_diacritic: ?u21,
    high_byte_diacritic: ?u21,
) void {
    var cell = Screen.default_cell;
    cell.codepoint = 0x10EEEE;
    cell.attrs = .{
        .fg = image_color,
        .bg = Screen.default_bg,
        .bold = false,
        .dim = false,
        .italic = false,
        .blink = false,
        .blink_fast = false,
        .reverse = false,
        .invisible = false,
        .underline = true,
        .strikethrough = false,
        .underline_style = .straight,
        .underline_color = Screen.Color.indexed(placement_id),
        .protected = false,
        .link_id = 0,
    };
    if (row_diacritic) |value| {
        cell.combining_len = 1;
        cell.combining[0] = value;
    }
    if (col_diacritic) |value| {
        if (cell.combining_len < 2) cell.combining_len = 2;
        cell.combining[1] = value;
    }
    if (high_byte_diacritic) |value| {
        if (cell.combining_len < 3) cell.combining_len = 3;
        cell.combining[2] = value;
    }
    terminal.screen_state.active().cells.?[@as(usize, row) * terminal.screen_state.activeConst().cols + col] = cell;
}

test "kitty graphics query returns OK without storing image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=31,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=31;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
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

test "kitty graphics invalid integer parser input emits no reply and does not mutate" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("", pendingOutput(&terminal));

    try stream.nextSlice("\x1b_Gi=abc,s=2,v=1,t=d,f=24;QUJD\x1b\\");

    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 7), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
}

test "kitty graphics invalid flag and unknown key parser input emits no reply and does not mutate" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));

    try stream.nextSlice("\x1b_Gi=8,a=Z,s=2,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Gi=9,N=1,s=2,v=1,t=d,f=24;QUJD\x1b\\");

    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 7), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
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
    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 6), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics anonymous physical placements publish distinct render order keys" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,c=1,r=1\x1b\\");

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 2), meta.placement_count);
    const first = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    const second = (try terminal.graphicsPlacement(meta.publication_seq, 1)).?;
    try std.testing.expect(first.render_order_key != 0);
    try std.testing.expect(second.render_order_key != 0);
    try std.testing.expect(first.render_order_key != second.render_order_key);
}

test "kitty graphics physical placement updates and conversion preserve render order key" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,c=1,r=1\x1b\\");
    var meta = try terminal.graphicsMeta();
    const initial = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try std.testing.expect(initial.render_order_key != 0);

    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,c=2,r=1\x1b\\");
    meta = try terminal.graphicsMeta();
    const updated = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(initial.render_order_key, updated.render_order_key);

    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,U=1,c=3,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,c=4,r=1\x1b\\");
    meta = try terminal.graphicsMeta();
    const converted = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(initial.render_order_key, converted.render_order_key);
}

test "kitty graphics animation control for missing image is rejected explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,a=a,s=2,v=1,t=d,f=24;QUJD\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
}

test "kitty graphics file upload loads and normalizes base64 payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();
    const io = std.Io.Threaded.global_single_threaded.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "image.bin", .data = "ZABCY" });
    const path = try tmp.dir.realPathFileAlloc(io, "image.bin", allocator);
    defer allocator.free(path);
    const encoded_path = try base64Owned(allocator, path);
    defer allocator.free(encoded_path);

    const seq = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,S=3,O=1,t=f,f=24;{s}\x1b\\", .{encoded_path});
    defer allocator.free(seq);

    try stream.nextSlice(seq);

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics temp file upload deletes safe temp file" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();
    const io = std.Io.Threaded.global_single_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path_text = try std.fmt.allocPrint(allocator, "/tmp/howl-tty-graphics-protocol-{s}.bin", .{tmp.sub_path});
    defer allocator.free(path_text);
    const path = try allocator.dupeZ(u8, path_text);
    defer allocator.free(path);
    defer _ = c.unlink(path);
    const fd = c.open(path, c.O_CREAT | c.O_WRONLY | c.O_TRUNC, @as(c_uint, 0o600));
    if (fd < 0) return error.Unexpected;
    defer _ = c.close(fd);
    if (c.write(fd, "ABC", 3) != 3) return error.Unexpected;
    const encoded_path = try base64Owned(allocator, path);
    defer allocator.free(encoded_path);

    const seq = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,t=t,f=24;{s}\x1b\\", .{encoded_path});
    defer allocator.free(seq);

    try stream.nextSlice(seq);

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openFileAbsolute(io, path, .{}));
}

test "kitty graphics shared memory upload loads and unlinks object" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const shm_name = "/howl-kitty-graphics-test";
    const shm_name_z = try allocator.dupeZ(u8, shm_name);
    defer allocator.free(shm_name_z);
    _ = c.shm_unlink(shm_name_z);
    try writeSharedMemory(shm_name_z, "ABC");

    const encoded_name = try base64Owned(allocator, shm_name);
    defer allocator.free(encoded_name);
    const seq = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,t=s,f=24;{s}\x1b\\", .{encoded_name});
    defer allocator.free(seq);

    try stream.nextSlice(seq);

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectError(error.FileNotFound, cShmOpenReadOnly(shm_name_z));
}

fn cShmOpenReadOnly(name: [:0]const u8) !void {
    const fd = c.shm_open(name, c.O_RDONLY, 0);
    if (fd < 0) return error.FileNotFound;
    _ = c.close(fd);
}

test "kitty graphics invalid transmission flag is rejected by parser" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=1,t=x,f=24;AAAA\x1b\\");

    try std.testing.expectEqualStrings("", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
}

test "kitty graphics direct upload decompresses raw zlib payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,o=z,f=24;eJxzdHIGAAGNAMc=\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics direct chunked upload decompresses raw zlib payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=9,s=1,v=1,t=d,o=z,f=24,m=1;eJxz\x1b\\");
    try stream.nextSlice("\x1b_Gm=0;dHIGAAGNAMc=\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics file upload decompresses raw zlib payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();
    const io = std.Io.Threaded.global_single_threaded.io();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "image.bin", .data = zlib_rgb_abc[0..] });
    const path = try tmp.dir.realPathFileAlloc(io, "image.bin", allocator);
    defer allocator.free(path);
    const encoded_path = try base64Owned(allocator, path);
    defer allocator.free(encoded_path);

    const seq = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,S={d},t=f,o=z,f=24;{s}\x1b\\", .{ zlib_rgb_abc.len, encoded_path });
    defer allocator.free(seq);

    try stream.nextSlice(seq);

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics temp file upload decompresses raw zlib payload and deletes safe temp file" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();
    const io = std.Io.Threaded.global_single_threaded.io();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path_text = try std.fmt.allocPrint(allocator, "/tmp/howl-tty-graphics-protocol-{s}.bin", .{tmp.sub_path});
    defer allocator.free(path_text);
    const path = try allocator.dupeZ(u8, path_text);
    defer allocator.free(path);
    defer _ = c.unlink(path);
    const fd = c.open(path, c.O_CREAT | c.O_WRONLY | c.O_TRUNC, @as(c_uint, 0o600));
    if (fd < 0) return error.Unexpected;
    defer _ = c.close(fd);
    if (c.write(fd, zlib_rgba_abcd[0..].ptr, zlib_rgba_abcd.len) != zlib_rgba_abcd.len) return error.Unexpected;
    const encoded_path = try base64Owned(allocator, path);
    defer allocator.free(encoded_path);

    const seq = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,S={d},t=t,o=z,f=32;{s}\x1b\\", .{ zlib_rgba_abcd.len, encoded_path });
    defer allocator.free(seq);

    try stream.nextSlice(seq);

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJDRA==", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.openFileAbsolute(io, path, .{}));
}

test "kitty graphics shared memory upload decompresses raw zlib payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const shm_name = "/howl-kitty-graphics-zlib-test";
    const shm_name_z = try allocator.dupeZ(u8, shm_name);
    defer allocator.free(shm_name_z);
    _ = c.shm_unlink(shm_name_z);
    try writeSharedMemory(shm_name_z, zlib_rgb_abc[0..]);

    const encoded_name = try base64Owned(allocator, shm_name);
    defer allocator.free(encoded_name);
    const seq = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,S={d},t=s,o=z,f=24;{s}\x1b\\", .{ zlib_rgb_abc.len, encoded_name });
    defer allocator.free(seq);

    try stream.nextSlice(seq);

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectError(error.FileNotFound, cShmOpenReadOnly(shm_name_z));
}

test "kitty graphics png zlib compression is rejected explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,t=d,o=z,f=100;eJxzdHIGAAGNAMc=\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;EINVAL:unsupported kitty graphics compression\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
}

test "kitty graphics place stores virtual placement prototype for U=1" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=11,v=13,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=7,a=p,U=1,c=2,r=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
    const placement = terminal.kitty.main.graphics.virtualPlacementAt(0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 0), placement.placement_id);
    try std.testing.expectEqual(@as(u32, 11), placement.source_width);
    try std.testing.expectEqual(@as(u32, 13), placement.source_height);
    try std.testing.expectEqual(@as(u32, 2), placement.columns);
    try std.testing.expectEqual(@as(u32, 1), placement.rows);
}

test "kitty graphics virtual placement derives omitted grid extent" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    terminal.setCellPixelSize(10, 20);
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=20,v=40,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=7,a=p,U=1,w=20,h=40\x1b\\");

    const placement = terminal.kitty.main.graphics.virtualPlacementAt(0).?;
    try std.testing.expectEqual(@as(u32, 2), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
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

test "kitty graphics transmit and display chunk completion keeps first unicode placement metadata" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 6, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[2;3H\x1b_GI=13,p=5,U=1,C=1,s=11,v=13,a=T,t=d,f=24,x=2,y=4,w=6,h=8,X=3,Y=5,m=1;Q\x1b\\");
    try stream.nextSlice("\x1b[5;9H\x1b_Gp=99,x=1,y=1,w=1,h=1,c=7,r=3,m=0;U\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=1,I=13,p=5;OK\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
    const placement = terminal.kitty.main.graphics.virtualPlacementAt(0).?;
    try std.testing.expectEqual(@as(u32, 1), placement.image_id);
    try std.testing.expectEqual(@as(u32, 5), placement.placement_id);
    try std.testing.expectEqual(@as(u32, 2), placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.columns);
    try std.testing.expectEqual(@as(u32, 1), placement.rows);
    try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 8), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics chunked yazi-like unicode no-move contract publishes one coherent virtual placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 6, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[2;3H\x1b_GI=13,p=5,U=1,C=1,s=11,v=13,a=T,t=d,f=24,x=2,y=4,w=6,h=8,c=7,r=3,m=1;Q\x1b\\");
    try stream.nextSlice("\x1b[5;9H\x1b_Gp=99,x=1,y=1,w=1,h=1,c=1,r=1,m=0;UJD\x1b\\");

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 1), meta.image_count);
    try std.testing.expectEqual(@as(u32, 0), meta.placement_count);
    try std.testing.expectEqual(@as(u32, 1), meta.virtual_placement_count);
    try std.testing.expect(meta.publication_seq != 0);

    const image = (try terminal.graphicsImage(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 1), image.image_id);
    try std.testing.expectEqual(@as(u32, 13), image.image_number);
    try std.testing.expectEqualStrings("QUJD", image.base64_payload);

    const placement = (try terminal.graphicsVirtualPlacement(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 1), placement.image_id);
    try std.testing.expectEqual(@as(u32, 5), placement.placement_id);
    try std.testing.expectEqual(@as(u32, 2), placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.source_y);
    try std.testing.expectEqual(@as(u32, 6), placement.source_width);
    try std.testing.expectEqual(@as(u32, 8), placement.source_height);
    try std.testing.expectEqual(@as(u32, 7), placement.columns);
    try std.testing.expectEqual(@as(u32, 3), placement.rows);
    try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 8), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics placeholder-run export resolves left-to-right row inheritance" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    terminal.setCellPixelSize(10, 20);
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=3,r=1\x1b\\");

    setPlaceholderCell(&terminal, 1, 2, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 1, 3, Screen.Color.indexed(7), 9, null, null, null);
    setPlaceholderCell(&terminal, 1, 4, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 1), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));
    const run = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 7), run.image_id);
    try std.testing.expectEqual(@as(u32, 9), run.placement_id);
    try std.testing.expectEqual(@as(u32, 0), run.virtual_placement_index);
    try std.testing.expectEqual(@as(u32, 0), run.run_order);
    try std.testing.expectEqual(@as(u16, 1), run.cell_row);
    try std.testing.expectEqual(@as(u16, 2), run.cell_col);
    try std.testing.expectEqual(@as(u32, 0), run.image_row);
    try std.testing.expectEqual(@as(u32, 0), run.image_col);
    try std.testing.expectEqual(@as(u32, 3), run.columns);
}

test "kitty graphics placeholder cells publish generated placements and suppress render runs" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    terminal.setCellPixelSize(10, 20);
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=100,v=40,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,x=10,y=4,w=80,h=20,c=4,r=2\x1b\\");

    setPlaceholderCell(&terminal, 1, 2, Screen.Color.indexed(7), 9, 0x0305, 0x030E, null);
    setPlaceholderCell(&terminal, 1, 3, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 1), meta.placement_count);
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 1), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));

    const placement = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 9), placement.placement_id);
    try std.testing.expectEqual(@as(i32, -1), placement.z_index);
    try std.testing.expect(placement.flags & Graphics.placement_generated_placeholder_flag != 0);
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 2), placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 50), placement.source_x);
    try std.testing.expectEqual(@as(u32, 4), placement.source_y);
    try std.testing.expectEqual(@as(u32, 40), placement.source_width);
    try std.testing.expectEqual(@as(u32, 10), placement.source_height);
    try std.testing.expectEqual(@as(u32, 2), placement.columns);
    try std.testing.expectEqual(@as(u32, 0), placement.rows);
    const dest = placement.resolveDestGeometry(terminal.screen_state.activeConst().cellPixelSize()).?;
    try std.testing.expectEqual(@as(u32, 0), dest.left_px);
    try std.testing.expectEqual(@as(u32, 15), dest.top_px);
    try std.testing.expectEqual(@as(u32, 20), dest.right_px);
    try std.testing.expectEqual(@as(u32, 20), dest.bottom_px);
}

test "kitty graphics generated placements publish stable synthetic render order keys" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    terminal.setCellPixelSize(10, 20);
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=100,v=40,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,x=0,y=0,w=80,h=20,c=4,r=2\x1b\\");
    const virtual = terminal.kitty.main.graphics.virtualPlacementAt(0).?;
    try std.testing.expect(virtual.ref_id != 0);

    setPlaceholderCell(&terminal, 1, 1, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 2, 1, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    terminal.postApply(true);

    var meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 2), meta.placement_count);
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    var first = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    var second = (try terminal.graphicsPlacement(meta.publication_seq, 1)).?;
    try std.testing.expectEqual((@as(u64, virtual.ref_id) << 32) | @as(u64, 0), first.render_order_key);
    try std.testing.expectEqual((@as(u64, virtual.ref_id) << 32) | @as(u64, 1), second.render_order_key);
    try std.testing.expect(first.render_order_key != 0);
    try std.testing.expect(second.render_order_key != 0);
    try std.testing.expect(first.render_order_key != second.render_order_key);

    meta = try terminal.graphicsMeta();
    first = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    second = (try terminal.graphicsPlacement(meta.publication_seq, 1)).?;
    try std.testing.expectEqual((@as(u64, virtual.ref_id) << 32) | @as(u64, 0), first.render_order_key);
    try std.testing.expectEqual((@as(u64, virtual.ref_id) << 32) | @as(u64, 1), second.render_order_key);
}

test "kitty graphics generated placements clear and update from VT truth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    terminal.setCellPixelSize(10, 20);
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=100,v=40,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,x=10,y=4,w=80,h=20,c=4,r=2\x1b\\");
    setPlaceholderCell(&terminal, 1, 2, Screen.Color.indexed(7), 9, 0x0305, 0x030D, null);
    terminal.postApply(true);

    const first_meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 1), first_meta.placement_count);
    const first = (try terminal.graphicsPlacement(first_meta.publication_seq, 0)).?;

    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,x=20,y=0,w=40,h=20,c=4,r=2\x1b\\");
    const updated_meta = try terminal.graphicsMeta();
    const updated = (try terminal.graphicsPlacement(updated_meta.publication_seq, 0)).?;
    try std.testing.expect(updated.source_x != first.source_x or updated.source_width != first.source_width or updated.source_y != first.source_y);

    terminal.screen_state.active().cells.?[@as(usize, 1) * terminal.screen_state.activeConst().cols + 2] = Screen.default_cell;
    terminal.postApply(true);
    const cleared_meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), cleared_meta.placement_count);
    try std.testing.expectEqual(@as(u32, 0), try terminal.graphicsPlaceholderRunProofCount(cleared_meta.publication_seq));
}

test "kitty graphics physical placements sort before generated placeholder placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=4,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    setPlaceholderCell(&terminal, 2, 1, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 2), meta.placement_count);
    const physical = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    const generated = (try terminal.graphicsPlacement(meta.publication_seq, 1)).?;
    try std.testing.expectEqual(@as(u32, 4), physical.placement_id);
    try std.testing.expectEqual(@as(u32, 0), physical.flags);
    try std.testing.expectEqual(@as(u32, 9), generated.placement_id);
    try std.testing.expect(generated.flags & Graphics.placement_generated_placeholder_flag != 0);
}

test "kitty graphics placeholder-run export maps U+0305 to row and column zero" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 1, 2, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 1), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));
    const run = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 0), run.image_row);
    try std.testing.expectEqual(@as(u32, 0), run.image_col);
}

test "kitty graphics placeholder-run export infers missing column and high byte on same row" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=16777223,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=16777223,p=9,U=1,c=3,r=1\x1b\\");

    setPlaceholderCell(&terminal, 1, 2, Screen.Color.rgbComponents(0, 0, 7), 9, 0x0305, 0x0305, 0x030D);
    setPlaceholderCell(&terminal, 1, 3, Screen.Color.rgbComponents(0, 0, 7), 9, 0x0305, null, null);
    setPlaceholderCell(&terminal, 1, 4, Screen.Color.rgbComponents(0, 0, 7), 9, null, null, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 1), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));
    const run = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 16777223), run.image_id);
    try std.testing.expectEqual(@as(u32, 0), run.image_row);
    try std.testing.expectEqual(@as(u32, 0), run.image_col);
    try std.testing.expectEqual(@as(u32, 3), run.columns);
}

test "kitty graphics placeholder-run export breaks on mismatched fields" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 5, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Gi=16777223,s=1,v=1,t=d,f=24;CCCC\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=3,r=2\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=10,U=1,c=3,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=9,U=1,c=3,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=16777223,p=9,U=1,c=3,r=1\x1b\\");

    setPlaceholderCell(&terminal, 0, 0, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 0, 1, Screen.Color.indexed(7), 9, 0x030D, null, null);
    setPlaceholderCell(&terminal, 1, 0, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 1, 1, Screen.Color.indexed(7), 9, 0x0305, 0x030E, null);
    setPlaceholderCell(&terminal, 2, 0, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 2, 1, Screen.Color.indexed(8), 9, 0x0305, 0x030D, null);
    setPlaceholderCell(&terminal, 3, 0, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 3, 1, Screen.Color.indexed(7), 10, 0x0305, 0x030D, null);
    setPlaceholderCell(&terminal, 4, 0, Screen.Color.rgbComponents(0, 0, 7), 9, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 4, 1, Screen.Color.rgbComponents(0, 0, 7), 9, 0x0305, 0x030D, 0x030D);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 10), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));
    const row_mismatch_second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 1)).?;
    const col_mismatch_second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 3)).?;
    const image_mismatch_second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 5)).?;
    const placement_mismatch_second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 7)).?;
    const high_mismatch_second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 9)).?;
    try std.testing.expectEqual(@as(u32, 1), row_mismatch_second.image_row);
    try std.testing.expectEqual(@as(u32, 0), row_mismatch_second.image_col);
    try std.testing.expectEqual(@as(u32, 0), col_mismatch_second.image_row);
    try std.testing.expectEqual(@as(u32, 2), col_mismatch_second.image_col);
    try std.testing.expectEqual(@as(u32, 8), image_mismatch_second.image_id);
    try std.testing.expectEqual(@as(u32, 10), placement_mismatch_second.placement_id);
    try std.testing.expectEqual(@as(u32, 16777223), high_mismatch_second.image_id);
}

test "kitty graphics placeholder-run export does not inherit across rows" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=8,r=2\x1b\\");

    setPlaceholderCell(&terminal, 0, 7, Screen.Color.indexed(7), 9, 0x0305, 0x033F, null);
    setPlaceholderCell(&terminal, 1, 0, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 2), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));
    const first = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    const second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 1)).?;
    try std.testing.expectEqual(@as(u16, 0), first.cell_row);
    try std.testing.expectEqual(@as(u16, 7), first.cell_col);
    try std.testing.expectEqual(@as(u32, 0), first.image_row);
    try std.testing.expectEqual(@as(u32, 7), first.image_col);
    try std.testing.expectEqual(@as(u16, 1), second.cell_row);
    try std.testing.expectEqual(@as(u16, 0), second.cell_col);
    try std.testing.expectEqual(@as(u32, 0), second.image_row);
    try std.testing.expectEqual(@as(u32, 0), second.image_col);
}

test "kitty graphics placeholder-run export matches image id high byte" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=16777223,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=16777223,p=9,U=1,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 2, 6, Screen.Color.rgbComponents(0, 0, 7), 9, 0x0305, 0x0305, 0x030D);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    const run = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 16777223), run.image_id);
    try std.testing.expectEqual(@as(u32, 9), run.placement_id);
}

test "kitty graphics placeholder-run export resolves anonymous placement to first matching virtual placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,U=1,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 0, 0, Screen.Color.indexed(7), 0, 0x0305, 0x0305, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 2), meta.virtual_placement_count);
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    const run = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 0), run.placement_id);
    try std.testing.expectEqual(@as(u32, 0), run.virtual_placement_index);
}

test "kitty graphics placeholder-run export carries stable order for same-image multi-placement runs" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=10,U=1,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 0, 3, Screen.Color.indexed(7), 10, 0x0305, 0x0305, null);
    setPlaceholderCell(&terminal, 2, 1, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 2), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));

    const first = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    const second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 1)).?;
    try std.testing.expectEqual(@as(u32, 10), first.placement_id);
    try std.testing.expectEqual(@as(u32, 1), first.virtual_placement_index);
    try std.testing.expectEqual(@as(u32, 0), first.run_order);
    try std.testing.expectEqual(@as(u32, 9), second.placement_id);
    try std.testing.expectEqual(@as(u32, 0), second.virtual_placement_index);
    try std.testing.expectEqual(@as(u32, 1), second.run_order);
}

test "kitty graphics placeholder-run export covers yazi-like alt-screen path coherently" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 6, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b[?1049h");
    try stream.nextSlice("\x1b[2;3H\x1b_GI=13,p=5,U=1,C=1,s=11,v=13,a=T,t=d,f=24,x=2,y=4,w=6,h=8,c=7,r=3,m=1;Q\x1b\\");
    try stream.nextSlice("\x1b[5;9H\x1b_Gp=99,x=1,y=1,w=1,h=1,c=1,r=1,m=0;UJD\x1b\\");

    setPlaceholderCell(&terminal, 1, 8, Screen.Color.indexed(1), 5, 0x0305, 0x030D, null);
    setPlaceholderCell(&terminal, 1, 9, Screen.Color.indexed(1), 5, null, null, null);
    setPlaceholderCell(&terminal, 1, 10, Screen.Color.indexed(1), 5, null, null, null);
    setPlaceholderCell(&terminal, 2, 8, Screen.Color.indexed(1), 5, 0x030D, 0x030D, null);
    setPlaceholderCell(&terminal, 2, 9, Screen.Color.indexed(1), 5, null, null, null);
    setPlaceholderCell(&terminal, 2, 10, Screen.Color.indexed(1), 5, null, null, null);
    setPlaceholderCell(&terminal, 3, 8, Screen.Color.indexed(1), 5, 0x030E, 0x030D, null);
    setPlaceholderCell(&terminal, 3, 9, Screen.Color.indexed(1), 5, null, null, null);
    setPlaceholderCell(&terminal, 3, 10, Screen.Color.indexed(1), 5, null, null, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expect(meta.is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 1), meta.virtual_placement_count);
    try std.testing.expectEqual(@as(u32, 0), meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 3), try terminal.graphicsPlaceholderRunProofCount(meta.publication_seq));

    const first = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 0)).?;
    const second = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 1)).?;
    const third = (try terminal.graphicsPlaceholderRunProof(meta.publication_seq, 2)).?;
    try std.testing.expectEqual(@as(u32, 1), first.image_id);
    try std.testing.expectEqual(@as(u32, 5), first.placement_id);
    try std.testing.expectEqual(@as(u16, 8), first.cell_col);
    try std.testing.expectEqual(@as(u32, 0), first.image_row);
    try std.testing.expectEqual(@as(u32, 1), second.image_row);
    try std.testing.expectEqual(@as(u32, 2), third.image_row);
    try std.testing.expectEqual(@as(u32, 1), first.image_col);
    try std.testing.expectEqual(@as(u32, 3), first.columns);
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

    try std.testing.expectEqual(@as(u16, 3), terminal.screen_state.activeConst().cursor_row);
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
    try expectOnScreenRowAnchor(second.anchor_row, 3);
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

test "kitty graphics physical placement converts to virtual for same nonzero placement id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,c=2,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,U=1,c=4,r=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
    const placement = terminal.kitty.main.graphics.virtualPlacementAt(0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try std.testing.expectEqual(@as(u32, 4), placement.columns);
    try std.testing.expectEqual(@as(u32, 2), placement.rows);
}

test "kitty graphics virtual placement converts to physical for same nonzero placement id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,U=1,c=4,r=2\x1b\\");
    try stream.nextSlice("\x1b[3;5H\x1b_Ga=p,i=7,p=3,c=2,r=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.virtualPlacementCount());
    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), placement.image_id);
    try std.testing.expectEqual(@as(u32, 3), placement.placement_id);
    try expectOnScreenRowAnchor(placement.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), placement.anchor_col);
    try std.testing.expectEqual(@as(u32, 2), placement.columns);
    try std.testing.expectEqual(@as(u32, 1), placement.rows);
}

test "kitty graphics repeated physical virtual conversions keep one placement and one reply per command" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=5,U=1,c=1,r=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
    try std.testing.expectEqualStrings(
        "\x1b_Gi=7,p=5;OK\x1b\\" ++
            "\x1b_Gi=7,p=5;OK\x1b\\" ++
            "\x1b_Gi=7,p=5;OK\x1b\\" ++
            "\x1b_Gi=7,p=5;OK\x1b\\",
        pendingOutput(&terminal),
    );
}

test "kitty graphics anonymous physical and virtual placements do not replace each other" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,c=2,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,U=1,c=4,r=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementAt(&terminal, 0).?.placement_id);
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.virtualPlacementAt(0).?.placement_id);
}

test "kitty graphics child parent kind follows converted nonzero placement" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=9,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,H=2,V=1,c=1,r=1\x1b\\");
    try std.testing.expect(!terminal.kitty.main.graphics.placementAt(1).?.parent_is_virtual);

    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
    try std.testing.expect(terminal.kitty.main.graphics.placementAt(0).?.parent_is_virtual);
    setPlaceholderCell(&terminal, 3, 4, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);
    var meta = try terminal.graphicsMeta();
    var child = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 4);
    try std.testing.expectEqual(@as(u16, 6), child.anchor_col);

    try stream.nextSlice("\x1b[5;6H\x1b_Ga=p,i=7,p=9,c=1,r=1\x1b\\");
    try std.testing.expectEqual(@as(u32, 2), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.virtualPlacementCount());
    const first = terminal.kitty.main.graphics.placementAt(0).?;
    const second = terminal.kitty.main.graphics.placementAt(1).?;
    child = if (first.image_id == 8) first else second;
    try std.testing.expect(!child.parent_is_virtual);
    meta = try terminal.graphicsMeta();
    const resolved = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(resolved.anchor_row, 5);
    try std.testing.expectEqual(@as(u16, 7), resolved.anchor_col);
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
    try std.testing.expectEqual(@as(u32, 15), placement.source_y);
    try std.testing.expectEqual(@as(u32, 15), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);
}

test "kitty graphics margin line feed clips top from resolved implicit destination truth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 5, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 10);
    try stream.nextSlice("\x1b_Gi=7,s=40,v=30,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;4r\x1b[2;3H\x1b_Ga=p,i=7,p=3,c=3,Y=5\x1b\\");
    try stream.nextSlice("\x1b[4;1H\n");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u32, 7), placement.source_y);
    try std.testing.expectEqual(@as(u32, 23), placement.source_height);
    try std.testing.expectEqual(@as(u32, 0), placement.cell_y_offset);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);
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
    try std.testing.expectEqual(@as(u32, 15), placement.source_height);
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
    try std.testing.expectEqual(@as(u32, 15), placement.source_height);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);
}

test "kitty graphics scroll down lines clips bottom from resolved implicit destination truth" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 5, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 10);
    try stream.nextSlice("\x1b_Gi=7,s=40,v=30,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;4r\x1b[2;3H\x1b_Ga=p,i=7,p=3,c=3,Y=5\x1b\\");
    try stream.nextSlice("\x1b[1T");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 2);
    try std.testing.expectEqual(@as(u32, 0), placement.source_y);
    try std.testing.expectEqual(@as(u32, 19), placement.source_height);
    try std.testing.expectEqual(@as(u32, 5), placement.cell_y_offset);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);
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

test "kitty graphics place resolves implicit grid extent for all c/r cases when cell size is known" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 4, 16, 2);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    terminal.setCellPixelSize(10, 20);
    try stream.nextSlice("\x1b_Gi=7,s=40,v=20,t=d,f=24;AAAA\x1b\\");

    try stream.nextSlice("\x1b_Ga=p,i=7,p=1,X=2,Y=5\x1b\\");
    var placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 5), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);

    try stream.nextSlice("\x1b_Ga=d,i=7,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=2,X=2,Y=5,c=2\x1b\\");
    placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 2), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);

    try stream.nextSlice("\x1b_Ga=d,i=7,p=2\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,X=3,Y=5,r=2\x1b\\");
    placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 9), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);

    try stream.nextSlice("\x1b_Ga=d,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=4,X=3,Y=5,c=2,r=2\x1b\\");
    placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 2), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);
}

test "kitty graphics implicit extent rescales when cell size becomes known later" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=40,v=20,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,X=2,Y=5\x1b\\");

    var placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 1), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 1), placement.effective_rows);

    const fallback_meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 1), fallback_meta.placement_count);

    terminal.setCellPixelSize(10, 20);

    const refreshed_meta = try terminal.graphicsMeta();
    try std.testing.expect(refreshed_meta.publication_seq != fallback_meta.publication_seq);
    try std.testing.expect(refreshed_meta.dirty_generation != fallback_meta.dirty_generation);
    try std.testing.expectError(error.InvalidArgument, terminal.graphicsPlacement(fallback_meta.publication_seq, 0));

    placement = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 5), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), placement.effective_rows);

    const published = (try terminal.graphicsPlacement(refreshed_meta.publication_seq, 0)).?;
    try std.testing.expectEqual(@as(u32, 5), published.effective_columns);
    try std.testing.expectEqual(@as(u32, 2), published.effective_rows);

    const geometry = published.resolveDestGeometry(terminal.screen_state.primary.cellPixelSize()).?;
    try std.testing.expectEqual(@as(u32, 42), geometry.right_px);
    try std.testing.expectEqual(@as(u32, 25), geometry.bottom_px);
}

test "kitty graphics placement geometry falls back to positive grid-local pixels without cell size" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=40,v=20,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3,X=2,Y=5,c=2\x1b\\");

    const placement = terminal.kitty.main.graphics.placementAt(0).?;
    const geometry = placement.resolveDestGeometry(terminal.screen_state.primary.cellPixelSize()).?;
    try std.testing.expectEqual(@as(u32, 2), geometry.left_px);
    try std.testing.expectEqual(@as(u32, 5), geometry.top_px);
    try std.testing.expectEqual(@as(u32, 4), geometry.right_px);
    try std.testing.expectEqual(@as(u32, 6), geometry.bottom_px);
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

test "kitty graphics relative placement resolves parent anchor and does not move cursor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=3,c=4,r=2\x1b\\");
    try stream.nextSlice("\x1b[5;10H\x1b_Ga=p,i=8,p=9,P=7,Q=3,H=2,V=1,c=1,r=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementCount(&terminal));
    const child = KittyState.graphicsPlacementAt(&terminal, 1).?;
    try expectOnScreenRowAnchor(child.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), child.anchor_col);
    try std.testing.expectEqual(@as(u16, 4), terminal.screen_state.activeConst().cursor_row);
    try std.testing.expectEqual(@as(u16, 9), terminal.screen_state.activeConst().cursor_col);
}

test "kitty graphics relative placement resolves virtual parent from live placeholder cell" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 8, 16, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,H=2,V=1,c=1,r=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 0), (try terminal.graphicsMeta()).placement_count);

    terminal.screen_state.active().cells.?[1 * 16 + 3] = Screen.Cell{
        .codepoint = 0x10EEEE,
        .combining_len = 0,
        .attrs = .{
            .fg = Screen.Color.indexed(7),
            .bg = Screen.default_bg,
            .bold = false,
            .dim = false,
            .italic = false,
            .blink = false,
            .blink_fast = false,
            .reverse = false,
            .invisible = false,
            .underline = true,
            .strikethrough = false,
            .underline_style = .straight,
            .underline_color = Screen.Color.indexed(9),
            .protected = false,
            .link_id = 0,
        },
    };
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 2), meta.placement_count);
    const placement = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 5), placement.anchor_col);
}

test "kitty graphics relative placement rejects missing parent image explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,H=2,V=1,c=1,r=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=8,p=3;ENOPARENT:parent image not found\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics relative placement rejects missing parent placement explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,H=2,V=1,c=1,r=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=8,p=3;ENOPARENT:parent placement not found\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics relative placement rejects self-parent explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=1,P=7,Q=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7,p=1;OK\x1b\\\x1b_Gi=7,p=1;EINVAL:placement cannot parent itself\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics virtual placement rejects parent reference explicitly" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,P=7,Q=1,c=1,r=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7,p=9;EINVAL:virtual placement cannot refer to a parent\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.virtualPlacementCount());
}

test "kitty graphics virtual parent anchor keeps row and column from the same matched cell" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 8, 16, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 1, 9, Screen.Color.indexed(7), 9, null, null, null);
    setPlaceholderCell(&terminal, 3, 1, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    const placement = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 9), placement.anchor_col);
}

test "kitty graphics virtual parent anchor matches image id high byte" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 8, 16, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=16777223,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=16777223,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=16777223,Q=9,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 2, 6, Screen.Color.rgbComponents(0, 0, 7), 9, null, null, 0x030D);
    terminal.postApply(true);

    const meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 2), meta.placement_count);
    const placement = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(placement.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 6), placement.anchor_col);
}

test "kitty graphics deleting virtual parent removes descendant placements" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,H=2,V=1,c=1,r=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());

    try stream.nextSlice("\x1b_Ga=d,d=i,i=7,p=9\x1b\\");

    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.placementCount());
    try std.testing.expectEqual(@as(u32, 0), terminal.kitty.main.graphics.virtualPlacementCount());
}

test "kitty graphics Q0 child stays with anonymous physical parent when another anonymous parent is deleted" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b[5;6H\x1b_Ga=p,i=7,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=4,P=7,Q=0,H=2,V=1,c=1,r=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 3), terminal.kitty.main.graphics.placementCount());
    var meta = try terminal.graphicsMeta();
    var child = (try terminal.graphicsPlacement(meta.publication_seq, 2)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), child.anchor_col);

    try stream.nextSlice("\x1b_Ga=d,d=p,x=6,y=5\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), terminal.kitty.main.graphics.placementCount());
    meta = try terminal.graphicsMeta();
    child = (try terminal.graphicsPlacement(meta.publication_seq, 1)).?;
    try std.testing.expectEqual(@as(u32, 8), child.image_id);
    try expectOnScreenRowAnchor(child.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), child.anchor_col);
}

test "kitty graphics Q0 child stays with selected virtual parent when another virtual ref changes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=10,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=0,H=2,V=1,c=1,r=1\x1b\\");

    setPlaceholderCell(&terminal, 1, 2, Screen.Color.indexed(7), 9, null, null, null);
    setPlaceholderCell(&terminal, 4, 5, Screen.Color.indexed(7), 10, null, null, null);
    terminal.postApply(true);
    var meta = try terminal.graphicsMeta();
    var child = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), child.anchor_col);

    try stream.nextSlice("\x1b_Ga=d,d=i,i=7,p=10\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=11,U=1,c=1,r=1\x1b\\");
    setPlaceholderCell(&terminal, 6, 7, Screen.Color.indexed(7), 11, null, null, null);
    terminal.postApply(true);

    meta = try terminal.graphicsMeta();
    child = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 2);
    try std.testing.expectEqual(@as(u16, 4), child.anchor_col);
}

test "kitty graphics updating nonzero parent keeps Q0 child attached to same ref" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=9,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=0,H=2,V=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b[5;6H\x1b_Ga=p,i=7,p=9,c=1,r=1\x1b\\");

    const meta = try terminal.graphicsMeta();
    const child = (try terminal.graphicsPlacement(meta.publication_seq, 1)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 5);
    try std.testing.expectEqual(@as(u16, 7), child.anchor_col);
}

test "kitty graphics nonzero parent conversion preserves Q0 child through both placement kinds" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=9,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=0,H=2,V=1,c=1,r=1\x1b\\");

    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    setPlaceholderCell(&terminal, 3, 4, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);
    var meta = try terminal.graphicsMeta();
    var child = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 4);
    try std.testing.expectEqual(@as(u16, 6), child.anchor_col);

    try stream.nextSlice("\x1b[6;7H\x1b_Ga=p,i=7,p=9,c=1,r=1\x1b\\");
    meta = try terminal.graphicsMeta();
    child = (try terminal.graphicsPlacement(meta.publication_seq, 0)).?;
    try expectOnScreenRowAnchor(child.anchor_row, 6);
    try std.testing.expectEqual(@as(u16, 8), child.anchor_col);
}

test "kitty graphics deleting anonymous parent removes descendants by internal ref" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b[5;6H\x1b_Ga=p,i=7,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=4,P=7,Q=0,H=2,V=1,c=1,r=1\x1b\\");

    try stream.nextSlice("\x1b_Ga=d,d=p,x=3,y=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.placementCount());
    const remaining = terminal.kitty.main.graphics.placementAt(0).?;
    try std.testing.expectEqual(@as(u32, 7), remaining.image_id);
    try expectOnScreenRowAnchor(remaining.anchor_row, 4);
    try std.testing.expectEqual(@as(u16, 5), remaining.anchor_col);
}

test "kitty graphics relative placement cycle is rejected" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=2,P=7,Q=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=1,P=8,Q=2\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7,p=1;OK\x1b\\\x1b_Gi=8,p=2;OK\x1b\\\x1b_Gi=7,p=1;ECYCLE:relative placement cycle\x1b\\", pendingOutput(&terminal));
    const root = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try expectOnScreenRowAnchor(root.anchor_row, 1);
    try std.testing.expectEqual(@as(u16, 2), root.anchor_col);
}

test "kitty graphics relative placement depth bound rejects ninth ancestor" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 12, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    var image_id: u32 = 1;
    while (image_id <= 10) : (image_id += 1) {
        var buf: [64]u8 = undefined;
        const upload = try std.fmt.bufPrint(&buf, "\x1b_Gi={d},s=1,v=1,t=d,f=24;AAAA\x1b\\", .{image_id});
        try stream.nextSlice(upload);
    }

    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=1,p=1\x1b\\");
    image_id = 2;
    while (image_id <= 9) : (image_id += 1) {
        var buf: [96]u8 = undefined;
        const place = try std.fmt.bufPrint(&buf, "\x1b_Ga=p,i={d},p=1,P={d},Q=1\x1b\\", .{ image_id, image_id - 1 });
        try stream.nextSlice(place);
    }

    try std.testing.expectEqual(@as(u32, 9), KittyState.graphicsPlacementCount(&terminal));
    try stream.nextSlice("\x1b_Ga=p,i=10,p=1,P=9,Q=1\x1b\\");
    try std.testing.expectEqual(@as(u32, 9), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expect(std.mem.endsWith(u8, pendingOutput(&terminal), "\x1b_Gi=10,p=1;ETOODEEP:relative placement depth exceeded\x1b\\"));
}

test "kitty graphics relative placement lifetime removes descendant placements without deleting named images" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 8, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=2,P=7,Q=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsPlacementCount(&terminal));

    try stream.nextSlice("\x1b_Ga=d,d=i,i=7,p=1\x1b\\");

    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
}

test "kitty graphics lowercase delete by image id removes placements and keeps image data" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=i,i=7\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 7), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
    try std.testing.expectEqualStrings("AAAA", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics uppercase delete by image id frees only targeted unplaced image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=3\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=I,i=7\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 8), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics uppercase delete by image number targets newest only" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,I=13,p=2\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=N,I=13\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,I=13,p=4\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementAt(&terminal, 0).?.image_id);
    try std.testing.expectEqual(@as(u32, 4), KittyState.graphicsPlacementAt(&terminal, 0).?.placement_id);
}

test "kitty graphics uppercase geometry delete does not sweep unrelated unplaced image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b[2;3H\x1b_Ga=p,i=7,p=1,c=2,r=2\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=P,x=3,y=2\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 8), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics range delete preserves lowercase data and frees uppercase targets" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Gi=9,s=1,v=1,t=d,f=24;CCCC\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=r,x=7,y=8\x1b\\");

    try std.testing.expectEqual(@as(u32, 3), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsPlacementCount(&terminal));

    try stream.nextSlice("\x1b_Ga=p,i=7,p=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=R,x=7,y=8\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 9), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
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

test "kitty graphics image number upload avoids existing explicit image id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=1,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageAt(&terminal, 0).?.image_id);
    try std.testing.expectEqualStrings("AAAA", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageAt(&terminal, 1).?.image_id);
    try std.testing.expectEqual(@as(u32, 13), KittyState.graphicsImageAt(&terminal, 1).?.image_number);
    try std.testing.expectEqualStrings("\x1b_Gi=2,I=13;OK\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics image number upload reuses lowest freed positive id" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=1,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=I,i=1\x1b\\");
    try stream.nextSlice("\x1b_GI=14,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expect(imageIndexById(&terminal.kitty.main.graphics, 1) != null);
    try std.testing.expect(imageIndexById(&terminal.kitty.main.graphics, 2) != null);
    const reused = KittyState.graphicsImageAt(&terminal, imageIndexById(&terminal.kitty.main.graphics, 1).?).?;
    try std.testing.expectEqual(@as(u32, 14), reused.image_number);
    try std.testing.expectEqualStrings("\x1b_Gi=2,I=13;OK\x1b\\\x1b_Gi=1,I=14;OK\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics frame upload by image number targets newest image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,I=13,r=2,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsFrameCount(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 2), frame.image_id);
    try std.testing.expectEqual(@as(u32, 2), frame.frame_number);
    try std.testing.expectEqualStrings("CCCC", frame.base64_payload);
}

test "kitty graphics chunked frame upload by image number captures newest image" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_GI=13,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,I=13,r=2,s=1,v=1,t=d,f=24,m=1;CC\x1b\\");
    try stream.nextSlice("\x1b_GI=99,m=0;CC\x1b\\");

    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsFrameCount(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 2), frame.image_id);
    try std.testing.expectEqualStrings("CCCC", frame.base64_payload);
}

test "kitty graphics frame upload by missing image number replies not found without allocation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Ga=f,I=404,r=2,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqualStrings("\x1b_GI=404;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsFrameCount(&terminal));
}

test "kitty graphics chunked frame upload by missing image number replies not found without allocation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Ga=f,I=404,r=2,s=1,v=1,t=d,f=24,m=1;CC\x1b\\");

    try std.testing.expectEqualStrings("\x1b_GI=404;ENOENT:image not found\x1b\\", pendingOutput(&terminal));
    try std.testing.expect(terminal.kitty.main.graphics.upload == null);
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsFrameCount(&terminal));
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

test "kitty graphics delete selectors remove resolved virtual children without deleting prototypes" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCellsAndHistory(allocator, 8, 16, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Gi=8,s=1,v=1,t=d,f=24;BBBB\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=8,p=3,P=7,Q=9,c=1,r=1\x1b\\");
    setPlaceholderCell(&terminal, 2, 5, Screen.Color.indexed(7), 9, null, null, null);
    terminal.postApply(true);

    try std.testing.expectEqual(@as(u32, 2), (try terminal.graphicsMeta()).placement_count);
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());

    try stream.nextSlice("\x1b_Ga=d,d=p,x=6,y=3\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), (try terminal.graphicsMeta()).placement_count);
    try std.testing.expectEqual(@as(u32, 1), terminal.kitty.main.graphics.virtualPlacementCount());
}

test "kitty graphics animation frame upload stores frame metadata" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsFrameCount(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 7), frame.image_id);
    try std.testing.expectEqual(@as(u32, 2), frame.frame_number);
    try std.testing.expectEqualStrings("CCCC", frame.base64_payload);
}

test "kitty graphics new animation frame without z gets default gap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;CCCC\x1b\\");

    try std.testing.expectEqual(@as(i32, 40), KittyState.graphicsFrameAt(&terminal, 0).?.gap);
}

test "kitty graphics new animation frame with z zero gets default gap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=0;CCCC\x1b\\");

    try std.testing.expectEqual(@as(i32, 40), KittyState.graphicsFrameAt(&terminal, 0).?.gap);
}

test "kitty graphics new animation frame with negative z gets gapless frame" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=-1;CCCC\x1b\\");

    try std.testing.expectEqual(@as(i32, 0), KittyState.graphicsFrameAt(&terminal, 0).?.gap);
}

test "kitty graphics editing animation frame without z preserves old gap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=9;CCCC\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;DDDD\x1b\\");

    try std.testing.expectEqual(@as(i32, 9), KittyState.graphicsFrameAt(&terminal, 0).?.gap);
}

test "kitty graphics editing animation frame with z zero preserves old gap" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=9;CCCC\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=0;DDDD\x1b\\");

    try std.testing.expectEqual(@as(i32, 9), KittyState.graphicsFrameAt(&terminal, 0).?.gap);
}

test "kitty graphics editing animation frame with negative z becomes gapless" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=9;CCCC\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=-1;DDDD\x1b\\");

    try std.testing.expectEqual(@as(i32, 0), KittyState.graphicsFrameAt(&terminal, 0).?.gap);
}

test "kitty graphics deleting root frame promotes first extra frame" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24,z=43;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=24,z=40;R0hJ\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");

    try stream.nextSlice("\x1b_Ga=d,d=f,i=7,r=1\x1b\\");

    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 1), image.current_frame_number);
    try std.testing.expectEqual(@as(i32, 43), image.root_frame_gap);
    try std.testing.expectEqualStrings("REVG", image.base64_payload);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsFrameCount(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 2), frame.frame_number);
    try std.testing.expectEqualStrings("R0hJ", frame.base64_payload);
}

test "kitty graphics deleting middle extra frame preserves order and current publication" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=24;R0hJ\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=4,s=1,v=1,t=d,f=24;SktM\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,c=4\x1b\\");

    try stream.nextSlice("\x1b_Ga=d,d=f,i=7,r=3\x1b\\");

    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 3), image.current_frame_number);
    try std.testing.expectEqualStrings("SktM", image.base64_payload);
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsFrameCount(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsFrameAt(&terminal, 0).?.frame_number);
    try std.testing.expectEqualStrings("REVG", KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);
    try std.testing.expectEqual(@as(u32, 3), KittyState.graphicsFrameAt(&terminal, 1).?.frame_number);
    try std.testing.expectEqualStrings("SktM", KittyState.graphicsFrameAt(&terminal, 1).?.base64_payload);
}

test "kitty graphics lowercase frame delete without r promotes until root remains" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=24;R0hJ\x1b\\");

    try stream.nextSlice("\x1b_Ga=d,d=f,i=7\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=f,i=7\x1b\\");
    try stream.nextSlice("\x1b_Ga=d,d=f,i=7\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsFrameCount(&terminal));
    try std.testing.expectEqualStrings("R0hJ", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics uppercase frame delete without extra frames deletes image data" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");

    try stream.nextSlice("\x1b_Ga=d,d=F,i=7\x1b\\");

    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsFrameCount(&terminal));
}

test "kitty graphics too-large frame delete normalizes to last frame" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=24;R0hJ\x1b\\");

    try stream.nextSlice("\x1b_Ga=d,d=f,i=7,r=99\x1b\\");

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsFrameCount(&terminal));
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsFrameAt(&terminal, 0).?.frame_number);
    try std.testing.expectEqualStrings("REVG", KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics compose root frame into destination frame stores composed payload" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=2,v=2,t=d,f=32;CgAA/xQAAP8eAAD/KAAA/w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=2,v=2,t=d,f=32;AQEB/wICAv8DAwP/BAQE/w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=c,i=7,r=1,c=2,C=1\x1b\\");

    try std.testing.expectEqualStrings("\x1b_Gi=7;OK\x1b\\", pendingOutput(&terminal));
    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u16, 32), frame.format);
    try std.testing.expectEqual(@as(u32, 2), frame.width);
    try std.testing.expectEqual(@as(u32, 2), frame.height);
    try std.testing.expectEqualStrings("CgAA/xQAAP8eAAD/KAAA/w==", frame.base64_payload);
}

test "kitty graphics compose sub-rectangle uses X Y source and x y destination offsets" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=3,v=3,t=d,f=32;AQAA/wIAAP8DAAD/BAAA/wUAAP8GAAD/BwAA/wgAAP8JAAD/\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=3,v=3,t=d,f=32;CgAA/woAAP8KAAD/CgAA/woAAP8KAAD/CgAA/woAAP8KAAD/\x1b\\");
    try stream.nextSlice("\x1b_Ga=c,i=7,r=1,c=2,X=1,Y=1,x=1,y=1,w=2,h=2,C=1\x1b\\");

    const frame = KittyState.graphicsFrameAt(&terminal, 0).?;
    try std.testing.expectEqualStrings("CgAA/woAAP8KAAD/CgAA/wUAAP8GAAD/CgAA/wgAAP8JAAD/", frame.base64_payload);
}

test "kitty graphics compose replacement differs from default alpha blending" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=32;AAD//w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=32;/wAAgA==\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=32;AAD//w==\x1b\\");

    try stream.nextSlice("\x1b_Ga=c,i=7,r=2,c=3\x1b\\");
    try std.testing.expectEqualStrings("gAB//w==", KittyState.graphicsFrameAt(&terminal, 1).?.base64_payload);

    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=32;AAD//w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=c,i=7,r=2,c=3,C=1\x1b\\");
    try std.testing.expectEqualStrings("/wAAgA==", KittyState.graphicsFrameAt(&terminal, 1).?.base64_payload);
}

test "kitty graphics compose missing image source and destination fail without mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Ga=c,i=404,r=1,c=2\x1b\\");
    try std.testing.expectEqual(@as(u32, 0), KittyState.graphicsImageCount(&terminal));

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=32;AAD//w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=32;/wAAgA==\x1b\\");
    const original = KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload;
    try stream.nextSlice("\x1b_Ga=c,i=7,r=3,c=2\x1b\\");
    try std.testing.expectEqualStrings(original, KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);
    try stream.nextSlice("\x1b_Ga=c,i=7,r=1,c=3\x1b\\");
    try std.testing.expectEqualStrings(original, KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);

    try std.testing.expectEqualStrings("\x1b_Gi=404;ENOENT:image not found\x1b\\\x1b_Gi=7;ENOENT:source frame not found\x1b\\\x1b_Gi=7;ENOENT:destination frame not found\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics compose out-of-bounds and same-frame overlap fail without mutation" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=3,v=3,t=d,f=32;AQAA/wIAAP8DAAD/BAAA/wUAAP8GAAD/BwAA/wgAAP8JAAD/\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=3,v=3,t=d,f=32;CgAA/woAAP8KAAD/CgAA/woAAP8KAAD/CgAA/woAAP8KAAD/\x1b\\");
    const original = KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload;

    try stream.nextSlice("\x1b_Ga=c,i=7,r=1,c=2,X=2,Y=0,w=2,h=1\x1b\\");
    try std.testing.expectEqualStrings(original, KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);
    try stream.nextSlice("\x1b_Ga=c,i=7,r=1,c=2,x=2,y=0,w=2,h=1\x1b\\");
    try std.testing.expectEqualStrings(original, KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);
    try stream.nextSlice("\x1b_Ga=c,i=7,r=2,c=2,X=0,Y=0,x=1,y=1,w=2,h=2\x1b\\");
    try std.testing.expectEqualStrings(original, KittyState.graphicsFrameAt(&terminal, 0).?.base64_payload);

    try std.testing.expectEqualStrings("\x1b_Gi=7;EINVAL:compose rectangle out of bounds\x1b\\\x1b_Gi=7;EINVAL:compose rectangle out of bounds\x1b\\\x1b_Gi=7;EINVAL:compose rectangles overlap\x1b\\", pendingOutput(&terminal));
}

test "kitty graphics compose into current destination frame refreshes publication" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=32;AAD//w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=32;AAD//w==\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=3,s=1,v=1,t=d,f=32;/wAAgA==\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");
    try std.testing.expectEqualStrings("AAD//w==", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);

    try stream.nextSlice("\x1b_Ga=c,i=7,r=3,c=2,C=1\x1b\\");

    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 2), image.current_frame_number);
    try std.testing.expectEqualStrings("/wAAgA==", image.base64_payload);
}

test "kitty graphics client-driven current frame republishes selected raw frame" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;REVG\x1b\\");

    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);

    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");

    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 2), image.current_frame_number);
    try std.testing.expectEqualStrings("REVG", image.base64_payload);
}

test "kitty graphics selecting current frame twice stays publication-noop" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=24;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");

    const first = try terminal.graphicsMeta();
    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");
    const second = try terminal.graphicsMeta();

    try std.testing.expectEqual(first.publication_seq, second.publication_seq);
}

test "kitty graphics client-driven current png frame republishes normalized rgba" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    const upload = try std.fmt.allocPrint(allocator, "\x1b_Ga=f,i=7,r=2,s=1,v=1,t=d,f=100;{s}\x1b\\", .{png_rgba_11223344});
    defer allocator.free(upload);
    try stream.nextSlice(upload);
    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");

    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u16, 32), image.format);
    try std.testing.expectEqual(@as(u32, 1), image.width);
    try std.testing.expectEqual(@as(u32, 1), image.height);
    try std.testing.expectEqualStrings("ESIzRA==", image.base64_payload);
}

test "kitty graphics selected raw frame over png root republishes normalized rgba" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const root = try std.fmt.allocPrint(allocator, "\x1b_Gi=7,s=1,v=1,t=d,f=100;{s}\x1b\\", .{png_rgba_11223344});
    defer allocator.free(root);
    try stream.nextSlice(root);
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,c=1,t=d,f=32;/wAAgA==\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,c=2\x1b\\");

    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u16, 32), image.format);
    try std.testing.expectEqualStrings("zQcLog==", image.base64_payload);
}

test "kitty graphics runtime obligation starts due and arms first frame deadline" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,r=1,z=7\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,z=5,t=d,f=24;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,s=3,v=1\x1b\\");

    const due = terminal.runtimeObligation(100);
    try std.testing.expect(due.pending_now);
    try std.testing.expectEqual(@as(u64, 0), due.deadline_ns);

    const first = try terminal.progressRuntime(100);
    try std.testing.expect(!first.state_changed);
    try std.testing.expect(!first.obligation.pending_now);
    try std.testing.expectEqual(@as(u64, 100 + 7 * std.time.ns_per_ms), first.obligation.deadline_ns);
}

test "kitty graphics runtime progress advances timed animation frames autonomously" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;QUJD\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,r=1,z=7\x1b\\");
    try stream.nextSlice("\x1b_Ga=f,i=7,r=2,s=1,v=1,z=5,t=d,f=24;REVG\x1b\\");
    try stream.nextSlice("\x1b_Ga=a,i=7,s=3,v=1\x1b\\");

    _ = try terminal.progressRuntime(100);
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);

    const second = try terminal.progressRuntime(100 + 7 * std.time.ns_per_ms);
    try std.testing.expect(second.state_changed);
    try std.testing.expectEqual(@as(u32, 2), KittyState.graphicsImageAt(&terminal, 0).?.current_frame_number);
    try std.testing.expectEqualStrings("REVG", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
    try std.testing.expectEqual(@as(u64, 100 + 12 * std.time.ns_per_ms), second.obligation.deadline_ns);

    const third = try terminal.progressRuntime(100 + 12 * std.time.ns_per_ms);
    try std.testing.expect(third.state_changed);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageAt(&terminal, 0).?.current_frame_number);
    try std.testing.expectEqualStrings("QUJD", KittyState.graphicsImageAt(&terminal, 0).?.base64_payload);
}

test "kitty graphics quota evicts unplaced image before failing or touching placed image" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    try appendTestImage(&state, allocator, 1, Graphics.retained_payload_max_bytes - 4);
    try appendTestPlacement(&state, allocator, 1);
    try appendTestImage(&state, allocator, 2, 4);

    _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 3,
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
        .payload = "BBBB",
    });

    try std.testing.expect(imageIndexById(&state, 1) != null);
    try std.testing.expect(imageIndexById(&state, 2) == null);
    try std.testing.expect(imageIndexById(&state, 3) != null);
    try std.testing.expectEqual(@as(u32, 1), state.placementCount());
    try std.testing.expectEqual(@as(u32, 1), state.placementAt(0).?.image_id);
}

test "kitty graphics quota preserves placed images and fails when only placed images fit" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    try appendTestImage(&state, allocator, 1, Graphics.retained_payload_max_bytes);
    try appendTestPlacement(&state, allocator, 1);

    try std.testing.expectError(error.ConsequenceLimit, state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 2,
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
        .payload = "B",
    }));

    try std.testing.expect(imageIndexById(&state, 1) != null);
    try std.testing.expectEqual(@as(u32, 1), state.imageCount());
    try std.testing.expectEqual(@as(u32, 1), state.placementCount());
}

test "kitty graphics quota preserves virtual placement images" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    try appendTestImage(&state, allocator, 1, Graphics.retained_payload_max_bytes);
    try appendTestVirtualPlacement(&state, allocator, 1);

    try std.testing.expectError(error.ConsequenceLimit, state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 2,
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
        .payload = "B",
    }));

    try std.testing.expect(imageIndexById(&state, 1) != null);
    try std.testing.expectEqual(@as(u32, 1), state.imageCount());
    try std.testing.expectEqual(@as(u32, 1), state.virtualPlacementCount());
}

test "kitty graphics quota replacement counts bytes freed by same image id" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    try appendTestImage(&state, allocator, 7, Graphics.retained_payload_max_bytes);
    const replacement = state.images.items[0].base64_payload;

    _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 7,
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
        .payload = replacement,
    });

    try std.testing.expectEqual(@as(u32, 1), state.imageCount());
    try std.testing.expectEqual(@as(u32, 7), state.imageAt(0).?.image_id);
    try std.testing.expectEqual(@as(usize, Graphics.retained_payload_max_bytes), state.imageAt(0).?.base64_payload.len);
}

test "kitty graphics quota replacement clears frames and current override" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    try appendTestImage(&state, allocator, 7, Graphics.retained_payload_max_bytes - 8);
    state.images.items[0].current_frame_number = 2;
    state.images.items[0].current_override_payload = try retainedPayload(allocator, 4, 'O');
    try state.frames.append(allocator, .{
        .frame_id = 1,
        .image_id = 7,
        .frame_number = 2,
        .format = 24,
        .width = 1,
        .height = 1,
        .x = 0,
        .y = 0,
        .uses_root_base = false,
        .base_frame_id = 0,
        .compose_mode = 0,
        .background_rgba = 0,
        .gap = 0,
        .base64_payload = try retainedPayload(allocator, 4, 'F'),
    });

    _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 7,
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
        .payload = "BBBBBBBB",
    });

    try std.testing.expectEqual(@as(u32, 1), state.imageCount());
    try std.testing.expectEqual(@as(u32, 7), state.imageAt(0).?.image_id);
    try std.testing.expectEqualStrings("BBBBBBBB", state.imageAt(0).?.base64_payload);
    try std.testing.expectEqual(@as(?[]u8, null), state.imageAt(0).?.current_override_payload);
    try std.testing.expectEqual(@as(u32, 0), state.frameCount());
}

test "kitty graphics quota eviction removes unplaced image frames and current override" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    try appendTestImage(&state, allocator, 1, Graphics.retained_payload_max_bytes - 12);
    try appendTestPlacement(&state, allocator, 1);
    try appendTestImage(&state, allocator, 2, 4);
    state.images.items[1].current_frame_number = 2;
    state.images.items[1].current_override_payload = try retainedPayload(allocator, 4, 'O');
    try state.frames.append(allocator, .{
        .frame_id = 1,
        .image_id = 2,
        .frame_number = 2,
        .format = 24,
        .width = 1,
        .height = 1,
        .x = 0,
        .y = 0,
        .uses_root_base = false,
        .base_frame_id = 0,
        .compose_mode = 0,
        .background_rgba = 0,
        .gap = 0,
        .base64_payload = try retainedPayload(allocator, 4, 'F'),
    });

    _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 3,
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
        .payload = "BBBBBBBBBBBB",
    });

    try std.testing.expect(imageIndexById(&state, 2) == null);
    try std.testing.expectEqual(@as(u32, 0), state.frameCount());
    try std.testing.expect(imageIndexById(&state, 1) != null);
    try std.testing.expect(imageIndexById(&state, 3) != null);
}

test "kitty graphics image count cap is explicit" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    var image_id: u32 = 1;
    while (image_id <= Graphics.image_max_count) : (image_id += 1) {
        _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
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
    try std.testing.expectError(error.ConsequenceLimit, state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
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

test "kitty graphics parser-limit chunked upload failure leaves terminal deinit-safe" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 3, 16);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    var first = std.ArrayList(u8).empty;
    defer first.deinit(allocator);
    try first.appendSlice(allocator, "\x1b_Gi=7,s=1,v=1365,t=d,f=24,m=1;");
    try first.appendNTimes(allocator, 'A', 4095);
    try first.appendSlice(allocator, "\x1b\\");

    var continuation = std.ArrayList(u8).empty;
    defer continuation.deinit(allocator);
    try continuation.appendSlice(allocator, "\x1b_Gm=1;");
    try continuation.appendNTimes(allocator, 'A', 4095);
    try continuation.appendSlice(allocator, "\x1b\\");

    try stream.nextSlice(first.items);
    while (true) {
        stream.nextSlice(continuation.items) catch |err| {
            try std.testing.expectEqual(error.ConsequenceLimit, err);
            break;
        };
    }

    try std.testing.expect(terminal.kitty.main.graphics.upload == null);
}

test "kitty graphics direct png upload accepts howl app icon replay" {
    const allocator = std.testing.allocator;
    const io = std.Io.Threaded.global_single_threaded.io();
    const png_bytes = try std.Io.Dir.cwd().readFileAlloc(io, howl_app_icon_rel_path, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(png_bytes);

    const encoded = try base64Owned(allocator, png_bytes);
    defer allocator.free(encoded);

    var terminal = try Terminal.initWithCells(allocator, 12, 80);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    const chunk_len: usize = 4096;
    var offset: usize = 0;
    while (offset < encoded.len) : (offset += chunk_len) {
        const end = @min(offset + chunk_len, encoded.len);
        const chunk = encoded[offset..end];
        const more: u8 = if (end < encoded.len) 1 else 0;

        var seq = std.ArrayList(u8).empty;
        defer seq.deinit(allocator);
        var control_buf: [64]u8 = undefined;
        if (offset == 0) {
            const control = try std.fmt.bufPrint(control_buf[0..], "\x1b_Gi=4242,f=100,t=d,a=T,c=8,r=4,m={d};", .{more});
            try seq.appendSlice(allocator, control);
        } else {
            const control = try std.fmt.bufPrint(control_buf[0..], "\x1b_Gm={d};", .{more});
            try seq.appendSlice(allocator, control);
        }
        try seq.appendSlice(allocator, chunk);
        try seq.appendSlice(allocator, "\x1b\\");
        try stream.nextSlice(seq.items);
    }

    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsImageCount(&terminal));
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
    const image = KittyState.graphicsImageAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 4242), image.image_id);
    try std.testing.expectEqual(@as(u16, 100), image.format);

    const placement = KittyState.graphicsPlacementAt(&terminal, 0).?;
    try std.testing.expectEqual(@as(u32, 8), placement.effective_columns);
    try std.testing.expectEqual(@as(u32, 4), placement.effective_rows);

    const fallback_meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 1), fallback_meta.placement_count);

    var geometry = placement.resolveDestGeometry(terminal.screen_state.primary.cellPixelSize()).?;
    try std.testing.expectEqual(@as(u32, 0), geometry.left_px);
    try std.testing.expectEqual(@as(u32, 0), geometry.top_px);
    try std.testing.expectEqual(@as(u32, 8), geometry.right_px);
    try std.testing.expectEqual(@as(u32, 4), geometry.bottom_px);

    terminal.setCellPixelSize(10, 20);

    const refreshed_meta = try terminal.graphicsMeta();
    try std.testing.expect(refreshed_meta.publication_seq != fallback_meta.publication_seq);
    try std.testing.expect(refreshed_meta.dirty_generation != fallback_meta.dirty_generation);
    try std.testing.expectError(error.InvalidArgument, terminal.graphicsPlacement(fallback_meta.publication_seq, 0));

    const published = (try terminal.graphicsPlacement(refreshed_meta.publication_seq, 0)).?;
    geometry = published.resolveDestGeometry(terminal.screen_state.primary.cellPixelSize()).?;
    try std.testing.expectEqual(@as(u32, 80), geometry.right_px);
    try std.testing.expectEqual(@as(u32, 80), geometry.bottom_px);
}

test "kitty graphics a=T cursor move leaves the placed image rows" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 12, 80);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24,a=T,c=8,r=4;AAAA\x1b\\");

    const active = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 8), active.cursor_col);
    try std.testing.expectEqual(@as(u16, 4), active.cursor_row);
}

test "kitty graphics placement accepts C=1 and leaves cursor untouched" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 12, 80);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,C=1\x1b\\");

    const active = terminal.screen_state.activeConst();
    try std.testing.expectEqual(@as(u16, 0), active.cursor_col);
    try std.testing.expectEqual(@as(u16, 0), active.cursor_row);
    try std.testing.expectEqual(@as(u32, 1), KittyState.graphicsPlacementCount(&terminal));
}

test "kitty graphics placeholder-run export rejects stale publication" {
    const allocator = std.testing.allocator;
    var terminal = try Terminal.initWithCells(allocator, 4, 8);
    defer terminal.deinit();
    var stream = try StreamHarness.init(&terminal);
    defer stream.deinit();

    try stream.nextSlice("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    try stream.nextSlice("\x1b_Ga=p,i=7,p=9,U=1,c=1,r=1\x1b\\");
    setPlaceholderCell(&terminal, 0, 0, Screen.Color.indexed(7), 9, 0x0305, 0x0305, null);
    terminal.postApply(true);

    const fallback_meta = try terminal.graphicsMeta();
    try std.testing.expectEqual(@as(u32, 0), fallback_meta.placeholder_run_count);
    try std.testing.expectEqual(@as(u32, 1), try terminal.graphicsPlaceholderRunProofCount(fallback_meta.publication_seq));

    try stream.nextSlice("\x1b[?1049h");

    try std.testing.expectError(error.InvalidArgument, terminal.graphicsPlaceholderRunProof(fallback_meta.publication_seq, 0));
}

test "kitty graphics frame count cap is explicit" {
    const allocator = std.testing.allocator;
    var state: Graphics.State = .{};
    defer state.deinit(allocator);
    const screen = Screen.init(24, 80);
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);
    var encode_buf: [128]u8 = undefined;

    _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 't',
        .image_id = 7,
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

    var frame_number: u32 = 2;
    while (frame_number <= Graphics.frame_max_count + 1) : (frame_number += 1) {
        _ = try state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
            .action = 'f',
            .image_id = 7,
            .image_number = 0,
            .placement_id = 0,
            .edit_frame_number = frame_number,
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
    try std.testing.expectError(error.ConsequenceLimit, state.handle(allocator, &screen, .{ .row = 0, .col = 0, .screen_rows = 24 }, null, &output, encode_buf[0..], .{
        .action = 'f',
        .image_id = 7,
        .image_number = 0,
        .placement_id = 0,
        .edit_frame_number = Graphics.frame_max_count + 2,
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
