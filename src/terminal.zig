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
const savepoint_mod = @import("terminal/savepoint.zig");

const ScreenNs = screen.Screen;
const TerminalModeNs = mode;
const FeedSummary = stream_terminal.FeedSummary;
const FeedError = stream_terminal.FeedError;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    const HostState = host_state.State;
    const KittyState = kitty_state.KittyState;
    pub const Stream = stream_terminal.Stream;
    pub const InitError = error{ InvalidDimensions, OutOfMemory };
    pub const ResizeError = error{ InvalidDimensions, OutOfMemory };

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
    primary_savepoint: savepoint_mod.Savepoint = .{},
    alternate_savepoint: savepoint_mod.Savepoint = .{},
    dirty_generation: u64 = 1,
    surface_publication: surface_publication.Publication = .{},
    scrollback_offset: u32 = 0,

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

    pub const ScrollViewport = union(enum) {
        top,
        bottom,
        delta: i64,
        absolute: u64,
    };

    fn initWithScreens(allocator: std.mem.Allocator, stream_state: stream_terminal.TerminalStreamState, state: ScreenNs, alt_state: ScreenNs) Terminal {
        return .{
            .allocator = allocator,
            .stream_state = stream_state,
            .screen_state = ScreenSet.init(state, alt_state),
            .host = HostState.init(),
        };
    }

    /// Initialize terminal state without cell storage.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Terminal {
        return initWithOptions(allocator, rows, cols, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, options: InitOptions) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        const state = ScreenNs.initWithDefaultCursorStyle(rows, cols, options.default_cursor_style);
        const alt_state = ScreenNs.initWithDefaultCursorStyle(rows, cols, options.default_cursor_style);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize terminal state with owned cell storage.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Terminal {
        return initWithCellsAndOptions(allocator, rows, cols, .{});
    }

    pub fn initWithCellsAndOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, options: InitOptions) InitError!Terminal {
        try validateDimensions(rows, cols);
        var stream_state = try stream_terminal.TerminalStreamState.initAlloc(allocator);
        errdefer stream_state.deinit();
        var state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer state.deinit(allocator);
        var alt_state = try ScreenNs.initWithCellsAndDefaultCursorStyle(allocator, rows, cols, options.default_cursor_style);
        errdefer alt_state.deinit(allocator);
        return initWithScreens(allocator, stream_state, state, alt_state);
    }

    /// Initialize terminal state with owned cells and bounded history storage.
    ///
    /// Both dimensions must be nonzero. The caller owns the returned terminal
    /// and must call `deinit`.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) InitError!Terminal {
        return initWithCellsHistoryAndOptions(allocator, rows, cols, history_capacity, .{});
    }

    pub fn initWithCellsHistoryAndOptions(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16, options: InitOptions) InitError!Terminal {
        try validateDimensions(rows, cols);
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
        const history_before = self.visibleHistoryCount();
        const was_scrolled = self.scrollback_offset > 0;
        var stream = self.vtStream();
        const summary = try stream.nextSliceSummary(bytes);
        self.postApply(summary.state_changed);
        self.repairScrollbackAfterHistoryChange(history_before, was_scrolled);
        return summary;
    }

    pub fn postApply(self: *Terminal, state_changed: bool) void {
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        if (state_changed) self.dirty_generation +%= 1;
    }

    /// Resize both terminal screens.
    ///
    /// Both dimensions must be nonzero; rejection leaves state unchanged.
    /// Allocation failure may occur after the primary screen is resized, so
    /// paired-screen rollback remains open under VT-012.
    pub fn resize(self: *Terminal, rows: u16, cols: u16) ResizeError!void {
        try validateDimensions(rows, cols);
        try self.screen_state.resize(self.allocator, rows, cols);
        self.screen_state.activeSelection().clearIfInvalidatedByGrid(
            self.screen_state.activeConst(),
        );
        self.clampScrollbackOffset();
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
        self.primary_savepoint.clear();
        self.alternate_savepoint.clear();
        self.gl_index = 0;
        self.g0_designation = 'B';
        self.g1_designation = 'B';
        self.kitty.resetTerminalState(self.allocator);
        self.host.resetTerminalState();
    }

    pub fn saveCursor(self: *Terminal) void {
        const active = self.screen_state.activeConst();
        const savepoint = self.activeSavepoint();
        savepoint.* = .{
            .valid = true,
            .cursor = .{
                .row = active.cursor.row,
                .col = active.cursor.col,
                .style = active.cursor.effectiveStyle(),
            },
            .current_attrs = active.current_attrs,
            .reverse_screen_mode = self.modes.reverse_screen_mode,
            .origin_mode = active.origin_mode,
            .auto_wrap = active.auto_wrap,
            .gl_index = self.gl_index,
            .g0_designation = self.g0_designation,
            .g1_designation = self.g1_designation,
        };
    }

    pub fn restoreCursor(self: *Terminal) void {
        const active = self.screen_state.active();
        const savepoint = self.activeSavepointConst();
        active.wrap_pending = false;
        if (!savepoint.valid) {
            active.cursor.setPositionStructural(0, 0);
            self.modes.reverse_screen_mode = false;
            active.origin_mode = false;
            self.gl_index = 0;
            self.g0_designation = 'B';
            self.g1_designation = 'B';
            return;
        }

        self.modes.reverse_screen_mode = savepoint.reverse_screen_mode;
        active.origin_mode = savepoint.origin_mode;
        active.auto_wrap = savepoint.auto_wrap;
        active.current_attrs = savepoint.current_attrs;
        active.cursor.restoreSavedStyle(savepoint.cursor.style);
        restoreCursorPosition(active, savepoint.cursor.row, savepoint.cursor.col);
        self.gl_index = savepoint.gl_index;
        self.g0_designation = savepoint.g0_designation;
        self.g1_designation = savepoint.g1_designation;
    }

    pub fn switchScreenMode(self: *Terminal, enable_alt: bool, clear_alt: bool, save_restore_cursor: bool) void {
        if (enable_alt) {
            if (self.screen_state.alt_active) return;
            if (save_restore_cursor) self.saveCursor();
            self.screen_state.alt_active = true;
            self.scrollback_offset = 0;
            self.screen_state.activeSelection().clear();
            if (clear_alt) self.screen_state.alternate.clearVisibleCells();
            self.screen_state.alternate.resetCursorForAltEntry();
            self.screen_state.alternate.markAllRowsDirty();
            return;
        }

        if (!self.screen_state.alt_active) return;
        self.screen_state.alt_active = false;
        self.clampScrollbackOffset();
        self.screen_state.activeSelection().clear();
        if (save_restore_cursor) self.restoreCursor();
        self.screen_state.primary.markAllRowsDirty();
    }

    pub fn ackSurface(self: *Terminal, snapshot_seq: u64) bool {
        if (snapshot_seq == 0) return false;
        if (self.surface_publication.canAck(snapshot_seq, self.dirty_generation)) {
            screen_set.clearDirtyRows(&self.screen_state);
        }
        return true;
    }

    pub fn scrollViewport(self: *Terminal, behavior: ScrollViewport) bool {
        const history_count = self.visibleHistoryCount();
        const previous = self.scrollback_offset;
        self.scrollback_offset = switch (behavior) {
            .top => history_count,
            .bottom => 0,
            .delta => |delta| offset: {
                if (delta < 0) {
                    const decrease: u64 = if (delta == std.math.minInt(i64))
                        @as(u64, @intCast(std.math.maxInt(i64))) + 1
                    else
                        @intCast(-delta);
                    break :offset if (decrease >= previous) 0 else previous - @as(u32, @intCast(decrease));
                }
                const increase: u64 = @intCast(delta);
                const target = @as(u64, previous) + increase;
                break :offset @intCast(@min(target, history_count));
            },
            .absolute => |offset| @intCast(@min(offset, history_count)),
        };
        std.debug.assert(self.scrollback_offset <= history_count);
        return self.scrollback_offset != previous;
    }

    pub fn visibleHistoryCount(self: *const Terminal) u32 {
        if (self.screen_state.alt_active) return 0;
        return self.screen_state.activeConst().historyCount();
    }

    fn clampScrollbackOffset(self: *Terminal) void {
        const history_count = self.visibleHistoryCount();
        self.scrollback_offset = @min(self.scrollback_offset, history_count);
        std.debug.assert(self.scrollback_offset <= history_count);
    }

    fn repairScrollbackAfterHistoryChange(self: *Terminal, history_before: u32, was_scrolled: bool) void {
        const history_after = self.visibleHistoryCount();
        if (history_after > history_before) {
            if (was_scrolled) {
                const delta = history_after - history_before;
                const target = @as(u64, self.scrollback_offset) + delta;
                self.scrollback_offset = @intCast(@min(target, history_after));
                std.debug.assert(self.scrollback_offset <= history_after);
            }
            return;
        }
        self.scrollback_offset = @min(self.scrollback_offset, history_after);
        std.debug.assert(self.scrollback_offset <= history_after);
    }

    pub fn surfaceSnapshot(self: *Terminal) SurfacePublication {
        const snapshot = screen_set.surfaceSnapshot(&self.screen_state, self.scrollback_offset);
        return .{
            .snapshot_seq = self.surface_publication.publish(snapshot.view, self.scrollback_offset, self.dirty_generation),
            .dirty_generation = self.dirty_generation,
            .snapshot = snapshot,
        };
    }

    pub fn visibleMeta(self: *Terminal) VisibleMeta {
        const publication = self.surfaceSnapshot();
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

    pub fn visibleCellHyperlinkUri(self: *Terminal, snapshot_seq: u64, row: u16, col: u16) error{InvalidArgument}!?[]const u8 {
        if (snapshot_seq == 0) return error.InvalidArgument;
        const publication = self.surfaceSnapshot();
        if (publication.snapshot_seq != snapshot_seq) return error.InvalidArgument;
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return error.InvalidArgument;
        return host_state.hyperlinkUriForId(self, view.cellInfoAt(row, col).attrs.link_id);
    }

    pub fn visibleCellHyperlinkUriCurrent(self: *Terminal, row: u16, col: u16) ?[]const u8 {
        const publication = self.surfaceSnapshot();
        const view = publication.snapshot.view;
        if (row >= view.rows or col >= view.cols) return null;
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

    fn activeSavepoint(self: *Terminal) *savepoint_mod.Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn activeSavepointConst(self: *const Terminal) *const savepoint_mod.Savepoint {
        return if (self.screen_state.alt_active) &self.alternate_savepoint else &self.primary_savepoint;
    }

    fn restoreCursorPosition(active: *ScreenNs, row: u16, col: u16) void {
        if (active.rows == 0 or active.cols == 0) {
            active.cursor.setPositionStructural(0, 0);
            return;
        }

        const top = if (active.origin_mode) active.scroll_top else 0;
        const bottom = if (active.origin_mode) @min(active.scroll_bottom, active.rows - 1) else active.rows - 1;
        const bounded_row = @max(top, @min(row, bottom));
        const bounded_col = @min(col, active.cols - 1);
        active.cursor.setPositionStructural(bounded_row, bounded_col);
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

fn validateDimensions(rows: u16, cols: u16) error{InvalidDimensions}!void {
    if (rows == 0 or cols == 0) return error.InvalidDimensions;
}

test "terminal scroll viewport owns bottom intent" {
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    _ = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(vt.visibleHistoryCount() > 0);
    try std.testing.expect(vt.scrollViewport(.top));
    try std.testing.expect(vt.scrollback_offset > 0);
    try std.testing.expect(vt.scrollViewport(.bottom));
    try std.testing.expectEqual(@as(u32, 0), vt.scrollback_offset);
    try std.testing.expect(!vt.scrollViewport(.bottom));
}

test "terminal feed preserves scrolled viewport as history grows" {
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 3, 5, 8);
    defer vt.deinit();

    _ = try vt.feed("1AAAA\r\n2BBBB\r\n3CCCC\r\n4DDDD");
    try std.testing.expect(vt.scrollViewport(.{ .absolute = 1 }));
    const before = vt.surfaceSnapshot().snapshot.view.cellAt(0, 0);
    const offset_before = vt.scrollback_offset;

    _ = try vt.feed("\r\n5EEEE");

    try std.testing.expect(vt.scrollback_offset > offset_before);
    try std.testing.expectEqual(before, vt.surfaceSnapshot().snapshot.view.cellAt(0, 0));
}
