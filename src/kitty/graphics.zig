const std = @import("std");
const screen_mod = @import("../screen.zig");
const vocabulary = @import("../action/vocabulary.zig");
const host_state = @import("../host/state.zig");
const parser = @import("../parser.zig");
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("stb_image.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

const KittyGraphicsCommand = vocabulary.KittyGraphicsCommand;
const CellPixelSize = screen_mod.Screen.CellPixelSize;
const reply_max_bytes = 60;
const MediaLoadError = error{
    InvalidGraphicsLocator,
    InvalidGraphicsMedium,
    InvalidGraphicsCompression,
    InvalidGraphicsData,
    GraphicsIo,
};

pub const RenderCursorView = struct {
    row: u16,
    col: u16,
    screen_rows: u16,
};

pub const RuntimeObligation = struct {
    pending_now: bool = false,
    deadline_ns: u64 = 0,
};

pub const CursorMove = struct {
    cols: u32,
    rows: u32,
};

pub const Count = u32;
pub const Index = u32;

// Ghostty accepts substantially larger Kitty APC payloads than the generic
// large-control ceiling because real direct-upload image traffic can exceed a
// 1 MiB burst. Keep Howl explicit and bounded, but give Kitty-owned retained
// payload state the same 65 MiB remote-upload scale while item counts stay
// capped at the metadata ceiling.
pub const image_max_count: Count = parser.max_metadata_control_bytes;
pub const placement_max_count: Count = parser.max_metadata_control_bytes;
pub const frame_max_count: Count = parser.max_metadata_control_bytes;
pub const retained_payload_max_bytes: u32 = 65 * 1024 * 1024;
pub const upload_max_bytes: u32 = retained_payload_max_bytes;
pub const parent_depth_limit: u32 = 8;
const kitty_placeholder_codepoint: u21 = 0x10EEEE;
const kitty_placeholder_diacritics = [_]u21{
    0x0305,  0x030D,  0x030E,  0x0310,  0x0312,  0x033D,  0x033E,  0x033F,  0x0346,  0x034A,
    0x034B,  0x034C,  0x0350,  0x0351,  0x0352,  0x0357,  0x035B,  0x0363,  0x0364,  0x0365,
    0x0366,  0x0367,  0x0368,  0x0369,  0x036A,  0x036B,  0x036C,  0x036D,  0x036E,  0x036F,
    0x0483,  0x0484,  0x0485,  0x0486,  0x0487,  0x0592,  0x0593,  0x0594,  0x0595,  0x0597,
    0x0598,  0x0599,  0x059C,  0x059D,  0x059E,  0x059F,  0x05A0,  0x05A1,  0x05A8,  0x05A9,
    0x05AB,  0x05AC,  0x05AF,  0x05C4,  0x0610,  0x0611,  0x0612,  0x0613,  0x0614,  0x0615,
    0x0616,  0x0617,  0x0657,  0x0658,  0x0659,  0x065A,  0x065B,  0x065D,  0x065E,  0x06D6,
    0x06D7,  0x06D8,  0x06D9,  0x06DA,  0x06DB,  0x06DC,  0x06DF,  0x06E0,  0x06E1,  0x06E2,
    0x06E4,  0x06E7,  0x06E8,  0x06EB,  0x06EC,  0x0730,  0x0732,  0x0733,  0x0735,  0x0736,
    0x073A,  0x073D,  0x073F,  0x0740,  0x0741,  0x0743,  0x0745,  0x0747,  0x0749,  0x074A,
    0x07EB,  0x07EC,  0x07ED,  0x07EE,  0x07EF,  0x07F0,  0x07F1,  0x07F3,  0x0816,  0x0817,
    0x0818,  0x0819,  0x081B,  0x081C,  0x081D,  0x081E,  0x081F,  0x0820,  0x0821,  0x0822,
    0x0823,  0x0825,  0x0826,  0x0827,  0x0829,  0x082A,  0x082B,  0x082C,  0x082D,  0x0951,
    0x0953,  0x0954,  0x0F82,  0x0F83,  0x0F86,  0x0F87,  0x135D,  0x135E,  0x135F,  0x17DD,
    0x193A,  0x1A17,  0x1A75,  0x1A76,  0x1A77,  0x1A78,  0x1A79,  0x1A7A,  0x1A7B,  0x1A7C,
    0x1B6B,  0x1B6D,  0x1B6E,  0x1B6F,  0x1B70,  0x1B71,  0x1B72,  0x1B73,  0x1CD0,  0x1CD1,
    0x1CD2,  0x1CDA,  0x1CDB,  0x1CE0,  0x1DC0,  0x1DC1,  0x1DC3,  0x1DC4,  0x1DC5,  0x1DC6,
    0x1DC7,  0x1DC8,  0x1DC9,  0x1DCB,  0x1DCC,  0x1DD1,  0x1DD2,  0x1DD3,  0x1DD4,  0x1DD5,
    0x1DD6,  0x1DD7,  0x1DD8,  0x1DD9,  0x1DDA,  0x1DDB,  0x1DDC,  0x1DDD,  0x1DDE,  0x1DDF,
    0x1DE0,  0x1DE1,  0x1DE2,  0x1DE3,  0x1DE4,  0x1DE5,  0x1DE6,  0x1DFE,  0x20D0,  0x20D1,
    0x20D4,  0x20D5,  0x20D6,  0x20D7,  0x20DB,  0x20DC,  0x20E1,  0x20E7,  0x20E9,  0x20F0,
    0x2CEF,  0x2CF0,  0x2CF1,  0x2DE0,  0x2DE1,  0x2DE2,  0x2DE3,  0x2DE4,  0x2DE5,  0x2DE6,
    0x2DE7,  0x2DE8,  0x2DE9,  0x2DEA,  0x2DEB,  0x2DEC,  0x2DED,  0x2DEE,  0x2DEF,  0x2DF0,
    0x2DF1,  0x2DF2,  0x2DF3,  0x2DF4,  0x2DF5,  0x2DF6,  0x2DF7,  0x2DF8,  0x2DF9,  0x2DFA,
    0x2DFB,  0x2DFC,  0x2DFD,  0x2DFE,  0x2DFF,  0xA66F,  0xA67C,  0xA67D,  0xA6F0,  0xA6F1,
    0xA8E0,  0xA8E1,  0xA8E2,  0xA8E3,  0xA8E4,  0xA8E5,  0xA8E6,  0xA8E7,  0xA8E8,  0xA8E9,
    0xA8EA,  0xA8EB,  0xA8EC,  0xA8ED,  0xA8EE,  0xA8EF,  0xA8F0,  0xA8F1,  0xAAB0,  0xAAB2,
    0xAAB3,  0xAAB7,  0xAAB8,  0xAABE,  0xAABF,  0xAAC1,  0xFE20,  0xFE21,  0xFE22,  0xFE23,
    0xFE24,  0xFE25,  0xFE26,  0x10A0F, 0x10A38, 0x1D185, 0x1D186, 0x1D187, 0x1D188, 0x1D189,
    0x1D1AA, 0x1D1AB, 0x1D1AC, 0x1D1AD, 0x1D242, 0x1D243, 0x1D244,
};

pub const Image = struct {
    pub const AnimationState = enum(u2) {
        stopped = 0,
        loading = 1,
        running = 2,
    };

    image_id: u32,
    image_number: u32,
    format: u16,
    width: u32,
    height: u32,
    base64_payload: []u8,
    current_frame_number: u32 = 1,
    current_override_format: u16 = 0,
    current_override_width: u32 = 0,
    current_override_height: u32 = 0,
    current_override_payload: ?[]u8 = null,
    next_frame_id: u32 = 1,
    root_frame_gap: i32 = 0,
    animation_state: AnimationState = .stopped,
    max_loops: u32 = 0,
    current_loop: u32 = 0,
    current_frame_shown_at_ns: u64 = 0,
};

pub const RowAnchor = union(enum) {
    on_screen: u16,
    scrollback_above: u32,
    below_screen: u32,

    pub fn initOnScreen(row: u16) RowAnchor {
        return .{ .on_screen = row };
    }

    fn onScreenRow(self: RowAnchor) ?u16 {
        return switch (self) {
            .on_screen => |row| row,
            .scrollback_above => null,
            .below_screen => null,
        };
    }

    pub fn scrollUp(self: RowAnchor, amount: u16, screen_rows: u16) RowAnchor {
        return switch (self) {
            .on_screen => |row| {
                if (row >= amount) return .{ .on_screen = row - amount };
                return .{ .scrollback_above = amount - row };
            },
            .scrollback_above => |rows| return .{ .scrollback_above = rows + amount },
            .below_screen => |rows| {
                if (rows >= amount) return .{ .below_screen = rows - amount };
                const delta = amount - rows;
                if (delta <= screen_rows) return .{ .on_screen = @intCast(screen_rows - @as(u16, @intCast(delta))) };
                return .{ .scrollback_above = delta - screen_rows };
            },
        };
    }

    pub fn scrollDown(self: RowAnchor, amount: u16, screen_rows: u16) RowAnchor {
        return switch (self) {
            .scrollback_above => |rows| {
                if (rows > amount) return .{ .scrollback_above = rows - amount };
                const delta = amount - rows;
                if (delta == 0) return .{ .on_screen = 0 };
                if (delta <= screen_rows) return .{ .on_screen = @intCast(delta - 1) };
                return .{ .below_screen = delta - screen_rows };
            },
            .on_screen => |row| {
                const next = @as(u32, row) + amount;
                if (next < screen_rows) return .{ .on_screen = @intCast(next) };
                return .{ .below_screen = next - screen_rows };
            },
            .below_screen => |rows| return .{ .below_screen = rows + amount },
        };
    }
};

pub const Placement = struct {
    parent_is_virtual: bool = false,
    image_id: u32,
    placement_id: u32,
    z_index: i32,
    anchor_row: RowAnchor,
    anchor_col: u16,
    parent_image_id: u32 = 0,
    parent_placement_id: u32 = 0,
    parent_offset_cols: i32 = 0,
    parent_offset_rows: i32 = 0,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    cell_x_offset: u32,
    cell_y_offset: u32,
    columns: u32,
    rows: u32,
    effective_columns: u32,
    effective_rows: u32,

    pub const ResolvedDestGeometry = struct {
        left_px: u32,
        top_px: u32,
        right_px: u32,
        bottom_px: u32,
    };

    pub fn resolveDestGeometry(self: Placement, cell_pixel_size: ?CellPixelSize) ?ResolvedDestGeometry {
        const left_px = self.cell_x_offset;
        const top_px = self.cell_y_offset;

        if (cell_pixel_size == null) {
            const right_px = std.math.add(u32, left_px, self.effective_columns) catch return null;
            const bottom_px = std.math.add(u32, top_px, self.effective_rows) catch return null;
            return .{
                .left_px = left_px,
                .top_px = top_px,
                .right_px = right_px,
                .bottom_px = bottom_px,
            };
        }

        const cell = cell_pixel_size.?;
        std.debug.assert(cell.width > 0);
        std.debug.assert(cell.height > 0);

        const width_px = resolvedWidthPx(self, cell);
        const height_px = resolvedHeightPx(self, cell, width_px);
        const right_px = std.math.add(u32, left_px, width_px) catch return null;
        const bottom_px = std.math.add(u32, top_px, height_px) catch return null;
        return .{
            .left_px = left_px,
            .top_px = top_px,
            .right_px = right_px,
            .bottom_px = bottom_px,
        };
    }

    fn recomputeExtent(self: *Placement, cell_pixel_size: ?CellPixelSize) void {
        const extent = resolveGridExtent(
            self.source_width,
            self.source_height,
            self.cell_x_offset,
            self.cell_y_offset,
            self.columns,
            self.rows,
            cell_pixel_size,
        );
        self.effective_columns = extent.columns;
        self.effective_rows = extent.rows;
    }

    fn hasParent(self: Placement) bool {
        return self.parent_image_id != 0;
    }
};

pub const VirtualPlacement = struct {
    image_id: u32,
    placement_id: u32,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    columns: u32,
    rows: u32,

    fn validate(self: VirtualPlacement) void {
        std.debug.assert(self.source_width > 0);
        std.debug.assert(self.source_height > 0);
        std.debug.assert(self.columns > 0);
        std.debug.assert(self.rows > 0);
    }
};

const PlaceholderParentMatch = struct {
    row: RowAnchor,
    col: u16,
};

const ParentPlacementRef = struct {
    image_id: u32,
    placement_id: u32,
    is_virtual: bool,
    parent_image_id: u32 = 0,
    parent_placement_id: u32 = 0,
};

pub const Frame = struct {
    frame_id: u32,
    image_id: u32,
    frame_number: u32,
    format: u16,
    width: u32,
    height: u32,
    x: u32,
    y: u32,
    uses_root_base: bool,
    base_frame_id: u32,
    compose_mode: u32,
    background_rgba: u32,
    gap: i32,
    base64_payload: []u8,
};

const HandleResult = struct {
    changed: bool,
    move: ?CursorMove,
};

pub const Upload = struct {
    image_id: u32,
    image_number: u32,
    action: u8,
    unicode_placement: bool,
    quiet: bool,
    compression: u8,
    format: u16,
    width: u32,
    height: u32,
    frame_number: u32,
    base_frame_number: u32,
    compose_mode: u32,
    background_rgba: u32,
    gap: i32,
    // Retain physical placement metadata from the first chunk so a future
    // honest a=T implementation does not depend on continuation chunks
    // repeating control fields.
    placement_id: u32,
    source_x: u32,
    source_y: u32,
    source_width: u32,
    source_height: u32,
    cell_x_offset: u32,
    cell_y_offset: u32,
    no_move_cursor: bool,
    columns: u32,
    rows: u32,
    z_index: i32,
    anchor_row: u16,
    anchor_col: u16,
    data: std.ArrayList(u8),
};

pub const State = struct {
    images: std.ArrayList(Image) = .empty,
    placements: std.ArrayList(Placement) = .empty,
    virtual_placements: std.ArrayList(VirtualPlacement) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    upload: ?Upload = null,
    next_image_id: u32 = 1,

    fn count32(items: anytype) u32 {
        std.debug.assert(items.len <= std.math.maxInt(u32));
        return @intCast(items.len);
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        for (self.images.items) |image| {
            allocator.free(image.base64_payload);
            if (image.current_override_payload) |payload| allocator.free(payload);
        }
        self.images.deinit(allocator);
        self.placements.deinit(allocator);
        self.virtual_placements.deinit(allocator);
        for (self.frames.items) |frame| allocator.free(frame.base64_payload);
        self.frames.deinit(allocator);
        if (self.upload) |*upload| upload.data.deinit(allocator);
    }

    pub fn runtimeObligation(self: *const State, now_ns: u64) RuntimeObligation {
        var earliest_deadline_ns: u64 = 0;
        for (self.images.items) |image| {
            const obligation = self.imageRuntimeObligation(image, now_ns);
            if (obligation.pending_now) return .{ .pending_now = true, .deadline_ns = 0 };
            if (obligation.deadline_ns == 0) continue;
            if (earliest_deadline_ns == 0 or obligation.deadline_ns < earliest_deadline_ns) {
                earliest_deadline_ns = obligation.deadline_ns;
            }
        }
        return .{ .pending_now = false, .deadline_ns = earliest_deadline_ns };
    }

    pub fn progressRuntime(self: *State, allocator: std.mem.Allocator, now_ns: u64) host_state.ApplyError!bool {
        var candidate_idx: ?usize = null;
        var earliest_deadline_ns: u64 = 0;
        for (self.images.items, 0..) |image, idx| {
            const obligation = self.imageRuntimeObligation(image, now_ns);
            if (!obligation.pending_now) continue;
            const deadline_ns = self.imageDueSortKey(image, now_ns);
            if (candidate_idx == null or deadline_ns < earliest_deadline_ns) {
                candidate_idx = idx;
                earliest_deadline_ns = deadline_ns;
            }
        }
        const idx = candidate_idx orelse return false;
        return try self.progressImageRuntime(allocator, @intCast(idx), now_ns);
    }

    fn imageRuntimeObligation(self: *const State, image: Image, now_ns: u64) RuntimeObligation {
        if (!imageNeedsRuntime(self, image)) return .{};
        if (image.animation_state == .loading and image.current_frame_shown_at_ns == 0 and image.current_frame_number == self.frameCountForImage(image.image_id)) {
            return .{};
        }
        if (image.current_frame_shown_at_ns == 0) return .{ .pending_now = true, .deadline_ns = 0 };
        const gap = self.currentFrameGap(image);
        if (gap <= 0) return .{ .pending_now = true, .deadline_ns = 0 };
        const gap_ns = gapToNs(gap) orelse return .{ .pending_now = true, .deadline_ns = 0 };
        const deadline_ns = image.current_frame_shown_at_ns +% gap_ns;
        if (now_ns >= deadline_ns) return .{ .pending_now = true, .deadline_ns = 0 };
        return .{ .pending_now = false, .deadline_ns = deadline_ns };
    }

    fn imageDueSortKey(self: *const State, image: Image, now_ns: u64) u64 {
        if (image.current_frame_shown_at_ns == 0) return 0;
        const gap = self.currentFrameGap(image);
        if (gap <= 0) return 0;
        const gap_ns = gapToNs(gap) orelse return 0;
        const deadline_ns = image.current_frame_shown_at_ns +% gap_ns;
        if (deadline_ns <= now_ns) return 0;
        return deadline_ns;
    }

    fn progressImageRuntime(self: *State, allocator: std.mem.Allocator, image_idx: Index, now_ns: u64) host_state.ApplyError!bool {
        const image = &self.images.items[@intCast(image_idx)];
        if (!imageNeedsRuntime(self, image.*)) return false;

        const gap = self.currentFrameGap(image.*);
        if (image.current_frame_shown_at_ns == 0) {
            if (gap > 0) {
                image.current_frame_shown_at_ns = now_ns;
                return false;
            }
            return try self.advanceRuntimeFrame(allocator, image_idx, now_ns);
        }

        if (gap > 0) {
            const gap_ns = gapToNs(gap) orelse return try self.advanceRuntimeFrame(allocator, image_idx, now_ns);
            if (now_ns < image.current_frame_shown_at_ns +% gap_ns) return false;
        }

        return try self.advanceRuntimeFrame(allocator, image_idx, now_ns);
    }

    fn advanceRuntimeFrame(self: *State, allocator: std.mem.Allocator, image_idx: Index, now_ns: u64) host_state.ApplyError!bool {
        const image = &self.images.items[@intCast(image_idx)];
        const original_frame = image.current_frame_number;
        while (true) {
            const next = self.nextRuntimeFrameNumber(image.*) orelse {
                image.current_frame_shown_at_ns = 0;
                return false;
            };
            image.current_frame_number = next;
            try self.refreshCurrentFramePublication(allocator, image_idx);
            const gap = self.currentFrameGap(image.*);
            if (gap > 0) {
                image.current_frame_shown_at_ns = now_ns;
                return image.current_frame_number != original_frame;
            }
        }
    }

    fn nextRuntimeFrameNumber(self: *State, image: Image) ?u32 {
        const total_frames = self.frameCountForImage(image.image_id);
        if (total_frames <= 1) return null;
        const next = image.current_frame_number + 1;
        if (next <= total_frames) return next;
        return switch (image.animation_state) {
            .loading => null,
            .running => blk: {
                const owned = &self.images.items[@intCast(self.findImage(image.image_id).?)];
                if (image.max_loops != 0 and image.current_loop + 1 >= image.max_loops) {
                    owned.animation_state = .stopped;
                    owned.current_loop = 0;
                    break :blk null;
                }
                owned.current_loop += 1;
                break :blk 1;
            },
            .stopped => null,
        };
    }

    fn currentFrameGap(self: *const State, image: Image) i32 {
        if (image.current_frame_number == 1) return image.root_frame_gap;
        const frame = self.frameByNumber(image.image_id, image.current_frame_number) orelse return 0;
        return frame.gap;
    }

    fn frameCountForImage(self: *const State, image_id: u32) u32 {
        var count: u32 = 1;
        for (self.frames.items) |frame| {
            if (frame.image_id == image_id) count += 1;
        }
        return count;
    }

    fn setAnimationControl(self: *State, image_idx: Index, animation_state: u32, loop_count: u32) bool {
        const image = &self.images.items[@intCast(image_idx)];
        var changed = false;
        if (loop_count != 0) {
            const next_max_loops = if (loop_count == 1) 0 else loop_count - 1;
            if (image.max_loops != next_max_loops) {
                image.max_loops = next_max_loops;
                changed = true;
            }
        }
        if (animation_state != 0) {
            const next_state: Image.AnimationState = switch (animation_state) {
                1 => .stopped,
                2 => .loading,
                3 => .running,
                else => return changed,
            };
            if (image.animation_state != next_state) {
                image.animation_state = next_state;
                changed = true;
            }
            image.current_loop = 0;
            image.current_frame_shown_at_ns = 0;
        }
        return changed;
    }

    fn setFrameGap(self: *State, allocator: std.mem.Allocator, image_idx: Index, frame_number: u32, gap: i32) host_state.ApplyError!bool {
        _ = allocator;
        if (gap == 0) return false;
        const image = &self.images.items[@intCast(image_idx)];
        if (frame_number == 1) {
            if (image.root_frame_gap == gap) return false;
            image.root_frame_gap = gap;
            if (image.current_frame_number == 1) image.current_frame_shown_at_ns = 0;
            return true;
        }
        const frame_idx = self.findFrameIndex(image.image_id, frame_number) orelse return false;
        const frame = &self.frames.items[@intCast(frame_idx)];
        if (frame.gap == gap) return false;
        frame.gap = gap;
        if (image.current_frame_number == frame_number) image.current_frame_shown_at_ns = 0;
        return true;
    }

    pub fn reset(self: *State, allocator: std.mem.Allocator) void {
        for (self.images.items) |image| {
            allocator.free(image.base64_payload);
            if (image.current_override_payload) |payload| allocator.free(payload);
        }
        self.images.clearRetainingCapacity();
        self.placements.clearRetainingCapacity();
        self.virtual_placements.clearRetainingCapacity();
        for (self.frames.items) |frame| allocator.free(frame.base64_payload);
        self.frames.clearRetainingCapacity();
        self.abortUpload(allocator);
        self.next_image_id = 1;
    }

    pub fn imageCount(self: *const State) Count {
        return count32(self.images.items);
    }

    pub fn imageAt(self: *const State, idx: Index) ?Image {
        if (idx >= self.imageCount()) return null;
        const image = self.images.items[@intCast(idx)];
        if (image.current_override_payload) |payload| {
            var published = image;
            published.format = image.current_override_format;
            published.width = image.current_override_width;
            published.height = image.current_override_height;
            published.base64_payload = payload;
            return published;
        }
        return image;
    }

    pub fn placementCount(self: *const State) Count {
        return count32(self.placements.items);
    }

    pub fn virtualPlacementCount(self: *const State) Count {
        return count32(self.virtual_placements.items);
    }

    pub fn placementAt(self: *const State, idx: Index) ?Placement {
        if (idx >= self.placementCount()) return null;
        return self.placements.items[@intCast(idx)];
    }

    pub fn virtualPlacementAt(self: *const State, idx: Index) ?VirtualPlacement {
        if (idx >= self.virtualPlacementCount()) return null;
        return self.virtual_placements.items[@intCast(idx)];
    }

    pub fn placementAtResolved(self: *const State, idx: Index, screen: *const screen_mod.Screen) ?Placement {
        if (idx >= self.placementCount()) return null;
        var placement = self.placements.items[@intCast(idx)];
        const anchor = self.resolvePlacementAnchor(placement, screen) orelse return null;
        if (anchor.col < 0) return null;
        placement.anchor_row = anchor.row;
        placement.anchor_col = std.math.cast(u16, anchor.col) orelse return null;
        return placement;
    }

    pub fn resolvedPlacementCount(self: *const State, screen: *const screen_mod.Screen) Count {
        var count: u32 = 0;
        for (self.placements.items) |placement| {
            _ = self.resolvePlacementAnchor(placement, screen) orelse continue;
            count += 1;
        }
        return count;
    }

    pub fn resolvedPlacementAt(self: *const State, idx: Index, screen: *const screen_mod.Screen) ?Placement {
        var resolved_idx: u32 = 0;
        for (self.placements.items) |placement| {
            var resolved = placement;
            const anchor = self.resolvePlacementAnchor(resolved, screen) orelse continue;
            if (anchor.col < 0) continue;
            if (resolved_idx == idx) {
                resolved.anchor_row = anchor.row;
                resolved.anchor_col = std.math.cast(u16, anchor.col) orelse return null;
                return resolved;
            }
            resolved_idx += 1;
        }
        return null;
    }

    pub fn frameCount(self: *const State) Count {
        return count32(self.frames.items);
    }

    pub fn frameAt(self: *const State, idx: Index) ?Frame {
        if (idx >= self.frameCount()) return null;
        return self.frames.items[@intCast(idx)];
    }

    pub fn scrollUpFullPage(self: *State, screen: *const screen_mod.Screen, history_count: u32, count: u16, retain_in_scrollback: bool) void {
        const screen_rows = screen.rows;
        if (count == 0 or screen_rows == 0) return;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            var placement = &self.placements.items[@intCast(idx)];
            if (!placement.hasParent()) {
                placement.anchor_row = placement.anchor_row.scrollUp(count, screen_rows);
            }
            const resolved = self.resolvePlacementAnchor(placement.*, screen) orelse {
                idx += 1;
                continue;
            };
            if (rowAnchorRetained(resolved.row, history_count, placement.effective_rows, retain_in_scrollback)) {
                idx += 1;
            } else {
                _ = self.placements.swapRemove(@intCast(idx));
            }
        }
    }

    pub fn scrollDownFullPage(self: *State, screen: *const screen_mod.Screen, count: u16) void {
        const screen_rows = screen.rows;
        if (count == 0 or screen_rows == 0) return;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            if (!self.placements.items[@intCast(idx)].hasParent()) {
                self.placements.items[@intCast(idx)].anchor_row = self.placements.items[@intCast(idx)].anchor_row.scrollDown(count, screen_rows);
            }
            idx += 1;
        }
    }

    pub fn scrollUpRegion(self: *State, _: *const screen_mod.Screen, top: u16, bottom: u16, count: u16, cell: CellPixelSize) void {
        if (count == 0 or top > bottom or cell.height == 0) return;
        const amount = @min(count, bottom - top + 1);
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            var placement = &self.placements.items[@intCast(idx)];
            if (placement.hasParent()) {
                idx += 1;
                continue;
            }
            if (!placementFullyWithinRegion(placement.*, top, bottom)) {
                idx += 1;
                continue;
            }

            const anchor_row = placement.anchor_row.onScreenRow().?;
            placement.anchor_row = RowAnchor.initOnScreen(anchor_row -| amount);
            if (clipPlacementTop(placement, top, cell)) {
                validatePlacement(placement.*);
                idx += 1;
            } else {
                _ = self.placements.swapRemove(@intCast(idx));
            }
        }
    }

    pub fn scrollDownRegion(self: *State, _: *const screen_mod.Screen, top: u16, bottom: u16, count: u16, cell: CellPixelSize) void {
        if (count == 0 or top > bottom or cell.height == 0) return;
        const amount = @min(count, bottom - top + 1);
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            var placement = &self.placements.items[@intCast(idx)];
            if (placement.hasParent()) {
                idx += 1;
                continue;
            }
            if (!placementFullyWithinRegion(placement.*, top, bottom)) {
                idx += 1;
                continue;
            }

            const anchor_row = placement.anchor_row.onScreenRow().?;
            placement.anchor_row = RowAnchor.initOnScreen(anchor_row + amount);
            if (clipPlacementBottom(placement, bottom, cell)) {
                validatePlacement(placement.*);
                idx += 1;
            } else {
                _ = self.placements.swapRemove(@intCast(idx));
            }
        }
    }

    pub fn clearVisiblePlacements(self: *State, screen: *const screen_mod.Screen) void {
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const placement = self.placements.items[@intCast(idx)];
            const resolved = self.resolvePlacementAnchor(placement, screen) orelse {
                idx += 1;
                continue;
            };
            if (rowAnchorVisible(resolved.row, placement.effective_rows)) {
                _ = self.placements.swapRemove(@intCast(idx));
            } else {
                idx += 1;
            }
        }
    }

    pub fn handle(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) host_state.ApplyError!HandleResult {
        if (cmd.unsupported_key != 0) {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics control key");
            return .{ .changed = false, .move = null };
        }
        if (cmd.action == 'q') {
            try self.queryImageSupport(allocator, cmd, output, encode_buf);
            return .{ .changed = false, .move = null };
        }
        if (cmd.action == 'a') {
            return try self.controlAnimation(allocator, output, encode_buf, cmd);
        }
        if (cmd.action == 'c') {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics action");
            return .{ .changed = false, .move = null };
        }
        if (!graphicsMediumSupported(cmd.medium)) {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics medium");
            return .{ .changed = false, .move = null };
        }
        if (!graphicsCompressionSupported(cmd)) {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics compression");
            return .{ .changed = false, .move = null };
        }
        if (cmd.action == 'p') {
            return .{ .changed = true, .move = try self.placeImage(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd) };
        }
        if (cmd.action == 'd') {
            self.delete(allocator, screen, render_view, cmd);
            return .{ .changed = true, .move = null };
        }
        if (cmd.action == 'f') {
            const move = try self.captureUpload(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd);
            return .{ .changed = move != null or cmd.more_chunks or self.upload != null or cmd.payload.len != 0, .move = move };
        }
        if (cmd.action != 't' and cmd.action != 'T') {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics action");
            return .{ .changed = false, .move = null };
        }
        return .{ .changed = true, .move = try self.captureUpload(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd) };
    }

    fn controlAnimation(self: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) host_state.ApplyError!HandleResult {
        const controls = @intFromBool(cmd.current_frame_number != 0) +
            @intFromBool(cmd.edit_frame_number != 0 or cmd.z != 0) +
            @intFromBool(cmd.animation_state != 0 or cmd.loop_count != 0);
        if (controls == 0 or controls > 1) {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics action");
            return .{ .changed = false, .move = null };
        }
        const image_id = self.resolveImageId(cmd) orelse {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "ENOENT:image not found");
            return .{ .changed = false, .move = null };
        };
        const image_idx = self.findImage(image_id) orelse unreachable;
        const changed = if (cmd.current_frame_number != 0)
            try self.selectCurrentFrame(allocator, @intCast(image_idx), cmd.current_frame_number)
        else if (cmd.edit_frame_number != 0 or cmd.z != 0)
            try self.setFrameGap(allocator, @intCast(image_idx), cmd.edit_frame_number, cmd.z)
        else
            self.setAnimationControl(@intCast(image_idx), cmd.animation_state, cmd.loop_count);
        if (!cmd.quiet and (cmd.image_id != 0 or cmd.image_number != 0)) {
            try appendNumberReply(allocator, output, encode_buf, image_id, cmd.image_number, "OK");
        }
        return .{ .changed = changed, .move = null };
    }

    fn queryImageSupport(self: *State, allocator: std.mem.Allocator, cmd: KittyGraphicsCommand, output: *std.ArrayList(u8), encode_buf: []u8) host_state.ApplyError!void {
        _ = self;
        switch (cmd.medium) {
            'd' => {
                const normalized = normalizeDirectPayloadOwned(allocator, cmd.compression, cmd.format, cmd.width, cmd.height, cmd.payload) catch |err| {
                    switch (err) {
                        error.InvalidGraphicsCompression => {
                            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics compression");
                            return;
                        },
                        error.InvalidGraphicsData => {
                            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "ENODATA:insufficient kitty graphics data");
                            return;
                        },
                        error.OutOfMemory => return error.OutOfMemory,
                        error.ConsequenceLimit => return error.ConsequenceLimit,
                    }
                };
                defer allocator.free(normalized);
            },
            'f', 't', 's' => {
                const normalized = loadIndirectPayloadNormalized(allocator, cmd) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.ConsequenceLimit => return error.ConsequenceLimit,
                    error.InvalidGraphicsLocator => {
                        if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:invalid kitty graphics locator");
                        return;
                    },
                    error.InvalidGraphicsMedium => {
                        if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics medium");
                        return;
                    },
                    error.InvalidGraphicsCompression => {
                        if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics compression");
                        return;
                    },
                    error.InvalidGraphicsData => {
                        if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "ENODATA:insufficient kitty graphics data");
                        return;
                    },
                    error.GraphicsIo => {
                        if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EBADF:failed to read kitty graphics medium");
                        return;
                    },
                };
                defer allocator.free(normalized);
            },
            else => {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics medium");
                return;
            },
        }
        if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "OK");
    }

    fn placeImage(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) host_state.ApplyError!?CursorMove {
        const image_id = self.resolveImageId(cmd) orelse {
            if (!cmd.quiet) try appendPlacementReply(allocator, output, encode_buf, cmd.image_id, cmd.image_number, cmd.placement_id, "ENOENT:image not found");
            return null;
        };
        const image = self.images.items[@intCast(self.findImage(image_id).?)];
        const source_width = if (cmd.source_width != 0) cmd.source_width else image.width;
        const source_height = if (cmd.source_height != 0) cmd.source_height else image.height;
        if (cmd.unicode_placement) {
            if (cmd.parent_image_id != 0) {
                if (!cmd.quiet) try appendPlacementReply(allocator, output, encode_buf, cmd.image_id, cmd.image_number, cmd.placement_id, "EINVAL:virtual placement cannot refer to a parent");
                return null;
            }
            return try self.upsertVirtualPlacement(allocator, output, encode_buf, .{
                .image_id = image_id,
                .placement_id = cmd.placement_id,
                .source_x = cmd.x,
                .source_y = cmd.y,
                .source_width = source_width,
                .source_height = source_height,
                .columns = @max(cmd.columns, 1),
                .rows = @max(cmd.rows, 1),
            }, cmd.image_number, cmd.quiet);
        }
        const extent = resolveGridExtent(source_width, source_height, cmd.cell_x_offset, cmd.cell_y_offset, cmd.columns, cmd.rows, cell_pixel_size);
        const parent = try self.resolveParentPlacement(allocator, output, encode_buf, cmd.image_id, cmd.image_number, cmd.placement_id, cmd.parent_image_id, cmd.parent_placement_id, cmd.quiet) orelse return null;
        return try self.upsertPlacement(allocator, output, encode_buf, .{
            .parent_is_virtual = parent.is_virtual,
            .image_id = image_id,
            .placement_id = cmd.placement_id,
            .z_index = cmd.z,
            .anchor_row = RowAnchor.initOnScreen(render_view.row),
            .anchor_col = render_view.col,
            .parent_image_id = parent.image_id,
            .parent_placement_id = parent.placement_id,
            .parent_offset_cols = cmd.parent_offset_cols,
            .parent_offset_rows = cmd.parent_offset_rows,
            .source_x = cmd.x,
            .source_y = cmd.y,
            .source_width = source_width,
            .source_height = source_height,
            .cell_x_offset = cmd.cell_x_offset,
            .cell_y_offset = cmd.cell_y_offset,
            .columns = cmd.columns,
            .rows = cmd.rows,
            .effective_columns = extent.columns,
            .effective_rows = extent.rows,
        }, screen, cmd.image_number, cmd.quiet, cmd.no_move_cursor);
    }

    fn delete(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cmd: KittyGraphicsCommand) void {
        self.abortUpload(allocator);
        switch (cmd.delete_target) {
            0, 'a', 'A' => {
                self.placements.clearRetainingCapacity();
                if (cmd.delete_target == 'A') self.deleteUnplacedImages(allocator);
            },
            'i', 'I' => if (self.resolveImageId(cmd)) |image_id| {
                if (cmd.placement_id != 0) {
                    self.deletePlacement(allocator, image_id, cmd.placement_id);
                    self.deleteVirtualPlacement(image_id, cmd.placement_id);
                } else self.deleteImage(allocator, image_id);
            },
            'n', 'N' => if (self.findNewestImageByNumber(cmd.image_number)) |idx| {
                const image_id = self.images.items[@intCast(idx)].image_id;
                if (cmd.placement_id != 0) {
                    self.deletePlacement(allocator, image_id, cmd.placement_id);
                    self.deleteVirtualPlacement(image_id, cmd.placement_id);
                } else self.deleteImage(allocator, image_id);
            },
            'c', 'C' => {
                self.deletePlacementsAt(allocator, screen, render_view.col + 1, render_view.row + 1, null);
                if (cmd.delete_target == 'C') self.deleteUnplacedImages(allocator);
            },
            'p', 'P' => {
                self.deletePlacementsAt(allocator, screen, cmd.x, cmd.y, null);
                if (cmd.delete_target == 'P') self.deleteUnplacedImages(allocator);
            },
            'q', 'Q' => {
                self.deletePlacementsAt(allocator, screen, cmd.x, cmd.y, cmd.z);
                if (cmd.delete_target == 'Q') self.deleteUnplacedImages(allocator);
            },
            'r', 'R' => self.deleteImagesInRange(allocator, cmd.x, cmd.y),
            'x', 'X' => {
                self.deletePlacementsInColumn(allocator, screen, cmd.x);
                if (cmd.delete_target == 'X') self.deleteUnplacedImages(allocator);
            },
            'y', 'Y' => {
                self.deletePlacementsInRow(allocator, screen, cmd.y);
                if (cmd.delete_target == 'Y') self.deleteUnplacedImages(allocator);
            },
            'z', 'Z' => {
                self.deletePlacementsByZ(allocator, cmd.z);
                if (cmd.delete_target == 'Z') self.deleteUnplacedImages(allocator);
            },
            'f', 'F' => self.deleteFrames(allocator, cmd),
            else => {},
        }
    }

    fn captureUpload(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) host_state.ApplyError!?CursorMove {
        if (cmd.action != 't' and cmd.action != 'T' and cmd.action != 'f') return null;
        if (cmd.medium != 'd') {
            return try self.storeIndirectPayload(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd);
        }
        if (cmd.more_chunks) {
            return try self.appendUploadChunk(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd, true);
        }
        if (self.upload != null) {
            return try self.appendUploadChunk(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd, false);
        } else {
            return try self.storeDirectPayload(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd, cmd.payload);
        }
    }

    fn appendUploadChunk(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand, more: bool) host_state.ApplyError!?CursorMove {
        if (self.upload == null) {
            const image_id = self.imageIdForUpload(cmd);
            self.upload = .{
                .image_id = image_id,
                .image_number = cmd.image_number,
                .action = cmd.action,
                .unicode_placement = cmd.unicode_placement,
                .quiet = cmd.quiet,
                .compression = cmd.compression,
                .format = cmd.format,
                .width = cmd.width,
                .height = cmd.height,
                .frame_number = cmd.edit_frame_number,
                .base_frame_number = cmd.base_frame_number,
                .compose_mode = cmd.compose_mode,
                .background_rgba = cmd.background_rgba,
                .gap = cmd.z,
                .placement_id = cmd.placement_id,
                .source_x = cmd.x,
                .source_y = cmd.y,
                .source_width = cmd.source_width,
                .source_height = cmd.source_height,
                .cell_x_offset = cmd.cell_x_offset,
                .cell_y_offset = cmd.cell_y_offset,
                .no_move_cursor = cmd.no_move_cursor,
                .columns = cmd.columns,
                .rows = cmd.rows,
                .z_index = cmd.z,
                .anchor_row = render_view.row,
                .anchor_col = render_view.col,
                .data = std.ArrayList(u8).empty,
            };
        }
        if (self.upload) |*upload| {
            upload.data.appendSlice(allocator, cmd.payload) catch |err| switch (err) {
                error.OutOfMemory => {
                    self.abortUpload(allocator);
                    return error.OutOfMemory;
                },
            };
            errdefer self.abortUpload(allocator);
            try ensureRetainedPayloadTotal(self);
            try ensureUploadBound(count32(upload.data.items));
            if (more) return null;
            const image_id = upload.image_id;
            const image_number = upload.image_number;
            const action = upload.action;
            const upload_unicode_placement = upload.unicode_placement;
            const quiet = upload.quiet;
            const compression = upload.compression;
            const format = upload.format;
            const width = upload.width;
            const height = upload.height;
            const frame_number = upload.frame_number;
            const base_frame_number = upload.base_frame_number;
            const compose_mode = upload.compose_mode;
            const background_rgba = upload.background_rgba;
            const gap = upload.gap;
            const placement_id = upload.placement_id;
            const source_x = upload.source_x;
            const source_y = upload.source_y;
            const source_width = upload.source_width;
            const source_height = upload.source_height;
            const cell_x_offset = upload.cell_x_offset;
            const cell_y_offset = upload.cell_y_offset;
            const no_move_cursor = upload.no_move_cursor;
            const columns = upload.columns;
            const rows = upload.rows;
            const z_index = upload.z_index;
            const anchor_row = upload.anchor_row;
            const anchor_col = upload.anchor_col;
            const transport = try upload.data.toOwnedSlice(allocator);
            defer allocator.free(transport);
            self.upload = null;
            const owned = normalizeDirectPayloadOwned(allocator, compression, format, width, height, transport) catch |err| {
                switch (err) {
                    error.InvalidGraphicsCompression => {
                        if (!quiet) try appendReply(allocator, output, encode_buf, image_id, "EINVAL:unsupported kitty graphics compression");
                        return null;
                    },
                    error.InvalidGraphicsData => {
                        if (!quiet) try appendReply(allocator, output, encode_buf, image_id, "ENODATA:insufficient kitty graphics data");
                        return null;
                    },
                    error.OutOfMemory => return error.OutOfMemory,
                    error.ConsequenceLimit => return error.ConsequenceLimit,
                }
            };
            if (action == 'f') {
                try self.storeFrameOwned(allocator, image_id, frame_number, format, width, height, upload.source_x, upload.source_y, base_frame_number, compose_mode, background_rgba, gap, owned);
            } else {
                try self.storeImageOwned(allocator, image_id, image_number, format, width, height, owned);
                if (action == 'T') {
                    const anonymous = image_id == 0 and image_number == 0;
                    const move = try self.placeStoredImage(allocator, screen, cell_pixel_size, output, encode_buf, .{
                        .unicode_placement = upload_unicode_placement,
                        .image_id = image_id,
                        .image_number = image_number,
                        .placement_id = if (anonymous) 0 else placement_id,
                        .z_index = z_index,
                        .anchor_row = anchor_row,
                        .anchor_col = anchor_col,
                        .source_x = source_x,
                        .source_y = source_y,
                        .source_width = source_width,
                        .source_height = source_height,
                        .cell_x_offset = cell_x_offset,
                        .cell_y_offset = cell_y_offset,
                        .no_move_cursor = no_move_cursor,
                        .columns = columns,
                        .rows = rows,
                    }, quiet or anonymous);
                    return move;
                }
                if (image_number != 0 and !quiet) try appendNumberReply(allocator, output, encode_buf, image_id, image_number, "OK");
            }
        }
        return null;
    }

    fn storeDirectPayload(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand, payload: []const u8) host_state.ApplyError!?CursorMove {
        const owned = normalizeDirectPayloadOwned(allocator, cmd.compression, cmd.format, cmd.width, cmd.height, payload) catch |err| {
            switch (err) {
                error.InvalidGraphicsCompression => {
                    if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics compression");
                    return null;
                },
                error.InvalidGraphicsData => {
                    if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "ENODATA:insufficient kitty graphics data");
                    return null;
                },
                error.OutOfMemory => return error.OutOfMemory,
                error.ConsequenceLimit => return error.ConsequenceLimit,
            }
        };
        defer allocator.free(owned);
        return try self.storePayload(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd, owned);
    }

    fn storeIndirectPayload(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand) host_state.ApplyError!?CursorMove {
        if (cmd.more_chunks) {
            if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:chunked kitty graphics upload requires direct medium");
            return null;
        }

        const normalized = loadIndirectPayloadNormalized(allocator, cmd) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ConsequenceLimit => return error.ConsequenceLimit,
            error.InvalidGraphicsLocator => {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:invalid kitty graphics locator");
                return null;
            },
            error.InvalidGraphicsMedium => {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics medium");
                return null;
            },
            error.InvalidGraphicsCompression => {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EINVAL:unsupported kitty graphics compression");
                return null;
            },
            error.InvalidGraphicsData => {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "ENODATA:insufficient kitty graphics data");
                return null;
            },
            error.GraphicsIo => {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "EBADF:failed to read kitty graphics medium");
                return null;
            },
        };
        defer allocator.free(normalized);

        return try self.storePayload(allocator, screen, render_view, cell_pixel_size, output, encode_buf, cmd, normalized);
    }

    fn storePayload(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, render_view: RenderCursorView, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, cmd: KittyGraphicsCommand, payload: []const u8) host_state.ApplyError!?CursorMove {
        if (cmd.action == 'f') {
            const image_id = self.resolveImageId(cmd) orelse cmd.image_id;
            if (self.findImage(image_id) == null) {
                if (!cmd.quiet) try appendReply(allocator, output, encode_buf, cmd.image_id, "ENOENT:image not found");
                return null;
            }
        }
        try ensureRetainedPayloadStore(self, count32(payload), 0);
        const owned = try allocator.dupe(u8, payload);
        const image_id = self.imageIdForUpload(cmd);
        if (cmd.action == 'f') {
            try self.storeFrameOwned(allocator, image_id, cmd.edit_frame_number, cmd.format, cmd.width, cmd.height, cmd.x, cmd.y, cmd.base_frame_number, cmd.compose_mode, cmd.background_rgba, cmd.z, owned);
        } else {
            try self.storeImageOwned(allocator, image_id, cmd.image_number, cmd.format, cmd.width, cmd.height, owned);
            if (cmd.action == 'T') {
                const anonymous = image_id == 0 and cmd.image_number == 0;
                return try self.placeStoredImage(allocator, screen, cell_pixel_size, output, encode_buf, .{
                    .unicode_placement = cmd.unicode_placement,
                    .image_id = image_id,
                    .image_number = cmd.image_number,
                    .placement_id = if (anonymous) 0 else cmd.placement_id,
                    .z_index = cmd.z,
                    .anchor_row = render_view.row,
                    .anchor_col = render_view.col,
                    .source_x = cmd.x,
                    .source_y = cmd.y,
                    .source_width = cmd.source_width,
                    .source_height = cmd.source_height,
                    .cell_x_offset = cmd.cell_x_offset,
                    .cell_y_offset = cmd.cell_y_offset,
                    .no_move_cursor = cmd.no_move_cursor,
                    .columns = cmd.columns,
                    .rows = cmd.rows,
                }, cmd.quiet or anonymous);
            }
            if (cmd.image_number != 0 and !cmd.quiet) try appendNumberReply(allocator, output, encode_buf, image_id, cmd.image_number, "OK");
        }
        return null;
    }

    const PlacementRequest = struct {
        unicode_placement: bool = false,
        image_id: u32,
        image_number: u32,
        placement_id: u32,
        z_index: i32,
        anchor_row: u16,
        anchor_col: u16,
        parent_image_id: u32 = 0,
        parent_placement_id: u32 = 0,
        parent_offset_cols: i32 = 0,
        parent_offset_rows: i32 = 0,
        source_x: u32,
        source_y: u32,
        source_width: u32,
        source_height: u32,
        cell_x_offset: u32,
        cell_y_offset: u32,
        no_move_cursor: bool = false,
        columns: u32,
        rows: u32,
    };

    fn placeStoredImage(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, cell_pixel_size: ?CellPixelSize, output: *std.ArrayList(u8), encode_buf: []u8, request: PlacementRequest, quiet: bool) host_state.ApplyError!?CursorMove {
        if (self.findImage(request.image_id) == null) {
            if (!quiet) try appendPlacementReply(allocator, output, encode_buf, request.image_id, request.image_number, request.placement_id, "ENOENT:image not found");
            return null;
        }

        const image = self.images.items[@intCast(self.findImage(request.image_id).?)];
        const source_width = if (request.source_width != 0) request.source_width else image.width;
        const source_height = if (request.source_height != 0) request.source_height else image.height;
        if (request.unicode_placement) {
            if (request.parent_image_id != 0) {
                if (!quiet) try appendPlacementReply(allocator, output, encode_buf, request.image_id, request.image_number, request.placement_id, "EINVAL:virtual placement cannot refer to a parent");
                return null;
            }
            return try self.upsertVirtualPlacement(allocator, output, encode_buf, .{
                .image_id = request.image_id,
                .placement_id = request.placement_id,
                .source_x = request.source_x,
                .source_y = request.source_y,
                .source_width = source_width,
                .source_height = source_height,
                .columns = @max(request.columns, 1),
                .rows = @max(request.rows, 1),
            }, request.image_number, quiet);
        }
        const extent = resolveGridExtent(source_width, source_height, request.cell_x_offset, request.cell_y_offset, request.columns, request.rows, cell_pixel_size);
        const parent = try self.resolveParentPlacement(allocator, output, encode_buf, request.image_id, request.image_number, request.placement_id, request.parent_image_id, request.parent_placement_id, quiet) orelse return null;
        return try self.upsertPlacement(allocator, output, encode_buf, .{
            .parent_is_virtual = parent.is_virtual,
            .image_id = request.image_id,
            .placement_id = request.placement_id,
            .z_index = request.z_index,
            .anchor_row = RowAnchor.initOnScreen(request.anchor_row),
            .anchor_col = request.anchor_col,
            .parent_image_id = parent.image_id,
            .parent_placement_id = parent.placement_id,
            .parent_offset_cols = request.parent_offset_cols,
            .parent_offset_rows = request.parent_offset_rows,
            .source_x = request.source_x,
            .source_y = request.source_y,
            .source_width = source_width,
            .source_height = source_height,
            .cell_x_offset = request.cell_x_offset,
            .cell_y_offset = request.cell_y_offset,
            .columns = request.columns,
            .rows = request.rows,
            .effective_columns = extent.columns,
            .effective_rows = extent.rows,
        }, screen, request.image_number, quiet, request.no_move_cursor);
    }

    pub fn rescaleImplicitPlacements(self: *State, cell: CellPixelSize) void {
        std.debug.assert(cell.width > 0);
        std.debug.assert(cell.height > 0);
        for (self.placements.items) |*placement| {
            if (placement.columns != 0 and placement.rows != 0) continue;
            placement.recomputeExtent(cell);
            validatePlacement(placement.*);
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

    fn storeImageOwned(self: *State, allocator: std.mem.Allocator, image_id: u32, image_number: u32, format: u16, width: u32, height: u32, owned: []u8) host_state.ApplyError!void {
        errdefer allocator.free(owned);
        if (image_id == 0 or self.findImage(image_id) == null) {
            try ensureCountBound(self.images.items.len, image_max_count);
        }
        try ensureRetainedPayloadStore(self, count32(owned), retainedPayloadBytesFreedByImage(self, image_id));
        const image_size = try intrinsicImageSize(format, width, height, owned);
        const image = Image{ .image_id = image_id, .image_number = image_number, .format = format, .width = image_size.width, .height = image_size.height, .base64_payload = owned };
        if (image_id != 0) self.deleteImage(allocator, image_id);
        try self.images.append(allocator, image);
    }

    fn storeFrameOwned(self: *State, allocator: std.mem.Allocator, image_id: u32, frame_number: u32, format: u16, width: u32, height: u32, x: u32, y: u32, base_frame_number: u32, compose_mode: u32, background_rgba: u32, gap: i32, owned: []u8) host_state.ApplyError!void {
        var ownership_transferred = false;
        errdefer if (!ownership_transferred) allocator.free(owned);
        const image_idx = self.findImage(image_id) orelse return;
        const image = &self.images.items[@intCast(image_idx)];

        const target_frame_number = if (frame_number == 0) self.nextFrameNumber(image_id) else frame_number;
        const uses_root_base = base_frame_number == 1;
        const base_frame_id = if (base_frame_number <= 1) 0 else self.frameIdForNumber(image_id, base_frame_number) orelse return;
        const frame_size = try intrinsicImageSize(format, width, height, owned);
        if (!currentFramePublicationFormatSupported(image.format)) return;
        if (!currentFramePublicationFormatSupported(format)) return;
        const png_backed = image.format == 100 or format == 100 or self.frameChainIncludesPng(image.*, base_frame_id);
        if (!png_backed and format != image.format) return;
        if (target_frame_number == 1) {
            if (x != 0 or y != 0 or base_frame_number != 0 or compose_mode != 0 or background_rgba != 0) return;
            try ensureRetainedPayloadStore(self, count32(owned), retainedPayloadBytesFreedByPublishedRoot(self, image_id));
            allocator.free(image.base64_payload);
            image.base64_payload = owned;
            ownership_transferred = true;
            image.width = frame_size.width;
            image.height = frame_size.height;
            image.format = format;
            if (image.current_frame_number != 1) try self.refreshCurrentFramePublication(allocator, @intCast(image_idx));
            return;
        }

        if (self.findFrameIndex(image_id, target_frame_number) == null) {
            try ensureCountBound(self.frames.items.len, frame_max_count);
        }
        try ensureRetainedPayloadStore(self, count32(owned), retainedPayloadBytesFreedByFrame(self, image_id, target_frame_number));

        if (self.findFrameIndex(image_id, target_frame_number)) |existing_idx| {
            const frame = &self.frames.items[@intCast(existing_idx)];
            allocator.free(frame.base64_payload);
            frame.format = format;
            frame.width = frame_size.width;
            frame.height = frame_size.height;
            frame.x = x;
            frame.y = y;
            frame.uses_root_base = uses_root_base;
            frame.base_frame_id = base_frame_id;
            frame.compose_mode = compose_mode;
            frame.background_rgba = background_rgba;
            frame.gap = gap;
            frame.base64_payload = owned;
            ownership_transferred = true;
        } else {
            const frame = Frame{
                .frame_id = image.next_frame_id,
                .image_id = image_id,
                .frame_number = target_frame_number,
                .format = format,
                .width = frame_size.width,
                .height = frame_size.height,
                .x = x,
                .y = y,
                .uses_root_base = uses_root_base,
                .base_frame_id = base_frame_id,
                .compose_mode = compose_mode,
                .background_rgba = background_rgba,
                .gap = gap,
                .base64_payload = owned,
            };
            image.next_frame_id +%= 1;
            if (image.next_frame_id == 0) image.next_frame_id = 1;
            try self.frames.append(allocator, frame);
            ownership_transferred = true;
        }

        if (image.current_frame_number == target_frame_number) {
            try self.refreshCurrentFramePublication(allocator, @intCast(image_idx));
        }
    }

    fn selectCurrentFrame(self: *State, allocator: std.mem.Allocator, image_idx: Index, frame_number: u32) host_state.ApplyError!bool {
        const image = &self.images.items[@intCast(image_idx)];
        if (frame_number == image.current_frame_number) return false;
        if (frame_number != 1 and self.findFrameIndex(image.image_id, frame_number) == null) return false;
        image.current_frame_number = frame_number;
        image.current_frame_shown_at_ns = 0;
        try self.refreshCurrentFramePublication(allocator, image_idx);
        return true;
    }

    fn refreshCurrentFramePublication(self: *State, allocator: std.mem.Allocator, image_idx: Index) host_state.ApplyError!void {
        const image = &self.images.items[@intCast(image_idx)];
        if (image.current_override_payload) |payload| {
            allocator.free(payload);
            image.current_override_payload = null;
        }
        if (image.current_frame_number == 1) return;

        const frame = self.frameByNumber(image.image_id, image.current_frame_number) orelse return;
        const publish_format: u16 = if (self.frameGraphPublishesRgba(image.*, frame)) 32 else frame.format;
        const raw = if (publish_format == 32)
            try self.coalesceFrameRgbaOwned(allocator, image.*, frame)
        else
            try self.coalesceFrameRawOwned(allocator, image.*, frame);
        defer allocator.free(raw);
        const encoded_len = std.base64.standard.Encoder.calcSize(raw.len);
        try ensureRetainedPayloadStore(self, @intCast(encoded_len), 0);
        const encoded = try allocator.alloc(u8, encoded_len);
        _ = std.base64.standard.Encoder.encode(encoded, raw);
        image.current_override_format = publish_format;
        image.current_override_width = image.width;
        image.current_override_height = image.height;
        image.current_override_payload = encoded;
    }

    fn frameGraphPublishesRgba(self: *const State, image: Image, frame: Frame) bool {
        if (image.format == 100) return true;
        if (frame.format == 100) return true;
        if (frame.base_frame_id == 0) return false;
        const base = self.frameById(image.image_id, frame.base_frame_id) orelse unreachable;
        return self.frameGraphPublishesRgba(image, base);
    }

    fn frameChainIncludesPng(self: *const State, image: Image, base_frame_id: u32) bool {
        if (image.format == 100) return true;
        if (base_frame_id == 0) return false;
        const base = self.frameById(image.image_id, base_frame_id) orelse unreachable;
        if (base.format == 100) return true;
        return self.frameChainIncludesPng(image, base.base_frame_id);
    }

    fn coalesceFrameRawOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame: Frame) host_state.ApplyError![]u8 {
        const root = try decodeBase64RawOwned(allocator, image.format, image.width, image.height, image.base64_payload);
        if (frame.uses_root_base) {
            return try self.composeFrameOntoOwned(allocator, image, frame, root);
        }
        if (frame.base_frame_id == 0) {
            return try self.composeStandaloneFrameOwned(allocator, image, frame, root);
        }
        defer allocator.free(root);
        const base = try self.coalesceFrameByIdRawOwned(allocator, image, frame.base_frame_id);
        return try self.composeFrameOntoOwned(allocator, image, frame, base);
    }

    fn coalesceFrameByIdRawOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame_id: u32) host_state.ApplyError![]u8 {
        const frame = self.frameById(image.image_id, frame_id) orelse unreachable;
        return try self.coalesceFrameRawOwned(allocator, image, frame);
    }

    fn coalesceFrameRgbaOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame: Frame) host_state.ApplyError![]u8 {
        const root = try decodeBase64RgbaOwned(allocator, image.format, image.width, image.height, image.base64_payload);
        if (frame.uses_root_base) {
            return try self.composeFrameOntoRgbaOwned(allocator, image, frame, root);
        }
        if (frame.base_frame_id == 0) {
            return try self.composeStandaloneFrameRgbaOwned(allocator, image, frame, root);
        }
        defer allocator.free(root);
        const base = try self.coalesceFrameByIdRgbaOwned(allocator, image, frame.base_frame_id);
        return try self.composeFrameOntoRgbaOwned(allocator, image, frame, base);
    }

    fn coalesceFrameByIdRgbaOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame_id: u32) host_state.ApplyError![]u8 {
        const frame = self.frameById(image.image_id, frame_id) orelse unreachable;
        return try self.coalesceFrameRgbaOwned(allocator, image, frame);
    }

    fn composeStandaloneFrameOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame: Frame, root: []u8) host_state.ApplyError![]u8 {
        _ = self;
        if (frame.x == 0 and frame.y == 0 and frame.width == image.width and frame.height == image.height and frame.background_rgba == 0) {
            allocator.free(root);
            return try decodeBase64RawOwned(allocator, frame.format, frame.width, frame.height, frame.base64_payload);
        }
        const base = try allocateBackgroundRaw(allocator, frame.format, image.width, image.height, frame.background_rgba);
        errdefer allocator.free(base);
        const over = try decodeBase64RawOwned(allocator, frame.format, frame.width, frame.height, frame.base64_payload);
        defer allocator.free(over);
        composeRaw(frame.format, base, image.width, image.height, over, frame.width, frame.height, frame.x, frame.y, frame.compose_mode != 1);
        allocator.free(root);
        return base;
    }

    fn composeFrameOntoOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame: Frame, base: []u8) host_state.ApplyError![]u8 {
        _ = self;
        const under = base;
        errdefer allocator.free(under);
        const over = try decodeBase64RawOwned(allocator, frame.format, frame.width, frame.height, frame.base64_payload);
        defer allocator.free(over);
        composeRaw(frame.format, under, image.width, image.height, over, frame.width, frame.height, frame.x, frame.y, frame.compose_mode != 1);
        return under;
    }

    fn composeStandaloneFrameRgbaOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame: Frame, root: []u8) host_state.ApplyError![]u8 {
        _ = self;
        if (frame.x == 0 and frame.y == 0 and frame.width == image.width and frame.height == image.height and frame.background_rgba == 0) {
            allocator.free(root);
            return try decodeBase64RgbaOwned(allocator, frame.format, frame.width, frame.height, frame.base64_payload);
        }
        const base = try allocateBackgroundRaw(allocator, 32, image.width, image.height, frame.background_rgba);
        errdefer allocator.free(base);
        const over = try decodeBase64RgbaOwned(allocator, frame.format, frame.width, frame.height, frame.base64_payload);
        defer allocator.free(over);
        composeRaw(32, base, image.width, image.height, over, frame.width, frame.height, frame.x, frame.y, frame.compose_mode != 1);
        allocator.free(root);
        return base;
    }

    fn composeFrameOntoRgbaOwned(self: *const State, allocator: std.mem.Allocator, image: Image, frame: Frame, base: []u8) host_state.ApplyError![]u8 {
        _ = self;
        const under = base;
        errdefer allocator.free(under);
        const over = try decodeBase64RgbaOwned(allocator, frame.format, frame.width, frame.height, frame.base64_payload);
        defer allocator.free(over);
        composeRaw(32, under, image.width, image.height, over, frame.width, frame.height, frame.x, frame.y, frame.compose_mode != 1);
        return under;
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
            return self.images.items[@intCast(idx)].image_id;
        }
        return null;
    }

    fn abortUpload(self: *State, allocator: std.mem.Allocator) void {
        if (self.upload) |*upload| upload.data.deinit(allocator);
        self.upload = null;
    }

    fn deleteImage(self: *State, allocator: std.mem.Allocator, image_id: u32) void {
        while (self.findPlacementIndexForImage(image_id)) |idx| {
            const placement = self.placements.items[@intCast(idx)];
            self.deletePlacement(allocator, placement.image_id, placement.placement_id);
        }
        self.deleteVirtualPlacementsForImage(image_id);
        self.deleteImageData(allocator, image_id);
    }

    fn deleteImageData(self: *State, allocator: std.mem.Allocator, image_id: u32) void {
        var idx: Index = 0;
        while (idx < self.imageCount()) {
            if (self.images.items[@intCast(idx)].image_id == image_id) {
                if (self.images.items[@intCast(idx)].current_override_payload) |payload| allocator.free(payload);
                allocator.free(self.images.items[@intCast(idx)].base64_payload);
                _ = self.images.swapRemove(@intCast(idx));
            } else idx += 1;
        }
        idx = 0;
        while (idx < self.placementCount()) {
            if (self.placements.items[@intCast(idx)].image_id == image_id) _ = self.placements.swapRemove(@intCast(idx)) else idx += 1;
        }
        idx = 0;
        while (idx < self.virtualPlacementCount()) {
            if (self.virtual_placements.items[@intCast(idx)].image_id == image_id) {
                _ = self.virtual_placements.swapRemove(@intCast(idx));
            } else idx += 1;
        }
        idx = 0;
        while (idx < self.frameCount()) {
            if (self.frames.items[@intCast(idx)].image_id == image_id) {
                allocator.free(self.frames.items[@intCast(idx)].base64_payload);
                _ = self.frames.swapRemove(@intCast(idx));
            } else idx += 1;
        }
    }

    fn deletePlacement(self: *State, allocator: std.mem.Allocator, image_id: u32, placement_id: u32) void {
        _ = allocator;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const placement = self.placements.items[@intCast(idx)];
            if (placement.image_id == image_id and placement.placement_id == placement_id) {
                _ = self.placements.swapRemove(@intCast(idx));
                continue;
            }
            if (self.placementDescendsFrom(placement, image_id, placement_id)) {
                _ = self.placements.swapRemove(@intCast(idx));
                continue;
            }
            idx += 1;
        }
    }

    fn deleteVirtualPlacement(self: *State, image_id: u32, placement_id: u32) void {
        var child_idx: Index = 0;
        while (child_idx < self.placementCount()) {
            const child = self.placements.items[@intCast(child_idx)];
            if (!child.parent_is_virtual) {
                child_idx += 1;
                continue;
            }
            if (child.parent_image_id != image_id or child.parent_placement_id != placement_id) {
                child_idx += 1;
                continue;
            }
            self.deletePlacement(undefined, child.image_id, child.placement_id);
            child_idx = 0;
        }
        var idx: Index = 0;
        while (idx < self.virtualPlacementCount()) {
            const placement = self.virtual_placements.items[@intCast(idx)];
            if (placement.image_id == image_id and placement.placement_id == placement_id) {
                _ = self.virtual_placements.swapRemove(@intCast(idx));
                continue;
            }
            idx += 1;
        }
    }

    fn deleteVirtualPlacementsForImage(self: *State, image_id: u32) void {
        var idx: Index = 0;
        while (idx < self.virtualPlacementCount()) {
            if (self.virtual_placements.items[@intCast(idx)].image_id == image_id) {
                _ = self.virtual_placements.swapRemove(@intCast(idx));
            } else idx += 1;
        }
    }

    fn deletePlacementsAt(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, x: u32, y: u32, z: ?i32) void {
        if (x == 0 or y == 0) return;
        const col = x - 1;
        const row = y - 1;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const p = self.placements.items[@intCast(idx)];
            const resolved = self.resolvePlacementAnchor(p, screen) orelse {
                idx += 1;
                continue;
            };
            const anchor_row = resolved.row.onScreenRow() orelse {
                idx += 1;
                continue;
            };
            if (resolved.col < 0) {
                idx += 1;
                continue;
            }
            const anchor_col: u32 = @intCast(resolved.col);
            const intersects = col >= anchor_col and col < anchor_col + p.effective_columns and row >= anchor_row and row < anchor_row + p.effective_rows and (z == null or p.z_index == z.?);
            if (intersects) self.deletePlacement(allocator, p.image_id, p.placement_id) else idx += 1;
        }
    }

    fn deletePlacementsInColumn(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, x: u32) void {
        if (x == 0) return;
        const col = x - 1;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const p = self.placements.items[@intCast(idx)];
            const resolved = self.resolvePlacementAnchor(p, screen) orelse {
                idx += 1;
                continue;
            };
            if (resolved.col < 0) {
                idx += 1;
                continue;
            }
            const anchor_col: u32 = @intCast(resolved.col);
            if (col >= anchor_col and col < anchor_col + p.effective_columns) self.deletePlacement(allocator, p.image_id, p.placement_id) else idx += 1;
        }
    }

    fn deletePlacementsInRow(self: *State, allocator: std.mem.Allocator, screen: *const screen_mod.Screen, y: u32) void {
        if (y == 0) return;
        const row = y - 1;
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const p = self.placements.items[@intCast(idx)];
            const resolved = self.resolvePlacementAnchor(p, screen) orelse {
                idx += 1;
                continue;
            };
            const anchor_row = resolved.row.onScreenRow() orelse {
                idx += 1;
                continue;
            };
            if (row >= anchor_row and row < anchor_row + p.effective_rows) self.deletePlacement(allocator, p.image_id, p.placement_id) else idx += 1;
        }
    }

    fn deletePlacementsByZ(self: *State, allocator: std.mem.Allocator, z: i32) void {
        var idx: Index = 0;
        while (idx < self.placementCount()) {
            const placement = self.placements.items[@intCast(idx)];
            if (placement.z_index == z) self.deletePlacement(allocator, placement.image_id, placement.placement_id) else idx += 1;
        }
    }

    fn deleteImagesInRange(self: *State, allocator: std.mem.Allocator, first: u32, last: u32) void {
        const lo = @min(first, last);
        const hi = @max(first, last);
        var idx: Index = 0;
        while (idx < self.imageCount()) {
            const image_id = self.images.items[@intCast(idx)].image_id;
            if (image_id >= lo and image_id <= hi) self.deleteImage(allocator, image_id) else idx += 1;
        }
    }

    fn deleteUnplacedImages(self: *State, allocator: std.mem.Allocator) void {
        var idx: Index = 0;
        while (idx < self.imageCount()) {
            const image_id = self.images.items[@intCast(idx)].image_id;
            if (!self.imageHasPlacement(image_id)) self.deleteImage(allocator, image_id) else idx += 1;
        }
    }

    fn imageHasPlacement(self: *const State, image_id: u32) bool {
        for (self.placements.items) |placement| if (placement.image_id == image_id) return true;
        for (self.virtual_placements.items) |placement| if (placement.image_id == image_id) return true;
        return false;
    }

    fn findVirtualPlacementIndex(self: *const State, image_id: u32, placement_id: u32) ?Index {
        for (self.virtual_placements.items, 0..) |placement, idx| {
            if (placement.image_id != image_id) continue;
            if (placement.placement_id == placement_id) return @intCast(idx);
        }
        return null;
    }

    fn firstVirtualPlacementIndexForImage(self: *const State, image_id: u32) ?Index {
        for (self.virtual_placements.items, 0..) |placement, idx| {
            if (placement.image_id == image_id) return @intCast(idx);
        }
        return null;
    }

    fn findPlacementIndex(self: *const State, image_id: u32, placement_id: u32) ?Index {
        for (self.placements.items, 0..) |placement, idx| {
            if (placement.image_id != image_id) continue;
            if (placement.placement_id == placement_id) return @intCast(idx);
        }
        return null;
    }

    fn findPlacementIndexForImage(self: *const State, image_id: u32) ?Index {
        for (self.placements.items, 0..) |placement, idx| {
            if (placement.image_id == image_id) return @intCast(idx);
        }
        return null;
    }

    fn firstPlacementIndexForImage(self: *const State, image_id: u32) ?Index {
        for (self.placements.items, 0..) |placement, idx| {
            if (placement.image_id == image_id) return @intCast(idx);
        }
        return null;
    }

    fn placementDescendsFrom(self: *const State, placement: Placement, image_id: u32, placement_id: u32) bool {
        var current = placement;
        var depth: u32 = 0;
        while (current.parent_image_id != 0) {
            if (depth >= parent_depth_limit) return false;
            if (current.parent_image_id == image_id and current.parent_placement_id == placement_id) return true;
            if (current.parent_is_virtual) return false;
            const parent_idx = self.findPlacementIndex(current.parent_image_id, current.parent_placement_id) orelse return false;
            current = self.placements.items[@intCast(parent_idx)];
            depth += 1;
        }
        return false;
    }

    fn resolveParentPlacement(self: *const State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, image_id: u32, image_number: u32, placement_id: u32, parent_image_id: u32, parent_placement_id: u32, quiet: bool) host_state.ApplyError!?ParentPlacementRef {
        if (parent_image_id == 0) return .{ .image_id = 0, .placement_id = 0, .is_virtual = false };
        if (self.findImage(parent_image_id) == null) {
            if (!quiet) try appendPlacementReply(allocator, output, encode_buf, image_id, image_number, placement_id, "ENOPARENT:parent image not found");
            return null;
        }
        const parent = if (parent_placement_id != 0)
            self.parentPlacementById(parent_image_id, parent_placement_id)
        else
            self.firstParentPlacementForImage(parent_image_id);
        const resolved_parent = parent orelse {
            if (!quiet) try appendPlacementReply(allocator, output, encode_buf, image_id, image_number, placement_id, "ENOPARENT:parent placement not found");
            return null;
        };
        if (placement_id != 0 and image_id == resolved_parent.image_id and placement_id == resolved_parent.placement_id) {
            if (!quiet) try appendPlacementReply(allocator, output, encode_buf, image_id, image_number, placement_id, "EINVAL:placement cannot parent itself");
            return null;
        }
        return resolved_parent;
    }

    fn upsertPlacement(self: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, placement: Placement, screen: *const screen_mod.Screen, image_number: u32, quiet: bool, no_move_cursor: bool) host_state.ApplyError!?CursorMove {
        if (placement.hasParent()) {
            const ok = try self.validatePlacementAncestry(allocator, output, encode_buf, placement, image_number, quiet);
            if (!ok) return null;
        }
        if (placement.placement_id != 0) {
            if (self.findPlacementIndex(placement.image_id, placement.placement_id)) |idx| {
                self.placements.items[@intCast(idx)] = placement;
                validatePlacement(self.placements.items[@intCast(idx)]);
                if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "OK");
                if (placement.hasParent() or no_move_cursor) {
                    _ = self.resolvePlacementAnchor(placement, screen) orelse return null;
                    return null;
                }
                return .{ .cols = placement.effective_columns, .rows = placement.effective_rows };
            }
        }
        try ensureCountBound(self.placements.items.len, placement_max_count);
        try self.placements.append(allocator, placement);
        validatePlacement(self.placements.items[self.placements.items.len - 1]);
        if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "OK");
        if (placement.hasParent() or no_move_cursor) {
            _ = self.resolvePlacementAnchor(placement, screen) orelse return null;
            return null;
        }
        return .{ .cols = placement.effective_columns, .rows = placement.effective_rows };
    }

    fn upsertVirtualPlacement(self: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, placement: VirtualPlacement, image_number: u32, quiet: bool) host_state.ApplyError!?CursorMove {
        placement.validate();
        if (placement.placement_id != 0) {
            if (self.findVirtualPlacementIndex(placement.image_id, placement.placement_id)) |idx| {
                self.virtual_placements.items[@intCast(idx)] = placement;
                if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "OK");
                return null;
            }
        }
        try ensureCountBound(self.virtual_placements.items.len, placement_max_count);
        try self.virtual_placements.append(allocator, placement);
        if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "OK");
        return null;
    }

    fn validatePlacementAncestry(self: *const State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, placement: Placement, image_number: u32, quiet: bool) host_state.ApplyError!bool {
        var depth: u32 = 0;
        var current_image_id = placement.parent_image_id;
        var current_placement_id = placement.parent_placement_id;
        while (current_image_id != 0) {
            if (current_image_id == placement.image_id and current_placement_id == placement.placement_id) {
                if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "ECYCLE:relative placement cycle");
                return false;
            }
            if (depth >= parent_depth_limit) {
                if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "ETOODEEP:relative placement depth exceeded");
                return false;
            }
            const parent = self.parentPlacementById(current_image_id, current_placement_id) orelse {
                if (!quiet) try appendPlacementReply(allocator, output, encode_buf, placement.image_id, image_number, placement.placement_id, "ENOPARENT:ancestor placement not found");
                return false;
            };
            if (parent.is_virtual) return true;
            current_image_id = parent.parent_image_id;
            current_placement_id = parent.parent_placement_id;
            depth += 1;
        }
        return true;
    }

    fn resolvePlacementAnchor(self: *const State, placement: Placement, screen: *const screen_mod.Screen) ?struct { row: RowAnchor, col: i32 } {
        var current = placement;
        var depth: u32 = 0;
        var offset_rows: i64 = 0;
        var offset_cols: i64 = 0;
        while (current.parent_image_id != 0) {
            if (depth >= parent_depth_limit) return null;
            offset_rows = std.math.add(i64, offset_rows, current.parent_offset_rows) catch return null;
            offset_cols = std.math.add(i64, offset_cols, current.parent_offset_cols) catch return null;
            if (current.parent_is_virtual) {
                const parent = self.resolveVirtualParentAnchor(screen, current.parent_image_id, current.parent_placement_id) orelse return null;
                const row = offsetRowAnchor(parent.row, offset_rows, screen.rows) orelse return null;
                const col = std.math.add(i64, parent.col, offset_cols) catch return null;
                return .{ .row = row, .col = std.math.cast(i32, col) orelse return null };
            }
            const parent_idx = self.findPlacementIndex(current.parent_image_id, current.parent_placement_id) orelse return null;
            current = self.placements.items[@intCast(parent_idx)];
            depth += 1;
        }
        const row = offsetRowAnchor(current.anchor_row, offset_rows, screen.rows) orelse return null;
        const col = std.math.add(i64, current.anchor_col, offset_cols) catch return null;
        return .{ .row = row, .col = std.math.cast(i32, col) orelse return null };
    }

    fn firstParentPlacementForImage(self: *const State, image_id: u32) ?ParentPlacementRef {
        if (self.firstPlacementIndexForImage(image_id)) |idx| {
            const placement = self.placements.items[@intCast(idx)];
            return .{ .image_id = placement.image_id, .placement_id = placement.placement_id, .is_virtual = false, .parent_image_id = placement.parent_image_id, .parent_placement_id = placement.parent_placement_id };
        }
        if (self.firstVirtualPlacementIndexForImage(image_id)) |idx| {
            const placement = self.virtual_placements.items[@intCast(idx)];
            return .{ .image_id = placement.image_id, .placement_id = placement.placement_id, .is_virtual = true };
        }
        return null;
    }

    fn parentPlacementById(self: *const State, image_id: u32, placement_id: u32) ?ParentPlacementRef {
        if (self.findPlacementIndex(image_id, placement_id)) |idx| {
            const placement = self.placements.items[@intCast(idx)];
            return .{ .image_id = placement.image_id, .placement_id = placement.placement_id, .is_virtual = false, .parent_image_id = placement.parent_image_id, .parent_placement_id = placement.parent_placement_id };
        }
        if (self.findVirtualPlacementIndex(image_id, placement_id)) |idx| {
            const placement = self.virtual_placements.items[@intCast(idx)];
            return .{ .image_id = placement.image_id, .placement_id = placement.placement_id, .is_virtual = true };
        }
        return null;
    }

    fn resolveVirtualParentAnchor(self: *const State, screen: *const screen_mod.Screen, image_id: u32, placement_id: u32) ?PlaceholderParentMatch {
        _ = self;
        var best_row: ?RowAnchor = null;
        var best_row_pos: i32 = 0;
        var best_col: ?u16 = null;

        var history_idx: u32 = 0;
        while (history_idx < screen.historyCount()) : (history_idx += 1) {
            const row = RowAnchor{ .scrollback_above = history_idx + 1 };
            scanPlaceholderParentRow(screen, .{ .history = history_idx }, row, image_id, placement_id, &best_row, &best_row_pos, &best_col);
        }

        var row_idx: u16 = 0;
        while (row_idx < screen.rows) : (row_idx += 1) {
            const row = RowAnchor.initOnScreen(row_idx);
            scanPlaceholderParentRow(screen, .{ .screen = row_idx }, row, image_id, placement_id, &best_row, &best_row_pos, &best_col);
        }

        return .{ .row = best_row orelse return null, .col = best_col orelse return null };
    }

    fn deleteFrames(self: *State, allocator: std.mem.Allocator, cmd: KittyGraphicsCommand) void {
        const image_id = self.resolveImageId(cmd) orelse cmd.image_id;
        const deleted_frame_number = cmd.edit_frame_number;
        var idx: Index = 0;
        while (idx < self.frameCount()) {
            const frame = self.frames.items[@intCast(idx)];
            if ((image_id == 0 or frame.image_id == image_id) and (deleted_frame_number == 0 or frame.frame_number == deleted_frame_number)) {
                allocator.free(self.frames.items[@intCast(idx)].base64_payload);
                _ = self.frames.swapRemove(@intCast(idx));
            } else idx += 1;
        }
        if (image_id != 0) self.repairImageAfterFrameDelete(allocator, image_id, deleted_frame_number);
    }

    fn repairImageAfterFrameDelete(self: *State, allocator: std.mem.Allocator, image_id: u32, deleted_frame_number: u32) void {
        const image_idx = self.findImage(image_id) orelse return;
        const image = &self.images.items[@intCast(image_idx)];
        if (deleted_frame_number != 0 and image.current_frame_number == deleted_frame_number) {
            image.current_frame_number = 1;
        } else if (deleted_frame_number != 0 and image.current_frame_number > deleted_frame_number) {
            image.current_frame_number -= 1;
        }
        var frame_idx: Index = 0;
        while (frame_idx < self.frameCount()) : (frame_idx += 1) {
            var frame = &self.frames.items[@intCast(frame_idx)];
            if (frame.image_id != image_id) continue;
            if (deleted_frame_number != 0 and frame.frame_number > deleted_frame_number) frame.frame_number -= 1;
        }
        self.refreshCurrentFramePublication(allocator, image_idx) catch {};
    }

    fn findFrameIndex(self: *const State, image_id: u32, frame_number: u32) ?Index {
        for (self.frames.items, 0..) |frame, idx| {
            if (frame.image_id != image_id) continue;
            if (frame.frame_number == frame_number) return @intCast(idx);
        }
        return null;
    }

    fn frameByNumber(self: *const State, image_id: u32, frame_number: u32) ?Frame {
        const idx = self.findFrameIndex(image_id, frame_number) orelse return null;
        return self.frames.items[@intCast(idx)];
    }

    fn frameById(self: *const State, image_id: u32, frame_id: u32) ?Frame {
        for (self.frames.items) |frame| {
            if (frame.image_id != image_id) continue;
            if (frame.frame_id == frame_id) return frame;
        }
        return null;
    }

    fn frameIdForNumber(self: *const State, image_id: u32, frame_number: u32) ?u32 {
        if (frame_number == 1) return 0;
        const frame = self.frameByNumber(image_id, frame_number) orelse return null;
        return frame.frame_id;
    }

    fn nextFrameNumber(self: *const State, image_id: u32) u32 {
        var next: u32 = 2;
        for (self.frames.items) |frame| {
            if (frame.image_id != image_id) continue;
            if (frame.frame_number >= next) next = frame.frame_number + 1;
        }
        return next;
    }
};

