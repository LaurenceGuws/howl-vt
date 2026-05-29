const std = @import("std");
const mode = @import("control/mode.zig");
const screen = @import("screen.zig");
const host_state = @import("host/state.zig");
const kitty_state = @import("kitty/state.zig");
const kitty_types = @import("kitty/types.zig");
const parser_mod = @import("parser.zig");
const selection = @import("selection.zig");
const screen_set = @import("screen_set.zig");
const stream_terminal = @import("stream_terminal.zig");

const ScreenNs = screen.Screen;
const TerminalModeNs = mode;
const FeedSummary = stream_terminal.FeedSummary;
const FeedError = stream_terminal.FeedError;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    const HostState = host_state.State;
    const KittyState = kitty_state.State;
    const GraphicsState = kitty_types.Graphics.State;
    pub const Stream = stream_terminal.Stream;

    const ScreenSet = screen_set.Set;

    allocator: std.mem.Allocator,
    stream_state: stream_terminal.State,
    screen_state: ScreenSet,
    modes: TerminalModeNs.State = .{},
    kitty: KittyState = .{},
    xtchecksum_flags: u16 = 0,
    host: HostState,
    gl_index: u8 = 0,
    g0_designation: u8 = 'B',
    g1_designation: u8 = 'B',
    dirty_generation: u64 = 1,
    surface_snapshot_seq: u64 = 1,
    surface_snapshot_dirty_generation: u64 = 0,
    surface_snapshot_scrollback_offset: u64 = 0,
    surface_snapshot_start: u64 = 0,
    surface_snapshot_rows: u16 = 0,
    surface_snapshot_cols: u16 = 0,
    surface_snapshot_alt: bool = false,
    graphics_publication_seq: u64 = 1,
    graphics_publication_dirty_generation: u64 = 0,
    graphics_publication_alt: bool = false,

    pub const RuntimeObligation = struct {
        pending_now: bool,
        deadline_ns: u64,
    };

    pub const RuntimeProgress = struct {
        state_changed: bool,
        obligation: RuntimeObligation,
    };

    pub const InitOptions = struct {
        default_cursor_style: ScreenNs.CursorStyle = ScreenNs.default_cursor_style,
    };

    /// Initialize Terminal without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        return initWithOptions(allocator, rows, cols, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, options: InitOptions) !Terminal {
        var stream_state = try stream_terminal.State.initAlloc(allocator);
        errdefer stream_state.deinit();
        const state = ScreenNs.initWithDefaultCursorStyle(rows, cols, options.default_cursor_style);
        const alt_state = ScreenNs.initWithDefaultCursorStyle(rows, cols, options.default_cursor_style);
        return Terminal{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        return initWithCellsAndOptions(allocator, rows, cols, .{});
    }

    pub fn initWithCellsAndOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, options: InitOptions) !Terminal {
        var stream_state = try stream_terminal.State.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Terminal {
        return initWithCellsHistoryAndOptions(allocator, rows, cols, history_capacity, .{});
    }

    pub fn initWithCellsHistoryAndOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16, options: InitOptions) !Terminal {
        var stream_state = try stream_terminal.State.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCellsHistoryAndDefaultCursorStyle(allocator, rows, cols, history_capacity, options.default_cursor_style);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Release Terminal resources.
    pub fn deinit(self: *Terminal) void {
        const allocator = self.allocator;
        self.host.deinit(allocator);
        self.kitty.deinit(allocator);
        self.screen_state.deinit(allocator);
        self.stream_state.deinit();
    }

    pub fn vtStream(self: *Terminal) Stream {
        return .init(self);
    }

    pub fn feed(self: *Terminal, bytes: []const u8) FeedError!FeedSummary {
        var stream = self.vtStream();
        const summary = try stream.nextSliceSummary(bytes);
        self.postApply(summary.state_changed);
        return summary;
    }

    pub fn postApply(self: *Terminal, state_changed: bool) void {
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        if (state_changed) self.dirty_generation +%= 1;
    }

    pub fn resize(self: *Terminal, rows: u16, cols: u16) !void {
        try self.screen_state.resize(self.allocator, rows, cols);
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        self.dirty_generation +%= 1;
    }

    pub fn setCellPixelSize(self: *Terminal, width: u32, height: u32) void {
        const previous = self.screen_state.primary.cellPixelSize();
        if (previous) |cell| {
            if (cell.width == width and cell.height == height) return;
        }

        self.screen_state.setCellPixelSize(width, height);
        self.kitty.main.graphics.rescaleImplicitPlacements(.{ .width = width, .height = height });
        self.kitty.alt.graphics.rescaleImplicitPlacements(.{ .width = width, .height = height });

        if ((self.kitty.activeGraphicsConst(self.screen_state.alt_active).resolvedPlacementCount(self.allocator, self.screen_state.activeConst(), self.screen_state.activeConst().cellPixelSize()) catch 1) == 0) {
            return;
        }

        self.screen_state.active().markAllRowsDirty();
        self.dirty_generation +%= 1;
    }

    pub fn resetScreen(self: *Terminal) void {
        self.screen_state.reset();
        self.kitty.resetTerminalState(self.allocator);
        self.host.resetTerminalState();
    }

    pub fn ackSurface(self: *Terminal, snapshot_seq: u64) bool {
        if (snapshot_seq == 0) return false;
        if (self.surface_snapshot_seq == snapshot_seq and self.surface_snapshot_dirty_generation == self.dirty_generation) {
            screen_set.clearDirtyRows(&self.screen_state);
        }
        return true;
    }

    pub fn surfaceSnapshot(self: *Terminal, scrollback_offset: u64) SurfacePublication {
        const snapshot = screen_set.surfaceSnapshot(&self.screen_state, scrollback_offset);
        return .{
            .snapshot_seq = self.noteSurfacePublication(snapshot.view, scrollback_offset),
            .dirty_generation = self.dirty_generation,
            .snapshot = snapshot,
        };
    }

    pub fn visibleMeta(self: *Terminal, scrollback_offset: u64) VisibleMeta {
        const publication = self.surfaceSnapshot(scrollback_offset);
        const view = publication.snapshot.view;
        return .{
            .rows = view.rows,
            .cols = view.cols,
            .history_count = view.history_count,
            .is_alternate_screen = view.is_alternate_screen,
            .snapshot_seq = publication.snapshot_seq,
            .dirty_generation = publication.dirty_generation,
        };
    }

    pub fn graphicsPublication(self: *Terminal) GraphicsPublication {
        return .{
            .publication_seq = self.noteGraphicsPublication(),
            .dirty_generation = self.dirty_generation,
            .is_alternate_screen = self.screen_state.alt_active,
            .state = self.kitty.activeGraphicsConst(self.screen_state.alt_active),
        };
    }

    pub fn graphicsMeta(self: *Terminal) host_state.ApplyError!GraphicsMeta {
        const publication = self.graphicsPublication();
        try self.kitty.activeGraphics(self.screen_state.alt_active).markResolvedPlaceholderRunImageAccess(self.allocator, self.screen_state.activeConst());
        const meta = GraphicsMeta{
            .image_count = publication.state.imageCount(),
            .placement_count = try publication.state.resolvedPlacementCount(self.allocator, self.screen_state.activeConst(), self.screen_state.activeConst().cellPixelSize()),
            .virtual_placement_count = publication.state.virtualPlacementCount(),
            .placeholder_run_count = try publication.state.resolvedPlaceholderRunCount(self.allocator, self.screen_state.activeConst()),
            .is_alternate_screen = publication.is_alternate_screen,
            .publication_seq = publication.publication_seq,
            .dirty_generation = publication.dirty_generation,
        };
        return meta;
    }

    pub fn runtimeObligation(self: *const Terminal, now_ns: u64) RuntimeObligation {
        const obligation = self.kitty.activeGraphicsConst(self.screen_state.alt_active).runtimeObligation(now_ns);
        return .{ .pending_now = obligation.pending_now, .deadline_ns = obligation.deadline_ns };
    }

    pub fn progressRuntime(self: *Terminal, now_ns: u64) host_state.ApplyError!RuntimeProgress {
        const changed = try self.kitty.activeGraphics(self.screen_state.alt_active).progressRuntime(self.allocator, now_ns);
        if (changed) self.dirty_generation +%= 1;
        return .{
            .state_changed = changed,
            .obligation = self.runtimeObligation(now_ns),
        };
    }

    pub fn noteDrawnGraphics(self: *Terminal, publication_seq: u64, image_ref_ids: []const u32) (error{InvalidArgument} || host_state.ApplyError)!void {
        _ = try self.graphicsStateForPublication(publication_seq);
        return self.kitty.activeGraphics(self.screen_state.alt_active).noteDrawnImageRefs(image_ref_ids);
    }

    pub fn graphicsImage(self: *Terminal, publication_seq: u64, idx: kitty_types.Graphics.Index) error{InvalidArgument}!?kitty_types.Graphics.Image {
        const state = try self.graphicsStateForPublication(publication_seq);
        return state.imageAt(idx);
    }

    pub fn graphicsDecodedImage(self: *Terminal, publication_seq: u64, idx: kitty_types.Graphics.Index) error{InvalidArgument}!?kitty_types.Graphics.DecodedImage {
        const state = try self.graphicsStateForPublication(publication_seq);
        return state.decodedImageAt(idx);
    }

    pub fn graphicsPlacement(self: *Terminal, publication_seq: u64, idx: kitty_types.Graphics.Index) (error{InvalidArgument} || host_state.ApplyError)!?kitty_types.Graphics.Placement {
        const state = try self.graphicsStateForPublication(publication_seq);
        return try state.resolvedPlacementAt(self.allocator, idx, self.screen_state.activeConst(), self.screen_state.activeConst().cellPixelSize());
    }

    pub fn graphicsVirtualPlacement(self: *Terminal, publication_seq: u64, idx: kitty_types.Graphics.Index) error{InvalidArgument}!?kitty_types.Graphics.VirtualPlacement {
        const state = try self.graphicsStateForPublication(publication_seq);
        return state.virtualPlacementAt(idx);
    }

    pub fn graphicsPlaceholderRun(
        self: *Terminal,
        publication_seq: u64,
        idx: kitty_types.Graphics.Index,
    ) (error{InvalidArgument} || host_state.ApplyError)!?kitty_types.Graphics.ResolvedPlaceholderRun {
        const state = try self.graphicsStateForPublication(publication_seq);
        return state.resolvedPlaceholderRunAt(self.allocator, idx, self.screen_state.activeConst());
    }

    pub fn graphicsPlaceholderRunProofCount(self: *Terminal, publication_seq: u64) (error{InvalidArgument} || host_state.ApplyError)!u32 {
        const state = try self.graphicsStateForPublication(publication_seq);
        return try state.resolvedPlaceholderRunCount(self.allocator, self.screen_state.activeConst());
    }

    pub fn graphicsPlaceholderRunProof(
        self: *Terminal,
        publication_seq: u64,
        idx: kitty_types.Graphics.Index,
    ) (error{InvalidArgument} || host_state.ApplyError)!?kitty_types.Graphics.ResolvedPlaceholderRun {
        return self.graphicsPlaceholderRun(publication_seq, idx);
    }

    pub fn visibleCellHyperlinkUri(self: *Terminal, scrollback_offset: u64, snapshot_seq: u64, row: u16, col: u16) error{InvalidArgument}!?[]const u8 {
        if (snapshot_seq == 0) return error.InvalidArgument;
        const publication = self.surfaceSnapshot(scrollback_offset);
        if (publication.snapshot_seq != snapshot_seq) return error.InvalidArgument;
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return error.InvalidArgument;
        return host_state.hyperlinkUriForId(self, view.cellInfoAt(row, col).attrs.link_id);
    }

    pub fn selectionState(self: *const Terminal) ?selection.TerminalSelection {
        return self.screen_state.activeSelectionConst().state();
    }

    pub fn startSelection(self: *Terminal, row: i32, col: u16) void {
        self.screen_state.activeSelection().start(row, col);
        self.noteSelectionChanged();
    }

    pub fn updateSelection(self: *Terminal, row: i32, col: u16) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().update(row, col);
        const after = self.selectionState() orelse return;
        if (before.end.row == after.end.row and before.end.col == after.end.col) return;
        self.noteSelectionChanged();
    }

    pub fn finishSelection(self: *Terminal) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().finish();
        const after = self.selectionState() orelse return;
        if (before.selecting == after.selecting) return;
        self.noteSelectionChanged();
    }

    pub fn clearSelection(self: *Terminal) void {
        if (self.selectionState() == null) return;
        self.screen_state.activeSelection().clear();
        self.noteSelectionChanged();
    }

    fn noteSurfacePublication(self: *Terminal, view: screen_set.View, scrollback_offset: u64) u64 {
        const same_dirty = self.surface_snapshot_dirty_generation == self.dirty_generation;
        const same_offset = self.surface_snapshot_scrollback_offset == scrollback_offset;
        const same_start = self.surface_snapshot_start == view.start;
        const same_rows = self.surface_snapshot_rows == view.rows;
        const same_cols = self.surface_snapshot_cols == view.cols;
        const same_alt = self.surface_snapshot_alt == view.is_alternate_screen;
        if (!(same_dirty and same_offset and same_start and same_rows and same_cols and same_alt)) {
            if (self.surface_snapshot_dirty_generation != 0) self.surface_snapshot_seq +%= 1;
            self.surface_snapshot_dirty_generation = self.dirty_generation;
            self.surface_snapshot_scrollback_offset = scrollback_offset;
            self.surface_snapshot_start = view.start;
            self.surface_snapshot_rows = view.rows;
            self.surface_snapshot_cols = view.cols;
            self.surface_snapshot_alt = view.is_alternate_screen;
        }
        return self.surface_snapshot_seq;
    }

    fn noteSelectionChanged(self: *Terminal) void {
        self.screen_state.active().markAllRowsDirty();
        self.dirty_generation +%= 1;
    }

    fn graphicsStateForPublication(self: *Terminal, publication_seq: u64) error{InvalidArgument}!*const GraphicsState {
        if (publication_seq == 0) return error.InvalidArgument;
        const publication = self.graphicsPublication();
        if (publication.publication_seq != publication_seq) return error.InvalidArgument;
        return publication.state;
    }

    fn noteGraphicsPublication(self: *Terminal) u64 {
        const same_dirty = self.graphics_publication_dirty_generation == self.dirty_generation;
        const same_alt = self.graphics_publication_alt == self.screen_state.alt_active;
        if (!(same_dirty and same_alt)) {
            if (self.graphics_publication_dirty_generation != 0) self.graphics_publication_seq +%= 1;
            self.graphics_publication_dirty_generation = self.dirty_generation;
            self.graphics_publication_alt = self.screen_state.alt_active;
        }
        return self.graphics_publication_seq;
    }

    pub const SurfacePublication = struct {
        snapshot_seq: u64,
        dirty_generation: u64,
        snapshot: screen_set.SurfaceSnapshot,
    };

    pub const VisibleMeta = struct {
        rows: u16,
        cols: u16,
        history_count: u32,
        is_alternate_screen: bool,
        snapshot_seq: u64,
        dirty_generation: u64,
    };

    pub const GraphicsPublication = struct {
        publication_seq: u64,
        dirty_generation: u64,
        is_alternate_screen: bool,
        state: *const GraphicsState,
    };

    pub const GraphicsMeta = struct {
        image_count: u32,
        placement_count: u32,
        virtual_placement_count: u32,
        placeholder_run_count: u32,
        is_alternate_screen: bool,
        publication_seq: u64,
        dirty_generation: u64,
    };

    pub fn deccirCharsetState(self: *const Terminal) parser_mod.DeccirCharsetState {
        return .{
            .gl_index = self.gl_index,
            .g0_designation = self.g0_designation,
            .g1_designation = self.g1_designation,
        };
    }
};

