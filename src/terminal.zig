const std = @import("std");
const mode = @import("mode.zig");
const screen = @import("screen.zig");
const host_state = @import("host_state.zig");
const kitty_state = @import("kitty/state.zig");
const parser_mod = @import("parser.zig");
const selection = @import("selection.zig");
const screen_set = @import("screen_set.zig");
const stream_terminal = @import("stream_terminal.zig");
const surface_publication = @import("publication.zig");

const ScreenNs = screen.Screen;
const TerminalModeNs = mode;
const FeedSummary = stream_terminal.FeedSummary;
const FeedError = stream_terminal.FeedError;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    const HostState = host_state.State;
    const KittyState = kitty_state.KittyState;
    pub const Stream = stream_terminal.Stream;

    const ScreenSet = screen_set.Set;

    allocator: std.mem.Allocator,
    stream_state: stream_terminal.TerminalStreamState,
    screen_state: ScreenSet,
    modes: TerminalModeNs.ModeState = .{},
    kitty: KittyState = .{},
    xtchecksum_flags: u16 = 0,
    host: HostState,
    gl_index: u8 = 0,
    g0_designation: u8 = 'B',
    g1_designation: u8 = 'B',
    dirty_generation: u64 = 1,
    surface_publication: surface_publication.Publication = .{},

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

    fn initWithScreens(allocator: std.mem.Allocator, stream_state: stream_terminal.TerminalStreamState, state: ScreenNs, alt_state: ScreenNs) Terminal {
        return .{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        return initWithOptions(allocator, rows, cols, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, options: InitOptions) !Terminal {
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        const state = ScreenNs.initWithDefaultCursorStyle(rows, cols, options.default_cursor_style);
        const alt_state = ScreenNs.initWithDefaultCursorStyle(rows, cols, options.default_cursor_style);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize Terminal with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        return initWithCellsAndOptions(allocator, rows, cols, .{});
    }

    pub fn initWithCellsAndOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, options: InitOptions) !Terminal {
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize Terminal with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Terminal {
        return initWithCellsHistoryAndOptions(allocator, rows, cols, history_capacity, .{});
    }

    pub fn initWithCellsHistoryAndOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16, options: InitOptions) !Terminal {
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCellsHistoryAndDefaultCursorStyle(allocator, rows, cols, history_capacity, options.default_cursor_style);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
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
    }

    pub fn resetScreen(self: *Terminal) void {
        self.screen_state.reset();
        self.kitty.resetTerminalState(self.allocator);
        self.host.resetTerminalState();
    }

    pub fn ackSurface(self: *Terminal, snapshot_seq: u64) bool {
        if (snapshot_seq == 0) return false;
        if (self.surface_publication.canAck(snapshot_seq, self.dirty_generation)) {
            screen_set.clearDirtyRows(&self.screen_state);
        }
        return true;
    }

    pub fn surfaceSnapshot(self: *Terminal, scrollback_offset: u64) SurfacePublication {
        const snapshot = screen_set.surfaceSnapshot(&self.screen_state, scrollback_offset);
        return .{
            .snapshot_seq = self.surface_publication.publish(snapshot.view, scrollback_offset, self.dirty_generation),
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

    pub fn runtimeObligation(self: *const Terminal, now_ns: u64) RuntimeObligation {
        _ = self;
        _ = now_ns;
        return .{ .pending_now = false, .deadline_ns = 0 };
    }

    pub fn progressRuntime(self: *Terminal, now_ns: u64) host_state.ApplyError!RuntimeProgress {
        _ = self;
        _ = now_ns;
        return .{
            .state_changed = false,
            .obligation = .{ .pending_now = false, .deadline_ns = 0 },
        };
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
        self.screen_state.activeSelection().start(self.selectionAbsoluteRow(row), col);
        self.noteSelectionChanged();
    }

    pub fn updateSelection(self: *Terminal, row: i32, col: u16) void {
        const before = self.selectionState() orelse return;
        self.screen_state.activeSelection().update(self.selectionAbsoluteRow(row), col);
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

    fn noteSelectionChanged(self: *Terminal) void {
        self.screen_state.active().markAllRowsDirty();
        self.dirty_generation +%= 1;
    }

    fn selectionAbsoluteRow(self: *const Terminal, row: i32) i32 {
        if (row < 0) return row;
        const absolute = @as(u64, self.screen_state.activeConst().historyRowBase()) + @as(u64, @intCast(row));
        return std.math.cast(i32, absolute) orelse std.math.maxInt(i32);
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

    pub fn deccirCharsetState(self: *const Terminal) parser_mod.DeccirCharsetState {
        return .{
            .gl_index = self.gl_index,
            .g0_designation = self.g0_designation,
            .g1_designation = self.g1_designation,
        };
    }
};