fn retainedPayloadBytes(self: *const State) u32 {
    var total: u32 = 0;
    for (self.images.items) |image| {
        total = addPayloadBytes(total, image.base64_payload.len);
        if (image.current_override_payload) |payload| total = addPayloadBytes(total, payload.len);
    }
    for (self.frames.items) |frame| total = addPayloadBytes(total, frame.base64_payload.len);
    if (self.upload) |upload| total = addPayloadBytes(total, upload.data.items.len);
    return total;
}

fn imageNeedsRuntime(self: *const State, image: Image) bool {
    return image.animation_state != .stopped and self.frameCountForImage(image.image_id) > 1;
}

fn gapToNs(gap_ms: i32) ?u64 {
    if (gap_ms <= 0) return null;
    return std.math.mul(u64, @intCast(gap_ms), std.time.ns_per_ms) catch null;
}

fn retainedPayloadBytesFreedByImage(self: *const State, image_id: u32) u32 {
    if (image_id == 0) return 0;
    var total: u32 = 0;
    for (self.images.items) |image| {
        if (image.image_id == image_id) {
            total = addPayloadBytes(total, image.base64_payload.len);
            if (image.current_override_payload) |payload| total = addPayloadBytes(total, payload.len);
        }
    }
    for (self.frames.items) |frame| {
        if (frame.image_id == image_id) total = addPayloadBytes(total, frame.base64_payload.len);
    }
    return total;
}

