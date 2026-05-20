const std = @import("std");
const vocabulary = @import("../action/vocabulary.zig");

const KittyGraphicsCommand = vocabulary.KittyGraphicsCommand;

pub const RenderCursorView = struct {
    row: u16,
    col: u16,
};

pub const Count = u32;
pub const Index = u32;

pub const Image = struct {
    image_id: u32,
    image_number: u32,
    format: u16,
    width: u32,
    height: u32,
    base64_payload: []u8,
};

pub const Placement = struct {
    image_id: u32,
    placement_id: u32,
    row: u16,
    col: u16,
    columns: u32,
    rows: u32,
    z_index: i32,
};

pub const Frame = struct {
    image_id: u32,
    frame_number: u32,
    format: u16,
    width: u32,
    height: u32,
    base64_payload: []u8,
};

pub const Upload = struct {
    image_id: u32,
    image_number: u32,
    action: u8,
    format: u16,
    width: u32,
    height: u32,
    frame_number: u32,
    data: std.ArrayList(u8),
};

pub const State = struct {
    images: std.ArrayList(Image) = .empty,
    placements: std.ArrayList(Placement) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    upload: ?Upload = null,
    next_image_id: u32 = 1,

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        for (self.images.items) |image| allocator.free(image.base64_payload);
        self.images.deinit(allocator);
        self.placements.deinit(allocator);
        for (self.frames.items) |frame| allocator.free(frame.base64_payload);
        self.frames.deinit(allocator);
        if (self.upload) |*upload| upload.data.deinit(allocator);
    }

    pub fn imageCount(self: *const State) Count {
        return countForLen(self.images.items.len);
    }

    pub fn imageAt(self: *const State, idx: Index) ?Image {
        if (idx >= self.imageCount()) return null;
        return self.images.items[listIndex(idx)];
    }

    pub fn placementCount(self: *const State) Count {
        return countForLen(self.placements.items.len);
    }

    pub fn placementAt(self: *const State, idx: Index) ?Placement {
        if (idx >= self.placementCount()) return null;
        return self.placements.items[listIndex(idx)];
    }

    pub fn frameCount(self: *const State) Count {
        return countForLen(self.frames.items.len);
    }

    pub fn frameAt(self: *const State, idx: Index) ?Frame {
        if (idx >= self.frameCount()) return null;
        return self.frames.items[listIndex(idx)];
    }

    pub fn handle(self: *State, allocator: std.mem.Allocator, render_view: RenderCursorView, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) void {
        if (cmd.action == 'q') {
            if (!cmd.quiet) appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:kitty graphics rendering unsupported");
            return;
        }
        if (cmd.action == 'p') {
            self.placeImage(allocator, render_view, output, encode_buf, cmd);
            return;
        }
        if (cmd.action == 'd') {
            self.delete(allocator, render_view, cmd);
            return;
        }
        if (cmd.action == 'f') {
            self.captureUpload(allocator, output, encode_buf, cmd);
            return;
        }
        self.captureUpload(allocator, output, encode_buf, cmd);
    }

    fn placeImage(self: *State, allocator: std.mem.Allocator, render_view: RenderCursorView, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) void {
        const image_id = self.resolveImageId(cmd) orelse {
            if (!cmd.quiet) appendReply(allocator, output, encode_buf, cmd.image_id, "ENOENT:image not found");
            return;
        };
        self.placements.append(allocator, .{
            .image_id = image_id,
            .placement_id = cmd.placement_id,
            .row = render_view.row,
            .col = render_view.col,
            .columns = cmd.columns,
            .rows = cmd.rows,
            .z_index = cmd.z,
        }) catch return;
        if (!cmd.quiet) appendReply(allocator, output, encode_buf, image_id, "OK");
    }

    fn delete(self: *State, allocator: std.mem.Allocator, render_view: RenderCursorView, cmd: KittyGraphicsCommand) void {
        self.abortUpload(allocator);
        switch (cmd.delete_target) {
            0, 'a', 'A' => {
                self.placements.clearRetainingCapacity();
                if (cmd.delete_target == 'A') self.deleteUnplacedImages(allocator);
            },
            'i', 'I' => if (self.resolveImageId(cmd)) |image_id| {
                if (cmd.placement_id != 0) self.deletePlacement(image_id, cmd.placement_id) else self.deleteImage(allocator, image_id);
            },
            'n', 'N' => if (self.findNewestImageByNumber(cmd.image_number)) |idx| {
                const image_id = self.images.items[listIndex(idx)].image_id;
                if (cmd.placement_id != 0) self.deletePlacement(image_id, cmd.placement_id) else self.deleteImage(allocator, image_id);
            },
            'c', 'C' => {
                self.deletePlacementsAt(render_view.col + 1, render_view.row + 1, null);
                if (cmd.delete_target == 'C') self.deleteUnplacedImages(allocator);
            },
            'p', 'P' => {
                self.deletePlacementsAt(cmd.x, cmd.y, null);
                if (cmd.delete_target == 'P') self.deleteUnplacedImages(allocator);
            },
            'q', 'Q' => {
                self.deletePlacementsAt(cmd.x, cmd.y, cmd.z);
                if (cmd.delete_target == 'Q') self.deleteUnplacedImages(allocator);
            },
            'r', 'R' => self.deleteImagesInRange(allocator, cmd.x, cmd.y),
            'x', 'X' => {
                self.deletePlacementsInColumn(cmd.x);
                if (cmd.delete_target == 'X') self.deleteUnplacedImages(allocator);
            },
            'y', 'Y' => {
                self.deletePlacementsInRow(cmd.y);
                if (cmd.delete_target == 'Y') self.deleteUnplacedImages(allocator);
            },
            'z', 'Z' => {
                self.deletePlacementsByZ(cmd.z);
                if (cmd.delete_target == 'Z') self.deleteUnplacedImages(allocator);
            },
            'f', 'F' => self.deleteFrames(allocator, cmd),
            else => {},
        }
    }

    fn captureUpload(self: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) void {
        if (cmd.medium != 'd') return;
        if (cmd.action != 't' and cmd.action != 'T' and cmd.action != 'f') return;
        if (cmd.more_chunks) {
            self.appendUploadChunk(allocator, output, encode_buf, cmd, true);
            return;
        }
        if (self.upload != null) {
            self.appendUploadChunk(allocator, output, encode_buf, cmd, false);
        } else {
            self.storePayload(allocator, output, encode_buf, cmd, cmd.payload);
        }
    }

    fn appendUploadChunk(self: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand, more: bool) void {
        if (self.upload == null) {
            const image_id = self.imageIdForUpload(cmd);
            self.upload = .{
                .image_id = image_id,
                .image_number = cmd.image_number,
                .action = cmd.action,
                .format = cmd.format,
                .width = cmd.width,
                .height = cmd.height,
                .frame_number = cmd.placement_id,
                .data = std.ArrayList(u8).empty,
            };
        }
        if (self.upload) |*upload| {
            upload.data.appendSlice(allocator, cmd.payload) catch return;
            if (more) return;
            const image_id = upload.image_id;
            const image_number = upload.image_number;
            const action = upload.action;
            const format = upload.format;
            const width = upload.width;
            const height = upload.height;
            const frame_number = upload.frame_number;
            const owned = upload.data.toOwnedSlice(allocator) catch return;
            if (action == 'f') {
                self.storeFrameOwned(allocator, image_id, frame_number, format, width, height, owned);
            } else {
                self.storeImageOwned(allocator, image_id, image_number, format, width, height, owned);
                if (image_number != 0 and !cmd.quiet) appendNumberReply(allocator, output, encode_buf, image_id, image_number, "OK");
            }
            self.upload = null;
        }
    }

    fn storePayload(self: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand, payload: []const u8) void {
        const owned = allocator.dupe(u8, payload) catch return;
        const image_id = self.imageIdForUpload(cmd);
        if (cmd.action == 'f') {
            self.storeFrameOwned(allocator, image_id, cmd.placement_id, cmd.format, cmd.width, cmd.height, owned);
        } else {
            self.storeImageOwned(allocator, image_id, cmd.image_number, cmd.format, cmd.width, cmd.height, owned);
            if (cmd.image_number != 0 and !cmd.quiet) appendNumberReply(allocator, output, encode_buf, image_id, cmd.image_number, "OK");
        }
    }

    fn imageIdForUpload(self: *State, cmd: KittyGraphicsCommand) u32 {
        if (cmd.image_id != 0) return cmd.image_id;
        if (cmd.image_number == 0) return 0;
        const image_id = self.next_image_id;
        self.next_image_id +%= 1;
        if (self.next_image_id == 0) self.next_image_id = 1;
        return image_id;
    }

    fn storeImageOwned(self: *State, allocator: std.mem.Allocator, image_id: u32, image_number: u32, format: u16, width: u32, height: u32, owned: []u8) void {
        const image = Image{ .image_id = image_id, .image_number = image_number, .format = format, .width = width, .height = height, .base64_payload = owned };
        if (image_id != 0) self.deleteImage(allocator, image_id);
        self.images.append(allocator, image) catch allocator.free(owned);
    }

    fn storeFrameOwned(self: *State, allocator: std.mem.Allocator, image_id: u32, frame_number: u32, format: u16, width: u32, height: u32, owned: []u8) void {
        const frame = Frame{ .image_id = image_id, .frame_number = frame_number, .format = format, .width = width, .height = height, .base64_payload = owned };
        self.frames.append(allocator, frame) catch allocator.free(owned);
    }

    fn findImage(self: *const State, image_id: u32) ?Index {
        for (self.images.items, 0..) |image, idx| {
            if (image.image_id == image_id) return @intCast(idx);
        }
        return null;
    }

    fn findNewestImageByNumber(self: *const State, image_number: u32) ?Index {
        if (image_number == 0) return null;
        var idx = self.images.items.len;
        while (idx > 0) {
            idx -= 1;
            if (self.images.items[idx].image_number == image_number) return @intCast(idx);
        }
        return null;
    }

    fn resolveImageId(self: *const State, cmd: KittyGraphicsCommand) ?u32 {
        if (cmd.image_id != 0 and cmd.image_number != 0) return null;
        if (cmd.image_id != 0) return if (self.findImage(cmd.image_id) != null) cmd.image_id else null;
        if (cmd.image_number != 0) {
            const idx = self.findNewestImageByNumber(cmd.image_number) orelse return null;
            return self.images.items[listIndex(idx)].image_id;
        }
        return null;
    }

    fn abortUpload(self: *State, allocator: std.mem.Allocator) void {
        if (self.upload) |*upload| upload.data.deinit(allocator);
        self.upload = null;
    }

    fn deleteImage(self: *State, allocator: std.mem.Allocator, image_id: u32) void {
        var idx: Index = 0;
        while (idx < self.imageCount()) {
            if (self.images.items[listIndex(idx)].image_id == image_id) {
                allocator.free(self.images.items[listIndex(idx)].base64_payload);
                _ = self.images.swapRemove(listIndex(idx));
            } else idx += 1;
        }
        idx = 0;
        while (idx < self.placementCount()) {
            if (self.placements.items[listIndex(idx)].image_id == image_id) _ = self.placements.swapRemove(listIndex(idx)) else idx += 1;
        }
        idx = 0;
        while (idx < self.frameCount()) {
            if (self.frames.items[listIndex(idx)].image_id == image_id) {
                allocator.free(self.frames.items[listIndex(idx)].base64_payload);
                _ = self.frames.swapRemove(listIndex(idx));
            } else idx += 1;
        }
    }

    fn deletePlacement(self: *State, image_id: u32, placement_id: u32) void {
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const placement = self.placements.items[listIndex(idx)];
            if (placement.image_id == image_id and placement.placement_id == placement_id) _ = self.placements.swapRemove(listIndex(idx)) else idx += 1;
        }
    }

    fn deletePlacementsAt(self: *State, x: u32, y: u32, z: ?i32) void {
        if (x == 0 or y == 0) return;
        const col = x - 1;
        const row = y - 1;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const p = self.placements.items[listIndex(idx)];
            const cols = @max(p.columns, 1);
            const rows = @max(p.rows, 1);
            const intersects = col >= p.col and col < p.col + cols and row >= p.row and row < p.row + rows and (z == null or p.z_index == z.?);
            if (intersects) _ = self.placements.swapRemove(listIndex(idx)) else idx += 1;
        }
    }

    fn deletePlacementsInColumn(self: *State, x: u32) void {
        if (x == 0) return;
        const col = x - 1;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const p = self.placements.items[listIndex(idx)];
            const cols = @max(p.columns, 1);
            if (col >= p.col and col < p.col + cols) _ = self.placements.swapRemove(listIndex(idx)) else idx += 1;
        }
    }

    fn deletePlacementsInRow(self: *State, y: u32) void {
        if (y == 0) return;
        const row = y - 1;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const p = self.placements.items[listIndex(idx)];
            const rows = @max(p.rows, 1);
            if (row >= p.row and row < p.row + rows) _ = self.placements.swapRemove(listIndex(idx)) else idx += 1;
        }
    }

    fn deletePlacementsByZ(self: *State, z: i32) void {
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            if (self.placements.items[listIndex(idx)].z_index == z) _ = self.placements.swapRemove(listIndex(idx)) else idx += 1;
        }
    }

    fn deleteImagesInRange(self: *State, allocator: std.mem.Allocator, first: u32, last: u32) void {
        const lo = @min(first, last);
        const hi = @max(first, last);
        var idx: Index = 0;
        while (idx < self.imageCount()) {
            const image_id = self.images.items[listIndex(idx)].image_id;
            if (image_id >= lo and image_id <= hi) self.deleteImage(allocator, image_id) else idx += 1;
        }
    }

    fn deleteUnplacedImages(self: *State, allocator: std.mem.Allocator) void {
        var idx: Index = 0;
        while (idx < self.imageCount()) {
            const image_id = self.images.items[listIndex(idx)].image_id;
            if (!self.imageHasPlacement(image_id)) self.deleteImage(allocator, image_id) else idx += 1;
        }
    }

    fn imageHasPlacement(self: *const State, image_id: u32) bool {
        for (self.placements.items) |placement| if (placement.image_id == image_id) return true;
        return false;
    }

    fn deleteFrames(self: *State, allocator: std.mem.Allocator, cmd: KittyGraphicsCommand) void {
        const image_id = self.resolveImageId(cmd) orelse cmd.image_id;
        var idx: Index = 0;
        while (idx < self.frameCount()) {
            const frame = self.frames.items[listIndex(idx)];
            if ((image_id == 0 or frame.image_id == image_id) and (cmd.placement_id == 0 or frame.frame_number == cmd.placement_id)) {
                allocator.free(self.frames.items[listIndex(idx)].base64_payload);
                _ = self.frames.swapRemove(listIndex(idx));
            } else idx += 1;
        }
    }
};

fn countForLen(len: usize) Count {
    std.debug.assert(len <= std.math.maxInt(Count));
    return @intCast(len);
}

fn listIndex(idx: Index) usize {
    return @intCast(idx);
}

fn appendReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, image_id: u32, msg: []const u8) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b_Gi={d};{s}\x1b\\", .{ image_id, msg }) catch return;
    output.appendSlice(allocator, text) catch {};
}

fn appendNumberReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, image_id: u32, image_number: u32, msg: []const u8) void {
    const text = std.fmt.bufPrint(encode_buf, "\x1b_Gi={d},I={d};{s}\x1b\\", .{ image_id, image_number, msg }) catch return;
    output.appendSlice(allocator, text) catch {};
}