test "terminal tracks synchronized output private mode" {
    const stream_harness = @import("test/stream_harness.zig");
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);
    defer stream.deinit();

    try stream.nextSlice("\x1b[?2026h");
    try std.testing.expect(vt.modes.synchronized_output);

    try stream.nextSlice("\x1b[?2026l");
    try std.testing.expect(!vt.modes.synchronized_output);
}

test "terminal visible view projects scrollback rows" {
    const stream_harness = @import("test/stream_harness.zig");
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);
    defer stream.deinit();

    try stream.nextSlice("aa\r\nbb\r\ncc");

    const live = screen_set.visibleView(&vt.screen_state, .{});
    try std.testing.expectEqual(0, live.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'b'), live.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), live.cellAt(1, 0));

    const scrolled = screen_set.visibleView(&vt.screen_state, .{ .scrollback_offset = 1 });
    try std.testing.expectEqual(1, scrolled.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'a'), scrolled.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), scrolled.cellAt(1, 0));
    try std.testing.expectEqual(2, scrolled.rowDepth(0));
    try std.testing.expectEqual(1, scrolled.rowDepth(1));
}

test "terminal reset screen delegates owner resets" {
    const stream_harness = @import("test/stream_harness.zig");
    var vt = try Terminal.initWithCells(std.testing.allocator, 2, 8);
    defer vt.deinit();
    var stream = try stream_harness.Harness.init(&vt);
    defer stream.deinit();

    vt.screen_state.active().writeText("ab");
    vt.kitty.main.pointer.set("pointer");
    vt.host.locator.mode = .continuous;
    vt.host.locator.coordinate_unit = 1;

    try stream.nextSlice("\x1bc");

    try std.testing.expectEqual(@as(u21, 0), vt.screen_state.activeConst().cellAt(0, 0));
    try std.testing.expectEqualStrings("0", vt.kitty.main.pointer.currentName());
    try std.testing.expect(vt.host.locator.mode == .disabled);
    try std.testing.expectEqual(@as(u16, 0), vt.host.locator.coordinate_unit);
}