fn retainedPayloadBytesFreedByFrame(self: *const State, image_id: u32, frame_number: u32) u32 {
    const frame = self.frameByNumber(image_id, frame_number) orelse return 0;
    return addPayloadBytes(0, frame.base64_payload.len);
}

fn retainedPayloadBytesFreedByPublishedRoot(self: *const State, image_id: u32) u32 {
    const idx = self.findImage(image_id) orelse return 0;
    const image = self.images.items[@intCast(idx)];
    return addPayloadBytes(0, image.base64_payload.len);
}

fn decodeBase64RawOwned(allocator: std.mem.Allocator, format: u16, width: u32, height: u32, payload: []const u8) host_state.ApplyError![]u8 {
    const raw_len = expectedRawPayloadLen(format, width, height) catch unreachable;
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(payload) catch unreachable;
    std.debug.assert(decoded_len == raw_len);
    const raw = try allocator.alloc(u8, raw_len);
    errdefer allocator.free(raw);
    std.base64.standard.Decoder.decode(raw, payload) catch unreachable;
    return raw;
}

fn decodeBase64RgbaOwned(allocator: std.mem.Allocator, format: u16, width: u32, height: u32, payload: []const u8) host_state.ApplyError![]u8 {
    return switch (format) {
        24 => try decodeBase64RgbExpandedOwned(allocator, width, height, payload),
        32 => try decodeBase64RawOwned(allocator, format, width, height, payload),
        100 => try decodeBase64PngRgbaOwned(allocator, width, height, payload),
        else => unreachable,
    };
}

