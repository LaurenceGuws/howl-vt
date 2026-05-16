//! Terminal runtime state and protocol engine.

const std = @import("std");
const dispatch = @import("../action/dispatch.zig");
const mode = @import("../control/mode.zig");
const osc_color = @import("../control/osc_color.zig");
const grid = @import("../grid.zig");
const host_state = @import("../host/state.zig");
const kitty_state = @import("../kitty/state.zig");
const screen_set = @import("../screen/set.zig");
const screen_view = @import("../screen/view.zig");
const Input = @import("../input.zig");
const action = @import("../action.zig");
const kitty = @import("../kitty.zig");
const selection = @import("../selection.zig");
const snapshot = @import("../screen/snapshot.zig");
const input_encode = @import("../input/encode.zig");

const GridNs = grid.Grid;
const Action = action;
const KittyNs = kitty;
const Selection = selection;
const Snapshot = snapshot;
const OscColorNs = osc_color;
const TerminalModeNs = mode;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    pub const ApplySummary = dispatch.ApplySummary;

    pub const ControlSignal = enum {
        hangup,
        interrupt,
        terminate,
        resize_notify,
    };

    pub const VisibleViewOptions = screen_view.Options;
    pub const VisibleRowSource = screen_view.RowSource;
    pub const VisibleView = screen_view.View;

    pub const KittyShellMark = KittyNs.ShellMark;
    pub const KittyNotificationRequest = KittyNs.NotificationRequest;
    pub const TerminalColorState = OscColorNs.State;
    const KittyGraphicsImage = KittyNs.Graphics.Image;
    const KittyGraphicsPlacement = KittyNs.Graphics.Placement;
    const KittyGraphicsFrame = KittyNs.Graphics.Frame;
    const HostState = host_state.State;
    const KittyState = kitty_state.State;

    const EncodeScratch = struct {
        buf: [64]u8 = undefined,
    };

    const ScreenSet = screen_set.Set;

    allocator: std.mem.Allocator,
    apply_flow: Action.ApplyFlow,
    screen_state: ScreenSet,
    selection: Selection.SelectionState,
    modes: TerminalModeNs.State = .{},
    kitty: KittyState = .{},
    xtchecksum_flags: u16 = 0,
    host: HostState,
    encode: EncodeScratch = .{},

    /// Initialize Terminal without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        var apply_flow = try Action.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        const state = GridNs.init(rows, cols);
        const alt_state = GridNs.init(rows, cols);
        return Terminal{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenSet.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        var apply_flow = try Action.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        var state = try GridNs.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenSet.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Terminal {
        var apply_flow = try Action.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        var state = try GridNs.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenSet.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Release Terminal resources.
    pub fn deinit(self: *Terminal) void {
        self.host.deinit(self.allocator);
        self.kitty.deinit(self.allocator);
        self.screen_state.deinit(self.allocator);
        self.apply_flow.deinit();
    }

    /// Feed one input byte into parser state.
    pub fn feedByte(self: *Terminal, byte: u8) void {
        self.apply_flow.feedByte(byte);
    }

    /// Feed a byte slice into parser state.
    pub fn feedSlice(self: *Terminal, bytes: []const u8) void {
        self.apply_flow.feedSlice(bytes);
    }

    /// Apply queued events to the screen state.
    pub fn apply(self: *Terminal) void {
        _ = self.applyLimit(std.math.maxInt(usize));
    }

    pub fn applyLimit(self: *Terminal, max_events: usize) ApplySummary {
        return dispatch.applyLimit(self, max_events);
    }

    /// Clear queued events without applying.
    pub fn clear(self: *Terminal) void {
        self.apply_flow.clear();
    }

    pub fn pendingOutput(self: *const Terminal) []const u8 {
        return host_state.pendingOutput(self);
    }

    pub fn clearPendingOutput(self: *Terminal) void {
        host_state.clearPendingOutput(self);
    }

    pub fn hyperlinkUriForId(self: *const Terminal, link_id: u32) ?[]const u8 {
        return host_state.hyperlinkUriForId(self, link_id);
    }

    pub fn pendingClipboardSet(self: *const Terminal) ?[]const u8 {
        return host_state.pendingClipboardSet(self);
    }

    pub fn drainPendingClipboardSet(self: *Terminal, allocator: std.mem.Allocator) !?[]u8 {
        return host_state.drainPendingClipboardSet(self, allocator);
    }

    pub fn kittyClipboardMode(self: *const Terminal) bool {
        return host_state.kittyClipboardMode(self);
    }

    pub fn sixelDisplayMode(self: *const Terminal) bool {
        return host_state.sixelDisplayMode(self);
    }

    pub fn reverseWraparoundMode(self: *const Terminal) bool {
        return host_state.reverseWraparoundMode(self);
    }

    pub fn extendedReverseWraparoundMode(self: *const Terminal) bool {
        return host_state.extendedReverseWraparoundMode(self);
    }

    pub fn mediaCopyRequest(self: *const Terminal) ?u16 {
        return host_state.mediaCopyRequest(self);
    }

    pub fn dcsPayloadKind(self: *const Terminal) ?Action.DcsPayloadKind {
        return host_state.dcsPayloadKind(self);
    }

    pub fn dcsPayload(self: *const Terminal) ?[]const u8 {
        return host_state.dcsPayload(self);
    }

    pub fn legacyControl(self: *const Terminal) ?Action.LegacyControlKind {
        return host_state.legacyControl(self);
    }

    pub fn kittyShellMark(self: *const Terminal) KittyShellMark {
        return kitty_state.shellMark(self);
    }

    pub fn kittyNotificationCount(self: *const Terminal) usize {
        return kitty_state.notificationCount(self);
    }

    pub fn kittyNotificationAt(self: *const Terminal, idx: usize) ?KittyNotificationRequest {
        return kitty_state.notificationAt(self, idx);
    }

    pub fn kittyFileTransferRequest(self: *const Terminal) ?[]const u8 {
        return kitty_state.fileTransferRequest(self);
    }

    pub fn kittyTextSizeRequest(self: *const Terminal) ?[]const u8 {
        return kitty_state.textSizeRequest(self);
    }

    pub fn kittyPointerShape(self: *const Terminal) []const u8 {
        return kitty_state.pointerShape(self);
    }

    pub fn kittyMultipleCursorCount(self: *const Terminal) u16 {
        return kitty_state.multipleCursorCount(self);
    }

    pub fn pointerMode(self: *const Terminal) u2 {
        return host_state.pointerMode(self);
    }

    pub fn kittyColorStackDepth(self: *const Terminal) u16 {
        return kitty_state.colorStackDepth(self);
    }

    pub fn terminalColorState(self: *const Terminal) TerminalColorState {
        return host_state.terminalColorState(self);
    }

    pub fn kittyGraphicsImageCount(self: *const Terminal) usize {
        return kitty_state.graphicsImageCount(self);
    }

    pub fn kittyGraphicsImageAt(self: *const Terminal, idx: usize) ?KittyGraphicsImage {
        return kitty_state.graphicsImageAt(self, idx);
    }

    pub fn kittyGraphicsPlacementCount(self: *const Terminal) usize {
        return kitty_state.graphicsPlacementCount(self);
    }

    pub fn kittyGraphicsPlacementAt(self: *const Terminal, idx: usize) ?KittyGraphicsPlacement {
        return kitty_state.graphicsPlacementAt(self, idx);
    }

    pub fn kittyGraphicsFrameCount(self: *const Terminal) usize {
        return kitty_state.graphicsFrameCount(self);
    }

    pub fn kittyGraphicsFrameAt(self: *const Terminal, idx: usize) ?KittyGraphicsFrame {
        return kitty_state.graphicsFrameAt(self, idx);
    }

    pub fn clearPendingClipboardSet(self: *Terminal) void {
        host_state.clearPendingClipboardSet(self);
    }

    /// Reset parser state and clear queue.
    pub fn reset(self: *Terminal) void {
        self.apply_flow.reset();
    }

    /// Reset visible grid state only.
    pub fn resetScreen(self: *Terminal) void {
        self.screen_state.active().reset();
    }

    /// Resize visible screen while preserving history ring contents.
    pub fn resize(self: *Terminal, rows: u16, cols: u16) !void {
        try self.screen_state.resize(self.allocator, rows, cols);
        self.selection.clearIfInvalidatedByGrid(self.screen_state.activeConst());
    }

    /// Return read-only screen state reference.
    pub fn screen(self: *const Terminal) *const GridNs {
        return self.screen_state.activeConst();
    }

    pub fn visibleView(self: *const Terminal, options: VisibleViewOptions) VisibleView {
        return screen_view.visibleView(&self.screen_state, options);
    }

    pub fn peekDirtyRows(self: *const Terminal) ?GridNs.DirtyRows {
        return screen_view.peekDirtyRows(&self.screen_state);
    }

    pub fn clearDirtyRows(self: *Terminal) void {
        screen_view.clearDirtyRows(&self.screen_state);
    }

    pub fn synchronizedOutputActive(self: *const Terminal) bool {
        return self.modes.synchronized_output;
    }

    /// Return history cell by recency index and column.
    pub fn historyRowAt(self: *const Terminal, history_idx: usize, col: u16) u21 {
        return screen_view.historyRowAt(&self.screen_state, history_idx, col);
    }

    pub fn historyCellAt(self: *const Terminal, history_idx: usize, col: u16) GridNs.Cell {
        return screen_view.historyCellAt(&self.screen_state, history_idx, col);
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const Terminal) u16 {
        return screen_view.historyCapacity(&self.screen_state);
    }

    /// Return active selection snapshot or null.
    pub fn selectionState(self: *const Terminal) ?Selection.TerminalSelection {
        return Selection.terminalState(self);
    }

    /// Start selection at row/column coordinates.
    pub fn selectionStart(self: *Terminal, row: i32, col: u16) void {
        Selection.terminalStart(self, row, col);
    }

    /// Update selection end coordinates.
    pub fn selectionUpdate(self: *Terminal, row: i32, col: u16) void {
        Selection.terminalUpdate(self, row, col);
    }

    /// Finish current active selection.
    pub fn selectionFinish(self: *Terminal) void {
        Selection.terminalFinish(self);
    }

    /// Clear current selection state.
    pub fn selectionClear(self: *Terminal) void {
        Selection.terminalClear(self);
    }

    /// Encode logical key and modifiers.
    pub fn encodeKey(self: *Terminal, key: Input.Key, mod: Input.Modifier) []const u8 {
        return input_encode.key(self, key, mod);
    }

    pub fn kittyKeyboardFlags(self: *const Terminal) u32 {
        return input_encode.kittyKeyboardFlags(self);
    }

    pub fn isApplicationKeypad(self: *const Terminal) bool {
        return input_encode.isApplicationKeypad(self);
    }

    pub fn modifyOtherKeys(self: *const Terminal) i8 {
        return input_encode.modifyOtherKeys(self);
    }

    pub fn keyFormatOption(self: *const Terminal, resource: u8) u16 {
        return input_encode.keyFormatOption(self, resource);
    }

    pub fn isKeyFormatResource(self: *const Terminal, resource: u8) bool {
        _ = self;
        return resource <= 4 or resource == 6 or resource == 7;
    }

    /// Encode a host mouse event for the active terminal mouse modes.
    pub fn encodeMouse(self: *Terminal, event: Input.MouseEvent) []const u8 {
        return input_encode.mouseEvent(self, event);
    }

    pub fn encodeFocusIn(self: *Terminal) []const u8 {
        return input_encode.focusIn(self);
    }

    pub fn encodePaste(self: *Terminal, allocator: std.mem.Allocator, text: []const u8) !Input.Encoded {
        return input_encode.paste(self, allocator, text);
    }

    pub fn encodeFocusOut(self: *Terminal) []const u8 {
        return input_encode.focusOut(self);
    }

    pub fn encodePasteStart(self: *Terminal) []const u8 {
        return input_encode.pasteStart(self);
    }

    pub fn encodePasteEnd(self: *Terminal) []const u8 {
        return input_encode.pasteEnd(self);
    }

    /// Capture visible cells, cursor, modes, history, and selection state.
    /// Parser state, queued events, and encode buffers are not included.
    pub fn snapshot(self: *const Terminal) !Snapshot.VtCoreSnapshot {
        return Snapshot.capture(self);
    }

};

test "terminal tracks synchronized output private mode" {
    var vt = try Terminal.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    vt.feedSlice("\x1b[?2026h");
    vt.apply();
    try std.testing.expect(vt.synchronizedOutputActive());

    vt.feedSlice("\x1b[?2026l");
    vt.apply();
    try std.testing.expect(!vt.synchronizedOutputActive());
}

test "terminal visible view projects scrollback rows" {
    var vt = try Terminal.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer vt.deinit();

    vt.feedSlice("aa\r\nbb\r\ncc");
    vt.apply();

    const live = vt.visibleView(.{});
    try std.testing.expectEqual(0, live.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'b'), live.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'c'), live.cellAt(1, 0));

    const scrolled = vt.visibleView(.{ .scrollback_offset = 1 });
    try std.testing.expectEqual(1, scrolled.scrollback_offset);
    try std.testing.expectEqual(@as(u21, 'a'), scrolled.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), scrolled.cellAt(1, 0));
    try std.testing.expectEqual(2, scrolled.rowDepth(0));
    try std.testing.expectEqual(1, scrolled.rowDepth(1));
}

test {
    _ = @import("../test/apply_flow_regression.zig");
    _ = @import("../test/terminal_graphics.zig");
    _ = @import("../test/terminal_modes_reports.zig");
    _ = @import("../test/terminal_osc_colors.zig");
    _ = @import("../test/terminal_surface.zig");
    _ = @import("../test/screen_state_behavior.zig");
    _ = @import("../test/action_mapping.zig");
    _ = @import("../test/snapshot_regression.zig");
    _ = @import("../test/terminal_end_to_end.zig");
}