test "graphics publication stays stable across surface queries" {
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();

    _ = try vt.feed("aa\r\nbb\r\ncc");
    _ = try vt.feed("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");

    const first = vt.graphicsPublication();
    _ = vt.surfaceSnapshot(0);
    _ = vt.surfaceSnapshot(1);
    const second = vt.graphicsPublication();

    try std.testing.expectEqual(first.publication_seq, second.publication_seq);
    try std.testing.expectEqual(first.dirty_generation, second.dirty_generation);
    try std.testing.expectEqual(first.is_alternate_screen, second.is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 1), second.state.imageCount());
}

test "graphics publication advances on graphics mutation and alt switch" {
    var vt = try Terminal.initWithCells(std.testing.allocator, 3, 16);
    defer vt.deinit();

    const initial = vt.graphicsPublication();
    try std.testing.expectEqual(@as(u32, 0), initial.state.imageCount());

    _ = try vt.feed("\x1b_Gi=7,s=1,v=1,t=d,f=24;AAAA\x1b\\");
    const after_upload = vt.graphicsPublication();
    try std.testing.expect(after_upload.publication_seq != initial.publication_seq);
    try std.testing.expectEqual(@as(u32, 1), after_upload.state.imageCount());
    try std.testing.expect(!after_upload.is_alternate_screen);

    _ = try vt.feed("\x1b[?1049h");
    const after_alt = vt.graphicsPublication();
    try std.testing.expect(after_alt.publication_seq != after_upload.publication_seq);
    try std.testing.expect(after_alt.is_alternate_screen);
    try std.testing.expectEqual(@as(u32, 0), after_alt.state.imageCount());
}

test {
    _ = @import("test/pty_feed_record.zig");
    _ = @import("test/terminal_graphics.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/action_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/terminal_end_to_end.zig");
}