fn currentFramePublicationFormatSupported(format: u16) bool {
    return format == 24 or format == 32 or format == 100;
}

fn decodeBase64RgbExpandedOwned(allocator: std.mem.Allocator, width: u32, height: u32, payload: []const u8) host_state.ApplyError![]u8 {
    const rgb = try decodeBase64RawOwned(allocator, 24, width, height, payload);
    defer allocator.free(rgb);

    const pixel_count = std.math.mul(u64, width, height) catch return error.ConsequenceLimit;
    const rgba_len = std.math.mul(u64, pixel_count, 4) catch return error.ConsequenceLimit;
    const rgba = try allocator.alloc(u8, std.math.cast(usize, rgba_len) orelse return error.ConsequenceLimit);
    errdefer allocator.free(rgba);

    var src_index: usize = 0;
    var dst_index: usize = 0;
    while (src_index < rgb.len) : (src_index += 3) {
        rgba[dst_index] = rgb[src_index];
        rgba[dst_index + 1] = rgb[src_index + 1];
        rgba[dst_index + 2] = rgb[src_index + 2];
        rgba[dst_index + 3] = 255;
        dst_index += 4;
    }
    return rgba;
}

fn decodeBase64PngRgbaOwned(allocator: std.mem.Allocator, width: u32, height: u32, payload: []const u8) host_state.ApplyError![]u8 {
    const png_len = std.base64.standard.Decoder.calcSizeForSlice(payload) catch unreachable;
    const png_bytes = try allocator.alloc(u8, png_len);
    defer allocator.free(png_bytes);
    std.base64.standard.Decoder.decode(png_bytes, payload) catch unreachable;

    var image_size = decodePngSize(png_bytes);
    const ptr = c.stbi_load_from_memory(png_bytes.ptr, @intCast(png_bytes.len), &image_size.width, &image_size.height, &image_size.comp, 4) orelse unreachable;
    defer c.stbi_image_free(ptr);

    const decoded_width_u32: u32 = @intCast(image_size.width);
    const decoded_height_u32: u32 = @intCast(image_size.height);
    std.debug.assert(decoded_width_u32 == width);
    std.debug.assert(decoded_height_u32 == height);

    const stride = std.math.mul(u64, width, 4) catch return error.ConsequenceLimit;
    const raw_len = std.math.mul(u64, stride, height) catch return error.ConsequenceLimit;
    const raw_len_usize = std.math.cast(usize, raw_len) orelse return error.ConsequenceLimit;
    const pixels = @as([*]const u8, @ptrCast(ptr))[0..raw_len_usize];
    return try allocator.dupe(u8, pixels);
}

const PngImageSize = struct {
    width: c_int,
    height: c_int,
    comp: c_int,
};

fn intrinsicImageSize(format: u16, width: u32, height: u32, payload: []const u8) host_state.ApplyError!struct { width: u32, height: u32 } {
    if (format != 100) return .{ .width = width, .height = height };
    const image_size = try decodeBase64PngSize(payload);
    return .{ .width = image_size.width, .height = image_size.height };
}

fn decodeBase64PngSize(payload: []const u8) host_state.ApplyError!struct { width: u32, height: u32 } {
    const png_len = std.base64.standard.Decoder.calcSizeForSlice(payload) catch unreachable;
    const png_bytes = try std.heap.c_allocator.alloc(u8, png_len);
    defer std.heap.c_allocator.free(png_bytes);
    std.base64.standard.Decoder.decode(png_bytes, payload) catch unreachable;
    const image_size = decodePngSize(png_bytes);
    return .{ .width = @intCast(image_size.width), .height = @intCast(image_size.height) };
}

fn decodePngSize(png_bytes: []const u8) PngImageSize {
    var width: c_int = 0;
    var height: c_int = 0;
    var comp: c_int = 0;
    const ok = c.stbi_info_from_memory(png_bytes.ptr, @intCast(png_bytes.len), &width, &height, &comp);
    std.debug.assert(ok != 0);
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);
    return .{ .width = width, .height = height, .comp = comp };
}

fn allocateBackgroundRaw(allocator: std.mem.Allocator, format: u16, width: u32, height: u32, rgba: u32) host_state.ApplyError![]u8 {
    const raw_len = expectedRawPayloadLen(format, width, height) catch unreachable;
    const raw = try allocator.alloc(u8, raw_len);
    errdefer allocator.free(raw);
    const r: u8 = @intCast((rgba >> 24) & 0xff);
    const g: u8 = @intCast((rgba >> 16) & 0xff);
    const b: u8 = @intCast((rgba >> 8) & 0xff);
    const a: u8 = @intCast(rgba & 0xff);
    if (format == 24) {
        var i: usize = 0;
        while (i < raw.len) : (i += 3) {
            raw[i] = r;
            raw[i + 1] = g;
            raw[i + 2] = b;
        }
    } else {
        var i: usize = 0;
        while (i < raw.len) : (i += 4) {
            raw[i] = r;
            raw[i + 1] = g;
            raw[i + 2] = b;
            raw[i + 3] = a;
        }
    }
    return raw;
}

fn composeRaw(format: u16, under: []u8, under_width: u32, under_height: u32, over: []const u8, over_width: u32, over_height: u32, offset_x: u32, offset_y: u32, alpha_blend: bool) void {
    const bytes_per_pixel: usize = if (format == 24) 3 else 4;
    var y: u32 = 0;
    while (y < over_height and y + offset_y < under_height) : (y += 1) {
        var x: u32 = 0;
        while (x < over_width and x + offset_x < under_width) : (x += 1) {
            const under_idx = (@as(usize, @intCast((y + offset_y) * under_width + (x + offset_x)))) * bytes_per_pixel;
            const over_idx = (@as(usize, @intCast(y * over_width + x))) * bytes_per_pixel;
            if (format == 24 or !alpha_blend) {
                @memcpy(under[under_idx .. under_idx + bytes_per_pixel], over[over_idx .. over_idx + bytes_per_pixel]);
                continue;
            }
            alphaBlendRgba(under[under_idx .. under_idx + 4], over[over_idx .. over_idx + 4]);
        }
    }
}

fn alphaBlendRgba(under: []u8, over: []const u8) void {
    const src_alpha: f32 = @as(f32, @floatFromInt(over[3])) / 255.0;
    if (src_alpha == 0) return;
    const dst_alpha: f32 = @as(f32, @floatFromInt(under[3])) / 255.0;
    const out_alpha = src_alpha + (dst_alpha * (1.0 - src_alpha));
    if (out_alpha == 0) {
        under[0] = 0;
        under[1] = 0;
        under[2] = 0;
        under[3] = 0;
        return;
    }
    var channel: usize = 0;
    while (channel < 3) : (channel += 1) {
        const src = @as(f32, @floatFromInt(over[channel]));
        const dst = @as(f32, @floatFromInt(under[channel]));
        const mixed = ((src * src_alpha) + (dst * dst_alpha * (1.0 - src_alpha))) / out_alpha;
        under[channel] = @intFromFloat(@round(mixed));
    }
    under[3] = @intFromFloat(@round(out_alpha * 255.0));
}

fn addPayloadBytes(total: u32, len: usize) u32 {
    const payload_len = count32Len(len);
    return std.math.add(u32, total, payload_len) catch retained_payload_max_bytes + 1;
}

fn count32Len(len: usize) u32 {
    std.debug.assert(len <= std.math.maxInt(u32));
    return @intCast(len);
}

fn graphicsMediumSupported(medium: u8) bool {
    return medium == 'd' or medium == 'f' or medium == 't' or medium == 's';
}

fn graphicsCompressionSupported(cmd: KittyGraphicsCommand) bool {
    if (cmd.compression == 0) return true;
    if (cmd.compression != 'z') return false;
    if (cmd.action != 't' and cmd.action != 'T' and cmd.action != 'f') return false;
    if (cmd.format == 24 or cmd.format == 32) return true;
    return false;
}

fn loadIndirectPayloadNormalized(allocator: std.mem.Allocator, cmd: KittyGraphicsCommand) (MediaLoadError || host_state.ApplyError)![]u8 {
    if (!graphicsCompressionSupported(cmd)) return error.InvalidGraphicsCompression;

    const locator = try decodeGraphicsLocator(allocator, cmd.payload);
    defer allocator.free(locator);

    const transport = try loadGraphicsMediumBytes(allocator, cmd, locator);
    defer allocator.free(transport);

    if (cmd.compression == 0) {
        const encoded_len = std.base64.standard.Encoder.calcSize(transport.len);
        try ensureRetainedPayloadStoreForLen(encoded_len);

        const encoded = try allocator.alloc(u8, encoded_len);
        _ = std.base64.standard.Encoder.encode(encoded, transport);
        return encoded;
    }

    const raw = try decompressRawPayloadOwned(allocator, cmd.format, cmd.width, cmd.height, transport);
    defer allocator.free(raw);

    const encoded_len = std.base64.standard.Encoder.calcSize(raw.len);
    try ensureRetainedPayloadStoreForLen(encoded_len);

    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, raw);
    return encoded;
}

fn decodeGraphicsLocator(allocator: std.mem.Allocator, payload: []const u8) (MediaLoadError || host_state.ApplyError)![]u8 {
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(payload) catch return error.InvalidGraphicsLocator;
    try ensureRetainedPayloadStoreForLen(decoded_len);
    const decoded = try allocator.alloc(u8, decoded_len);
    errdefer allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, payload) catch return error.InvalidGraphicsLocator;
    return decoded;
}

fn loadGraphicsMediumBytes(allocator: std.mem.Allocator, cmd: KittyGraphicsCommand, locator: []const u8) (MediaLoadError || host_state.ApplyError)![]u8 {
    return switch (cmd.medium) {
        'f' => try loadGraphicsFileBytes(allocator, cmd, locator, false),
        't' => try loadGraphicsFileBytes(allocator, cmd, locator, true),
        's' => try loadGraphicsSharedMemoryBytes(allocator, cmd, locator),
        else => error.InvalidGraphicsMedium,
    };
}

fn loadGraphicsFileBytes(allocator: std.mem.Allocator, cmd: KittyGraphicsCommand, locator: []const u8, temporary: bool) (MediaLoadError || host_state.ApplyError)![]u8 {
    const path_z = try allocator.dupeZ(u8, locator);
    defer allocator.free(path_z);

    const path = path_z[0 .. path_z.len - 1];
    const fd = openGraphicsFile(path_z) catch return error.GraphicsIo;
    defer _ = c.close(fd);

    var stat: c.struct_stat = undefined;
    if (c.fstat(fd, &stat) != 0) return error.GraphicsIo;
    if ((stat.st_mode & c.S_IFMT) != c.S_IFREG) return error.GraphicsIo;

    const bytes = try readGraphicsBytes(allocator, fd, @intCast(stat.st_size), cmd);
    if (temporary and tempFileDeletable(path)) {
        _ = c.unlink(path_z);
    }
    return bytes;
}

fn loadGraphicsSharedMemoryBytes(allocator: std.mem.Allocator, cmd: KittyGraphicsCommand, locator: []const u8) (MediaLoadError || host_state.ApplyError)![]u8 {
    const name_z = try allocator.dupeZ(u8, locator);
    defer allocator.free(name_z);

    const fd = c.shm_open(name_z, c.O_RDONLY, 0);
    if (fd < 0) return error.GraphicsIo;
    defer _ = c.close(fd);
    defer _ = c.shm_unlink(name_z);

    var stat: c.struct_stat = undefined;
    if (c.fstat(fd, &stat) != 0) return error.GraphicsIo;
    return try readGraphicsBytes(allocator, fd, @intCast(stat.st_size), cmd);
}

fn openGraphicsFile(path_z: [:0]u8) !c_int {
    const fd = c.open(path_z, c.O_RDONLY | c.O_CLOEXEC | c.O_NONBLOCK);
    if (fd < 0) return error.OpenFailed;
    return fd;
}

fn readGraphicsBytes(allocator: std.mem.Allocator, fd: c_int, file_size: u64, cmd: KittyGraphicsCommand) (MediaLoadError || host_state.ApplyError)![]u8 {
    const offset = @as(u64, cmd.data_offset);
    if (offset > file_size) return error.InvalidGraphicsData;

    const read_len = try graphicsReadLength(file_size, cmd, offset);
    try ensureRetainedPayloadStoreForLen(read_len);

    const bytes = try allocator.alloc(u8, read_len);
    errdefer allocator.free(bytes);
    if (read_len == 0) return bytes;

    var total: usize = 0;
    while (total < read_len) {
        const next_offset = std.math.add(u64, offset, total) catch return error.InvalidGraphicsData;
        const got = c.pread(fd, bytes.ptr + total, read_len - total, @intCast(next_offset));
        if (got < 0) return error.GraphicsIo;
        if (got == 0) return error.InvalidGraphicsData;
        total += @intCast(got);
    }
    return bytes;
}

fn graphicsReadLength(file_size: u64, cmd: KittyGraphicsCommand, offset: u64) (MediaLoadError || host_state.ApplyError)!usize {
    if (cmd.data_size != 0) {
        const read_len: usize = cmd.data_size;
        if (offset + read_len > file_size) return error.InvalidGraphicsData;
        return read_len;
    }

    if (cmd.compression == 'z') {
        if (cmd.format == 100) return error.InvalidGraphicsCompression;
        const available = file_size - offset;
        return std.math.cast(usize, available) orelse return error.ConsequenceLimit;
    }

    if (cmd.format == 24 or cmd.format == 32) {
        if (cmd.width == 0 or cmd.height == 0) return error.InvalidGraphicsData;
        const bytes_per_pixel: u32 = if (cmd.format == 24) 3 else 4;
        const pixels = std.math.mul(u64, cmd.width, cmd.height) catch return error.ConsequenceLimit;
        const raw_len = std.math.mul(u64, pixels, bytes_per_pixel) catch return error.ConsequenceLimit;
        if (offset + raw_len > file_size) return error.InvalidGraphicsData;
        return std.math.cast(usize, raw_len) orelse return error.ConsequenceLimit;
    }

    if (cmd.format == 100) {
        const available = file_size - offset;
        return std.math.cast(usize, available) orelse return error.ConsequenceLimit;
    }

    return error.InvalidGraphicsData;
}

fn ensureRetainedPayloadStoreForLen(len: usize) host_state.ApplyError!void {
    const len32 = std.math.cast(u32, len) orelse return error.ConsequenceLimit;
    if (len32 > retained_payload_max_bytes) return error.ConsequenceLimit;
}

fn normalizeDirectPayloadOwned(allocator: std.mem.Allocator, compression: u8, format: u16, width: u32, height: u32, payload: []const u8) (error{ InvalidGraphicsCompression, InvalidGraphicsData } || host_state.ApplyError)![]u8 {
    if (compression == 0) return try allocator.dupe(u8, payload);
    if (compression != 'z') return error.InvalidGraphicsCompression;

    const compressed_len = std.base64.standard.Decoder.calcSizeForSlice(payload) catch return error.InvalidGraphicsData;
    try ensureRetainedPayloadStoreForLen(compressed_len);

    const compressed = try allocator.alloc(u8, compressed_len);
    defer allocator.free(compressed);
    std.base64.standard.Decoder.decode(compressed, payload) catch return error.InvalidGraphicsData;

    const raw = try decompressRawPayloadOwned(allocator, format, width, height, compressed);
    defer allocator.free(raw);

    const encoded_len = std.base64.standard.Encoder.calcSize(raw.len);
    try ensureRetainedPayloadStoreForLen(encoded_len);

    const encoded = try allocator.alloc(u8, encoded_len);
    _ = std.base64.standard.Encoder.encode(encoded, raw);
    return encoded;
}

fn decompressRawPayloadOwned(allocator: std.mem.Allocator, format: u16, width: u32, height: u32, compressed: []const u8) (error{ InvalidGraphicsCompression, InvalidGraphicsData } || host_state.ApplyError)![]u8 {
    const raw_len = try expectedRawPayloadLen(format, width, height);
    try ensureRetainedPayloadStoreForLen(raw_len);

    const raw = try allocator.alloc(u8, raw_len);
    errdefer allocator.free(raw);
    if (raw.len == 0) return raw;

    var input = std.Io.Reader.fixed(compressed);
    var writer = std.Io.Writer.fixed(raw);
    var decompress: std.compress.flate.Decompress = .init(&input, .zlib, &.{});
    const written = decompress.reader.streamRemaining(&writer) catch return error.InvalidGraphicsData;
    if (written != raw.len) return error.InvalidGraphicsData;
    return raw;
}

fn expectedRawPayloadLen(format: u16, width: u32, height: u32) (error{ InvalidGraphicsCompression, InvalidGraphicsData } || host_state.ApplyError)!usize {
    if (format != 24 and format != 32) return error.InvalidGraphicsCompression;
    if (width == 0 or height == 0) return error.InvalidGraphicsData;

    const bytes_per_pixel: u32 = if (format == 24) 3 else 4;
    const pixels = std.math.mul(u64, width, height) catch return error.ConsequenceLimit;
    const raw_len = std.math.mul(u64, pixels, bytes_per_pixel) catch return error.ConsequenceLimit;
    return std.math.cast(usize, raw_len) orelse return error.ConsequenceLimit;
}

fn tempFileDeletable(path: []const u8) bool {
    if (std.mem.indexOf(u8, path, "tty-graphics-protocol") == null) return false;
    if (std.mem.startsWith(u8, path, "/tmp/")) return true;
    if (std.mem.startsWith(u8, path, "/dev/shm/")) return true;
    return false;
}

fn ensureCountBound(current_len: usize, max_len: Count) host_state.ApplyError!void {
    if (current_len < max_len) return;
    return error.ConsequenceLimit;
}

fn scanPlaceholderParentRow(
    screen: *const screen_mod.Screen,
    source: union(enum) { history: u32, screen: u16 },
    row: RowAnchor,
    image_id: u32,
    placement_id: u32,
    best_row: *?RowAnchor,
    best_row_pos: *i32,
    best_col: *?u16,
) void {
    var col: u16 = 0;
    while (col < screen.cols) : (col += 1) {
        const cell = switch (source) {
            .history => |history_idx| screen.historyCellAt(history_idx, col),
            .screen => |screen_row| screen.cellInfoAt(screen_row, col),
        };
        if (screen_mod.Screen.isCellContinuation(cell)) continue;
        if (cell.codepoint != kitty_placeholder_codepoint) continue;
        if (placeholderImageId(cell) != image_id) continue;
        if (placeholderColorId(cell.attrs.underline_color) != placement_id) continue;

        const row_pos = rowAnchorPosition(row);
        if (best_row.* == null or row_pos < best_row_pos.*) {
            best_row.* = row;
            best_row_pos.* = row_pos;
        }
        if (best_col.* == null or col < best_col.*.?) best_col.* = col;
    }
}

fn placeholderImageId(cell: screen_mod.Screen.Cell) u32 {
    return placeholderColorId(cell.attrs.fg) | (@as(u32, placeholderHighByte(cell) orelse 0) << 24);
}

fn placeholderHighByte(cell: screen_mod.Screen.Cell) ?u8 {
    const value = placeholderIndex(cell, 2) orelse return null;
    return std.math.cast(u8, value);
}

fn placeholderIndex(cell: screen_mod.Screen.Cell, idx: usize) ?u32 {
    if (idx >= cell.combining_len) return null;
    return placeholderDiacriticIndex(@intCast(cell.combining[idx]));
}

fn placeholderDiacriticIndex(cp: u21) ?u32 {
    for (kitty_placeholder_diacritics, 0..) |candidate, idx| {
        if (candidate == cp) return std.math.cast(u32, idx) orelse unreachable;
    }
    return null;
}

fn placeholderColorId(color: screen_mod.Screen.Color) u32 {
    return switch (color.kind) {
        .default => 0,
        .indexed => color.value & 0xFF,
        .rgb => color.value & 0xFFFFFF,
    };
}

fn rowAnchorPosition(row: RowAnchor) i32 {
    return switch (row) {
        .scrollback_above => |rows| -@as(i32, @intCast(rows)),
        .on_screen => |screen_row| @as(i32, screen_row),
        .below_screen => |rows| std.math.add(i32, std.math.maxInt(u16), @as(i32, @intCast(rows))) catch unreachable,
    };
}

fn ensureUploadBound(len: u32) host_state.ApplyError!void {
    if (len > upload_max_bytes) return error.ConsequenceLimit;
}

fn ensureRetainedPayloadStore(self: *const State, next_len: u32, freed_len: u32) host_state.ApplyError!void {
    if (next_len > retained_payload_max_bytes) return error.ConsequenceLimit;
    const retained_len = retainedPayloadBytes(self);
    const kept_len = retained_len -| freed_len;
    const total_len = std.math.add(u32, kept_len, next_len) catch return error.ConsequenceLimit;
    if (total_len > retained_payload_max_bytes) return error.ConsequenceLimit;
}

fn ensureRetainedPayloadTotal(self: *const State) host_state.ApplyError!void {
    if (retainedPayloadBytes(self) > retained_payload_max_bytes) return error.ConsequenceLimit;
}

fn validatePlacement(placement: Placement) void {
    std.debug.assert(placement.source_width > 0);
    std.debug.assert(placement.source_height > 0);
    std.debug.assert(placement.effective_columns > 0);
    std.debug.assert(placement.effective_rows > 0);
}

fn placementFullyWithinRegion(placement: Placement, top: u16, bottom: u16) bool {
    const anchor_row = placement.anchor_row.onScreenRow() orelse return false;
    const last_row = std.math.add(u32, anchor_row, placement.effective_rows - 1) catch return false;
    return anchor_row >= top and last_row <= bottom;
}

fn clipPlacementTop(placement: *Placement, top: u16, cell: CellPixelSize) bool {
    const anchor_row = placement.anchor_row.onScreenRow().?;
    if (anchor_row >= top) return true;

    const dest = placement.resolveDestGeometry(cell) orelse return false;
    const boundary_top_px = std.math.mul(u32, top - anchor_row, cell.height) catch return false;
    if (dest.bottom_px <= boundary_top_px) return false;

    const clip_px = boundary_top_px - dest.top_px;
    const source_clip_px = sourceClipForDestClip(placement.source_height, dest.bottom_px - dest.top_px, clip_px) orelse return false;
    if (placement.source_height <= source_clip_px) return false;

    placement.source_y += source_clip_px;
    placement.source_height -= source_clip_px;
    placement.cell_y_offset = 0;
    placement.effective_rows = ceilDiv(dest.bottom_px - boundary_top_px, cell.height);
    placement.anchor_row = RowAnchor.initOnScreen(top);
    return true;
}

fn clipPlacementBottom(placement: *Placement, bottom: u16, cell: CellPixelSize) bool {
    const anchor_row = placement.anchor_row.onScreenRow().?;
    const dest = placement.resolveDestGeometry(cell) orelse return false;
    const boundary_bottom_px = std.math.mul(u32, bottom - anchor_row + 1, cell.height) catch return false;
    if (dest.top_px >= boundary_bottom_px) return false;
    if (dest.bottom_px <= boundary_bottom_px) return true;

    const clip_px = dest.bottom_px - boundary_bottom_px;
    const source_clip_px = sourceClipForDestClip(placement.source_height, dest.bottom_px - dest.top_px, clip_px) orelse return false;
    if (placement.source_height <= source_clip_px) return false;

    placement.source_height -= source_clip_px;
    placement.effective_rows = ceilDiv(boundary_bottom_px - dest.top_px, cell.height);
    return true;
}

fn sourceClipForDestClip(source_height: u32, dest_height_px: u32, clip_px: u32) ?u32 {
    std.debug.assert(source_height > 0);
    std.debug.assert(dest_height_px > 0);
    if (clip_px == 0) return 0;

    const scaled = std.math.mul(u64, clip_px, source_height) catch return null;
    const clipped: u64 = @intCast(std.math.divCeil(u64, scaled, dest_height_px) catch return null);
    return std.math.cast(u32, clipped);
}

fn rowAnchorRetained(anchor: RowAnchor, history_count: u32, effective_rows: u32, retain_in_scrollback: bool) bool {
    return switch (anchor) {
        .on_screen => true,
        .scrollback_above => |rows| {
            const limit = if (retain_in_scrollback) history_count + effective_rows else effective_rows;
            return rows < limit;
        },
        .below_screen => true,
    };
}

fn rowAnchorVisible(anchor: RowAnchor, effective_rows: u32) bool {
    return switch (anchor) {
        .on_screen => true,
        .scrollback_above => |rows| rows < effective_rows,
        .below_screen => |rows| rows < effective_rows,
    };
}

fn offsetRowAnchor(anchor: RowAnchor, offset_rows: i64, screen_rows: u16) ?RowAnchor {
    const base_row: i64 = switch (anchor) {
        .on_screen => |row| row,
        .scrollback_above => |rows| -@as(i64, rows),
        .below_screen => |rows| std.math.add(i64, screen_rows, rows) catch return null,
    };
    const resolved_row = std.math.add(i64, base_row, offset_rows) catch return null;
    if (resolved_row < 0) {
        const above = std.math.cast(u32, -resolved_row) orelse return null;
        return .{ .scrollback_above = above };
    }
    if (resolved_row < screen_rows) return .{ .on_screen = std.math.cast(u16, resolved_row) orelse return null };
    const below = resolved_row - screen_rows;
    return .{ .below_screen = std.math.cast(u32, below) orelse return null };
}

const GridExtent = struct {
    columns: u32,
    rows: u32,
};

fn resolveGridExtent(source_width: u32, source_height: u32, cell_x_offset: u32, cell_y_offset: u32, columns: u32, rows: u32, cell_pixel_size: ?CellPixelSize) GridExtent {
    const cell = cell_pixel_size orelse return .{
        .columns = @max(columns, 1),
        .rows = @max(rows, 1),
    };
    std.debug.assert(cell.width > 0);
    std.debug.assert(cell.height > 0);

    var effective_columns = columns;
    var effective_rows = rows;
    if (effective_columns == 0) {
        if (effective_rows == 0) {
            const width_px = std.math.add(u32, source_width, cell_x_offset) catch std.math.maxInt(u32);
            effective_columns = ceilDiv(width_px, cell.width);
        } else {
            const height_px = std.math.add(u32, std.math.mul(u32, cell.height, effective_rows) catch std.math.maxInt(u32), cell_y_offset) catch std.math.maxInt(u32);
            const width_px = @as(f64, @floatFromInt(height_px)) * @as(f64, @floatFromInt(source_width)) / @as(f64, @floatFromInt(source_height));
            effective_columns = ceilDivFloat(width_px, cell.width);
        }
    }
    if (effective_rows == 0) {
        if (rows == 0 and columns == 0) {
            const height_px = std.math.add(u32, source_height, cell_y_offset) catch std.math.maxInt(u32);
            effective_rows = ceilDiv(height_px, cell.height);
        } else {
            const width_px = std.math.add(u32, std.math.mul(u32, cell.width, effective_columns) catch std.math.maxInt(u32), cell_x_offset) catch std.math.maxInt(u32);
            const height_px = @as(f64, @floatFromInt(width_px)) * @as(f64, @floatFromInt(source_height)) / @as(f64, @floatFromInt(source_width));
            effective_rows = ceilDivFloat(height_px, cell.height);
        }
    }
    return .{ .columns = @max(effective_columns, 1), .rows = @max(effective_rows, 1) };
}

fn ceilDiv(value: u32, divisor: u32) u32 {
    std.debug.assert(divisor > 0);
    const quotient = value / divisor;
    if (value > quotient * divisor) return quotient + 1;
    return quotient;
}

fn ceilDivFloat(value: f64, divisor: u32) u32 {
    std.debug.assert(divisor > 0);
    const units: u32 = @intFromFloat(@ceil(value / @as(f64, @floatFromInt(divisor))));
    return @max(units, 1);
}

fn resolvedWidthPx(placement: Placement, cell: CellPixelSize) u32 {
    if (placement.columns != 0) return cell.width * placement.effective_columns;
    if (placement.rows != 0) {
        const height_px = cell.height * placement.effective_rows + placement.cell_y_offset;
        return @intFromFloat(@ceil(@as(f64, @floatFromInt(height_px)) *
            @as(f64, @floatFromInt(placement.source_width)) /
            @as(f64, @floatFromInt(placement.source_height))));
    }
    return placement.source_width;
}

fn resolvedHeightPx(placement: Placement, cell: CellPixelSize, width_px: u32) u32 {
    if (placement.rows != 0) return cell.height * placement.effective_rows;
    if (placement.columns != 0) {
        return @intFromFloat(@ceil(@as(f64, @floatFromInt(width_px + placement.cell_x_offset)) *
            @as(f64, @floatFromInt(placement.source_height)) /
            @as(f64, @floatFromInt(placement.source_width))));
    }
    return placement.source_height;
}

fn appendReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, image_id: u32, msg: []const u8) host_state.ApplyError!void {
    const text = formatReply(encode_buf, "\x1b_Gi={d};{s}\x1b\\", .{ image_id, msg });
    try host_state.appendOutput(output, allocator, text);
}

fn appendNumberReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, image_id: u32, image_number: u32, msg: []const u8) host_state.ApplyError!void {
    const text = formatReply(encode_buf, "\x1b_Gi={d},I={d};{s}\x1b\\", .{ image_id, image_number, msg });
    try host_state.appendOutput(output, allocator, text);
}

fn appendPlacementReply(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, image_id: u32, image_number: u32, placement_id: u32, msg: []const u8) host_state.ApplyError!void {
    if (image_id != 0 and image_number != 0 and placement_id != 0) {
        const text = formatReply(encode_buf, "\x1b_Gi={d},I={d},p={d};{s}\x1b\\", .{ image_id, image_number, placement_id, msg });
        try host_state.appendOutput(output, allocator, text);
        return;
    }
    if (image_id != 0 and placement_id != 0) {
        const text = formatReply(encode_buf, "\x1b_Gi={d},p={d};{s}\x1b\\", .{ image_id, placement_id, msg });
        try host_state.appendOutput(output, allocator, text);
        return;
    }
    if (image_number != 0 and placement_id != 0) {
        const text = formatReply(encode_buf, "\x1b_GI={d},p={d};{s}\x1b\\", .{ image_number, placement_id, msg });
        try host_state.appendOutput(output, allocator, text);
        return;
    }
    if (image_number != 0) {
        if (image_id != 0) {
            try appendNumberReply(allocator, output, encode_buf, image_id, image_number, msg);
        } else {
            const text = formatReply(encode_buf, "\x1b_GI={d};{s}\x1b\\", .{ image_number, msg });
            try host_state.appendOutput(output, allocator, text);
        }
        return;
    }
    try appendReply(allocator, output, encode_buf, image_id, msg);
}

fn formatReply(encode_buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    std.debug.assert(encode_buf.len >= reply_max_bytes);
    return std.fmt.bufPrint(encode_buf, fmt, args) catch unreachable;
}
