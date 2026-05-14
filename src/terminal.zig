//! Terminal runtime state and protocol engine.

const std = @import("std");
const control = @import("control.zig");
const grid = @import("grid.zig");
const Input = @import("input.zig");
const interpret = @import("interpret.zig");
const kitty = @import("kitty.zig");
const parser = @import("parser.zig");
const selection = @import("selection.zig");
const snapshot = @import("snapshot.zig");
const keyboard = @import("input/keyboard.zig");
const mouse = @import("input/mouse.zig");

const GridNs = grid.Grid;
const Interpret = interpret;
const Osc = interpret.Osc;
const KittyNs = kitty;
const LocatorNs = control.Locator;
const OscColorNs = control.OscColor;
const Selection = selection;
const Snapshot = snapshot;
const TerminalModeNs = control.Mode;
const TerminalReportNs = control.Report;

/// Host-neutral terminal state and protocol engine.
pub const Terminal = struct {
    pub const ApplySummary = struct {
        applied: usize,
        remaining_events: usize,
        latest_title: ?[]const u8,
    };

    pub const ControlSignal = enum {
        hangup,
        interrupt,
        terminate,
        resize_notify,
    };

    pub const VisibleViewOptions = struct {
        scrollback_offset: usize = 0,
    };

    pub const VisibleRowSource = union(enum) {
        history: u32,
        screen: u16,
    };

    /// Read-only scrollback-aware view of terminal rows visible to a host.
    pub const VisibleView = struct {
        rows: u16,
        cols: u16,
        cursor_row: u16,
        cursor_col: u16,
        cursor_visible: bool,
        cursor_shape: GridNs.CursorShape,
        is_alternate_screen: bool,
        scrollback_offset: u32,
        history_count: u32,
        start: u32,
        screen: *const GridNs,

        pub fn rowSource(self: VisibleView, row: u16) VisibleRowSource {
            if (self.rows == 0 or row >= self.rows) return .{ .screen = 0 };
            const src_row = self.start + rowIndex(row);
            std.debug.assert(self.start + rowIndex(self.rows) <= self.history_count + rowIndex(self.rows));
            std.debug.assert(src_row >= self.start);
            std.debug.assert(src_row < self.history_count + rowIndex(self.rows));
            if (src_row < self.history_count) {
                return .{ .history = self.history_count - 1 - src_row };
            }
            return .{ .screen = @intCast(@min(src_row - self.history_count, rowIndex(self.rows -| 1))) };
        }

        pub fn sourceCellInfoAt(self: VisibleView, source: VisibleRowSource, col: u16) GridNs.Cell {
            return switch (source) {
                .history => |recency| self.screen.historyCellAt(recency, col),
                .screen => |screen_row| self.screen.cellInfoAt(screen_row, col),
            };
        }

        pub fn cellInfoAt(self: VisibleView, row: u16, col: u16) GridNs.Cell {
            return self.sourceCellInfoAt(self.rowSource(row), col);
        }

        pub fn cellAt(self: VisibleView, row: u16, col: u16) u21 {
            return @intCast(self.cellInfoAt(row, col).codepoint);
        }

        pub fn rowDepth(self: VisibleView, row: u16) u32 {
            if (self.rows == 0 or row >= self.rows) return self.scrollback_offset;
            std.debug.assert(self.scrollback_offset <= self.history_count);
            return self.scrollback_offset + rowIndex(self.rows - 1 - row);
        }

        pub fn contentEndExclusive(self: VisibleView, row: u16) u16 {
            if (self.scrollback_offset == 0 and row > self.cursor_row) return 0;
            var scan = self.cols;
            while (scan > 0) {
                const idx = scan - 1;
                const cell = self.cellInfoAt(row, idx);
                if (cell.codepoint != 0 and cell.codepoint != ' ') return scan;
                scan -= 1;
            }
            return if (self.cols > 0) 1 else 0;
        }
    };

    const ClipboardRequest = struct {
        raw: []u8,
    };

    pub const KittyShellMark = KittyNs.ShellMark;
    pub const KittyNotificationRequest = KittyNs.NotificationRequest;
    pub const TerminalColorState = OscColorNs.State;
    const SpecialColorKey = OscColorNs.SpecialKey;
    const KittyGraphicsImage = KittyNs.Graphics.Image;
    const KittyGraphicsPlacement = KittyNs.Graphics.Placement;
    const KittyGraphicsFrame = KittyNs.Graphics.Frame;
    const KittyKeyboardStack = KittyNs.Key.Stack;
    const KittyScreenState = KittyNs.ScreenState;
    const KittyGlobalState = KittyNs.GlobalState;

    const LocatorState = LocatorNs.State;

    const ModeState = struct {
        keyboard_action_mode: bool = false,
        application_cursor_keys: bool = false,
        application_keypad: bool = false,
        send_receive_mode: bool = false,
        newline_mode: bool = false,
        modify_other_keys: i8 = 0,
        key_format: [8]u16 = [_]u16{0} ** 8,
        focus_reporting: bool = false,
        bracketed_paste: bool = false,
        synchronized_output: bool = false,
        kitty_clipboard: bool = false,
        sixel_display_mode: bool = false,
        reverse_wraparound_mode: bool = false,
        extended_reverse_wraparound_mode: bool = false,
        mouse_tracking: Input.MouseTrackingMode = .off,
        mouse_protocol: Input.MouseProtocol = .none,
        pointer_mode: u2 = 1,
        saved_dec_modes: [16]TerminalModeNs.SavedDecMode = [_]TerminalModeNs.SavedDecMode{.{ .mode = 0, .state = 0 }} ** 16,
        saved_dec_mode_count: u8 = 0,
    };

    const HostState = struct {
        const DcsPayloadOwned = struct {
            kind: Interpret.DcsPayloadKind,
            payload: []u8,
        };

        colors: TerminalColorState = .{},
        pending_output: std.ArrayList(u8),
        hyperlink_targets: std.ArrayList([]u8),
        pending_clipboard: ?ClipboardRequest = null,
        locator: LocatorState = .{},
        media_copy_request: ?u16 = null,
        dcs_payload: ?DcsPayloadOwned = null,
        legacy_control: ?Interpret.LegacyControlKind = null,

        fn init() HostState {
            return .{
                .pending_output = std.ArrayList(u8).empty,
                .hyperlink_targets = std.ArrayList([]u8).empty,
            };
        }

        fn deinit(self: *HostState, allocator: std.mem.Allocator) void {
            for (self.hyperlink_targets.items) |uri| allocator.free(uri);
            self.hyperlink_targets.deinit(allocator);
            if (self.pending_clipboard) |req| allocator.free(req.raw);
            if (self.dcs_payload) |payload| allocator.free(payload.payload);
            self.pending_output.deinit(allocator);
        }
    };

    const KittyState = struct {
        main: KittyScreenState = .{},
        alt: KittyScreenState = .{},
        global: KittyGlobalState = .{},

        fn deinit(self: *KittyState, allocator: std.mem.Allocator) void {
            self.global.deinit(allocator);
        }

        pub fn activeScreen(self: *KittyState, alt_active: bool) *KittyScreenState {
            return if (alt_active) &self.alt else &self.main;
        }

        pub fn activeScreenConst(self: *const KittyState, alt_active: bool) *const KittyScreenState {
            return if (alt_active) &self.alt else &self.main;
        }

        pub fn resetTerminalState(self: *KittyState) void {
            self.main.pointer.len = 0;
            self.alt.pointer.len = 0;
            self.global.color_stack_depth = 0;
        }
    };

    const EncodeScratch = struct {
        buf: [64]u8 = undefined,
    };

    const ScreenState = struct {
        const CursorSnapshot = struct {
            row: u16,
            col: u16,
            wrap_pending: bool,
            cursor_visible: bool,
        };

        primary: GridNs,
        alternate: GridNs,
        alt_active: bool = false,
        saved_primary_cursor: ?CursorSnapshot = null,

        fn init(primary: GridNs, alternate: GridNs) ScreenState {
            return .{ .primary = primary, .alternate = alternate };
        }

        pub fn active(self: *ScreenState) *GridNs {
            return if (self.alt_active) &self.alternate else &self.primary;
        }

        pub fn activeConst(self: *const ScreenState) *const GridNs {
            return if (self.alt_active) &self.alternate else &self.primary;
        }

        pub fn reset(self: *ScreenState) void {
            self.active().reset();
        }

        pub fn resize(self: *ScreenState, allocator: std.mem.Allocator, rows: u16, cols: u16) !void {
            try self.primary.resize(allocator, rows, cols);
            try self.alternate.resize(allocator, rows, cols);
        }

        pub fn enterAlt(self: *ScreenState, clear_alt: bool, save_cursor: bool) void {
            if (save_cursor) {
                self.saved_primary_cursor = .{
                    .row = self.primary.cursor_row,
                    .col = self.primary.cursor_col,
                    .wrap_pending = self.primary.wrap_pending,
                    .cursor_visible = self.primary.cursor_visible,
                };
                std.debug.assert(self.saved_primary_cursor != null);
            }
            if (clear_alt) self.alternate.reset();
            self.alt_active = true;
            self.alternate.markAllDirty();
            std.debug.assert(self.alt_active);
        }

        pub fn exitAlt(self: *ScreenState, restore_cursor: bool) void {
            self.alt_active = false;
            if (restore_cursor) {
                if (self.saved_primary_cursor) |saved| {
                    self.primary.cursor_row = @min(saved.row, self.primary.rows -| 1);
                    self.primary.cursor_col = @min(saved.col, self.primary.cols -| 1);
                    self.primary.wrap_pending = saved.wrap_pending;
                    self.primary.cursor_visible = saved.cursor_visible;
                    std.debug.assert(self.primary.cursor_row < self.primary.rows or self.primary.rows == 0);
                    std.debug.assert(self.primary.cursor_col < self.primary.cols or self.primary.cols == 0);
                }
                self.saved_primary_cursor = null;
            }
            self.primary.markAllDirty();
            std.debug.assert(!self.alt_active);
        }

        fn deinit(self: *ScreenState, allocator: std.mem.Allocator) void {
            self.primary.deinit(allocator);
            self.alternate.deinit(allocator);
        }
    };

    allocator: std.mem.Allocator,
    apply_flow: Interpret.ApplyFlow,
    screen_state: ScreenState,
    selection: Selection.SelectionState,
    modes: ModeState = .{},
    kitty: KittyState = .{},
    xtchecksum_flags: u16 = 0,
    host: HostState,
    encode: EncodeScratch = .{},

    /// Initialize Terminal without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        var apply_flow = try Interpret.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        const state = GridNs.init(rows, cols);
        const alt_state = GridNs.init(rows, cols);
        return Terminal{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenState.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !Terminal {
        var apply_flow = try Interpret.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        var state = try GridNs.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenState.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Initialize Terminal with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !Terminal {
        var apply_flow = try Interpret.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        var state = try GridNs.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return Terminal{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenState.init(state, alt_state),
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
        if (max_events == 0) {
            return .{
                .applied = 0,
                .remaining_events = self.apply_flow.events().len,
                .latest_title = null,
            };
        }

        const count = @min(max_events, self.apply_flow.events().len);
        if (count == 0) return .{ .applied = 0, .remaining_events = 0, .latest_title = null };

        std.debug.assert(count <= max_events);
        std.debug.assert(count <= self.apply_flow.events().len);

        var latest_title: ?[]const u8 = null;
        for (self.apply_flow.events()[0..count]) |ev| {
            switch (ev) {
                .osc => |osc_event| {
                    if (osc_event.kind == .title) latest_title = osc_event.payload;
                },
                else => {},
            }
            if (Interpret.process(ev)) |sem_ev| {
                self.applySemantic(sem_ev);
            }
        }
        self.apply_flow.parsed_events.dropPrefix(count);
        const remaining = self.apply_flow.events().len;
        std.debug.assert(remaining + count >= count);
        self.selection.clearIfInvalidatedByGrid(self.activeState());
        return .{ .applied = count, .remaining_events = remaining, .latest_title = latest_title };
    }

    /// Clear queued events without applying.
    pub fn clear(self: *Terminal) void {
        self.apply_flow.clear();
    }

    pub fn pendingOutput(self: *const Terminal) []const u8 {
        return self.host.pending_output.items;
    }

    pub fn clearPendingOutput(self: *Terminal) void {
        self.host.pending_output.clearRetainingCapacity();
    }

    pub fn hyperlinkUriForId(self: *const Terminal, link_id: u32) ?[]const u8 {
        if (link_id == 0) return null;
        const idx = link_id - 1;
        if (idx >= self.host.hyperlink_targets.items.len) return null;
        return self.host.hyperlink_targets.items[idx];
    }

    pub fn pendingClipboardSet(self: *const Terminal) ?[]const u8 {
        if (self.host.pending_clipboard) |req| return req.raw;
        return null;
    }

    pub fn drainPendingClipboardSet(self: *Terminal, allocator: std.mem.Allocator) !?[]u8 {
        const pending = self.pendingClipboardSet() orelse return null;
        defer self.clearPendingClipboardSet();
        return Osc.decodeClipboardSet(allocator, pending) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        };
    }

    pub fn kittyClipboardMode(self: *const Terminal) bool {
        return self.modes.kitty_clipboard;
    }

    pub fn sixelDisplayMode(self: *const Terminal) bool {
        return self.modes.sixel_display_mode;
    }

    pub fn reverseWraparoundMode(self: *const Terminal) bool {
        return self.modes.reverse_wraparound_mode;
    }

    pub fn extendedReverseWraparoundMode(self: *const Terminal) bool {
        return self.modes.extended_reverse_wraparound_mode;
    }

    pub fn mediaCopyRequest(self: *const Terminal) ?u16 {
        return self.host.media_copy_request;
    }

    pub fn dcsPayloadKind(self: *const Terminal) ?Interpret.DcsPayloadKind {
        if (self.host.dcs_payload) |payload| return payload.kind;
        return null;
    }

    pub fn dcsPayload(self: *const Terminal) ?[]const u8 {
        if (self.host.dcs_payload) |payload| return payload.payload;
        return null;
    }

    pub fn legacyControl(self: *const Terminal) ?Interpret.LegacyControlKind {
        return self.host.legacy_control;
    }

    pub fn kittyShellMark(self: *const Terminal) KittyShellMark {
        return self.kitty.global.shell_mark;
    }

    pub fn kittyNotificationCount(self: *const Terminal) usize {
        return self.kitty.global.notifications.items.len;
    }

    pub fn kittyNotificationAt(self: *const Terminal, idx: usize) ?KittyNotificationRequest {
        if (idx >= self.kitty.global.notifications.items.len) return null;
        return self.kitty.global.notifications.items[idx];
    }

    pub fn kittyFileTransferRequest(self: *const Terminal) ?[]const u8 {
        return self.kitty.global.file_transfer_request;
    }

    pub fn kittyTextSizeRequest(self: *const Terminal) ?[]const u8 {
        return self.kitty.global.text_size_request;
    }

    pub fn kittyPointerShape(self: *const Terminal) []const u8 {
        return self.activeKittyScreenConst().pointer.currentName();
    }

    pub fn kittyMultipleCursorCount(self: *const Terminal) u16 {
        return self.activeKittyScreenConst().multiple_cursor_count;
    }

    pub fn pointerMode(self: *const Terminal) u2 {
        return self.modes.pointer_mode;
    }

    pub fn kittyColorStackDepth(self: *const Terminal) u16 {
        return self.kitty.global.color_stack_depth;
    }

    pub fn terminalColorState(self: *const Terminal) TerminalColorState {
        return self.host.colors;
    }

    pub fn kittyGraphicsImageCount(self: *const Terminal) usize {
        return self.kitty.global.graphics.imageCount();
    }

    pub fn kittyGraphicsImageAt(self: *const Terminal, idx: usize) ?KittyGraphicsImage {
        return self.kitty.global.graphics.imageAt(idx);
    }

    pub fn kittyGraphicsPlacementCount(self: *const Terminal) usize {
        return self.kitty.global.graphics.placementCount();
    }

    pub fn kittyGraphicsPlacementAt(self: *const Terminal, idx: usize) ?KittyGraphicsPlacement {
        return self.kitty.global.graphics.placementAt(idx);
    }

    pub fn kittyGraphicsFrameCount(self: *const Terminal) usize {
        return self.kitty.global.graphics.frameCount();
    }

    pub fn kittyGraphicsFrameAt(self: *const Terminal, idx: usize) ?KittyGraphicsFrame {
        return self.kitty.global.graphics.frameAt(idx);
    }

    pub fn clearPendingClipboardSet(self: *Terminal) void {
        if (self.host.pending_clipboard) |req| self.allocator.free(req.raw);
        self.host.pending_clipboard = null;
    }

    /// Reset parser state and clear queue.
    pub fn reset(self: *Terminal) void {
        self.apply_flow.reset();
    }

    /// Reset visible grid state only.
    pub fn resetScreen(self: *Terminal) void {
        self.activeStateMut().reset();
    }

    /// Resize visible screen while preserving history ring contents.
    pub fn resize(self: *Terminal, rows: u16, cols: u16) !void {
        try self.screen_state.resize(self.allocator, rows, cols);
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Return read-only screen state reference.
    pub fn screen(self: *const Terminal) *const GridNs {
        return self.activeState();
    }

    pub fn visibleView(self: *const Terminal, options: VisibleViewOptions) VisibleView {
        const active = self.activeState();
        const history_count: u32 = if (self.screen_state.alt_active) 0 else @intCast(active.historyCount());
        const offset: u32 = @intCast(@min(options.scrollback_offset, @as(usize, history_count)));
        const rows_count = rowIndex(active.rows);
        const total_rows = history_count + rows_count;
        const start = if (total_rows >= rows_count + offset) total_rows - rows_count - offset else 0;
        std.debug.assert(offset <= history_count);
        std.debug.assert(total_rows >= rows_count);
        std.debug.assert(start + rows_count <= total_rows);
        std.debug.assert(total_rows - (start + rows_count) == offset);
        return .{
            .rows = active.rows,
            .cols = active.cols,
            .cursor_row = active.cursor_row,
            .cursor_col = active.cursor_col,
            .cursor_visible = active.cursor_visible,
            .cursor_shape = active.cursor_style.shape,
            .is_alternate_screen = self.screen_state.alt_active,
            .scrollback_offset = offset,
            .history_count = history_count,
            .start = start,
            .screen = active,
        };
    }

    pub fn peekDirtyRows(self: *const Terminal) ?GridNs.DirtyRows {
        return self.activeState().peekDirtyRows();
    }

    pub fn clearDirtyRows(self: *Terminal) void {
        self.activeStateMut().clearDirtyRows();
    }

    pub fn synchronizedOutputActive(self: *const Terminal) bool {
        return self.modes.synchronized_output;
    }

    /// Return history cell by recency index and column.
    pub fn historyRowAt(self: *const Terminal, history_idx: usize, col: u16) u21 {
        if (self.screen_state.alt_active) return 0;
        return self.screen_state.primary.historyRowAt(history_idx, col);
    }

    pub fn historyCellAt(self: *const Terminal, history_idx: usize, col: u16) GridNs.Cell {
        if (self.screen_state.alt_active) return GridNs.default_cell;
        return self.screen_state.primary.historyCellAt(history_idx, col);
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const Terminal) u16 {
        return self.screen_state.primary.historyCapacity();
    }

    /// Return active selection snapshot or null.
    pub fn selectionState(self: *const Terminal) ?Selection.TerminalSelection {
        return self.selection.state();
    }

    /// Start selection at row/column coordinates.
    pub fn selectionStart(self: *Terminal, row: i32, col: u16) void {
        self.selection.start(row, col);
    }

    /// Update selection end coordinates.
    pub fn selectionUpdate(self: *Terminal, row: i32, col: u16) void {
        self.selection.update(row, col);
    }

    /// Finish current active selection.
    pub fn selectionFinish(self: *Terminal) void {
        self.selection.finish();
    }

    /// Clear current selection state.
    pub fn selectionClear(self: *Terminal) void {
        self.selection.clear();
    }

    /// Encode logical key and modifiers.
    pub fn encodeKey(self: *Terminal, key: Input.Key, mod: Input.Modifier) []const u8 {
        if (self.modes.keyboard_action_mode) {
            return self.encode.buf[0..0];
        }
        const encoded = keyboard.encodeKey(self.encode.buf[0..], key, mod, self.modes.application_cursor_keys, self.modes.application_keypad, self.modes.modify_other_keys, self.modes.key_format[4], self.activeKittyKeyboardFlags());
        std.debug.assert(encoded.len <= self.encode.buf.len);
        if (self.modes.newline_mode and key == Input.key_enter and std.mem.eql(u8, encoded, "\r")) {
            self.encode.buf[0] = '\r';
            self.encode.buf[1] = '\n';
            return self.encode.buf[0..2];
        }
        return encoded;
    }

    pub fn kittyKeyboardFlags(self: *const Terminal) u32 {
        return self.activeKittyKeyboardFlags();
    }

    pub fn isApplicationKeypad(self: *const Terminal) bool {
        return self.modes.application_keypad;
    }

    pub fn modifyOtherKeys(self: *const Terminal) i8 {
        return self.modes.modify_other_keys;
    }

    pub fn keyFormatOption(self: *const Terminal, resource: u8) u16 {
        return if (self.isKeyFormatResource(resource)) self.modes.key_format[resource] else 0;
    }

    pub fn isKeyFormatResource(self: *const Terminal, resource: u8) bool {
        _ = self;
        return resource <= 4 or resource == 6 or resource == 7;
    }

    /// Encode a host mouse event for the active terminal mouse modes.
    pub fn encodeMouse(self: *Terminal, event: Input.MouseEvent) []const u8 {
        LocatorNs.handleMouseEvent(&self.host.locator, self.allocator, &self.host.pending_output, self.encode.buf[0..], event);
        const encoded = mouse.encodeMouse(self.encode.buf[0..], event, self.modes.mouse_tracking, self.modes.mouse_protocol);
        std.debug.assert(encoded.len <= self.encode.buf.len);
        return encoded;
    }

    pub fn encodeFocusIn(self: *Terminal) []const u8 {
        const encoded = if (self.modes.focus_reporting) "\x1b[I" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        std.debug.assert(encoded.len <= self.encode.buf.len);
        return self.encode.buf[0..encoded.len];
    }

    pub fn encodePaste(self: *Terminal, allocator: std.mem.Allocator, text: []const u8) !Input.Encoded {
        const start = self.encodePasteStart();
        const end = self.encodePasteEnd();
        if (start.len == 0 and end.len == 0) return .{ .bytes = text };

        const out = try allocator.alloc(u8, start.len + text.len + end.len);
        std.debug.assert(out.len == start.len + text.len + end.len);
        @memcpy(out[0..start.len], start);
        @memcpy(out[start.len .. start.len + text.len], text);
        @memcpy(out[start.len + text.len ..], end);
        return .{ .allocator = allocator, .bytes = out };
    }

    pub fn encodeFocusOut(self: *Terminal) []const u8 {
        const encoded = if (self.modes.focus_reporting) "\x1b[O" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        std.debug.assert(encoded.len <= self.encode.buf.len);
        return self.encode.buf[0..encoded.len];
    }

    pub fn encodePasteStart(self: *Terminal) []const u8 {
        const encoded = if (self.modes.bracketed_paste) "\x1b[200~" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        std.debug.assert(encoded.len <= self.encode.buf.len);
        return self.encode.buf[0..encoded.len];
    }

    pub fn encodePasteEnd(self: *Terminal) []const u8 {
        const encoded = if (self.modes.bracketed_paste) "\x1b[201~" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        std.debug.assert(encoded.len <= self.encode.buf.len);
        return self.encode.buf[0..encoded.len];
    }

    /// Capture visible cells, cursor, modes, history, and selection state.
    /// Parser state, queued events, and encode buffers are not included.
    pub fn snapshot(self: *const Terminal) !Snapshot.VtCoreSnapshot {
        return Snapshot.VtCoreSnapshot.captureFromScreen(
            self.allocator,
            self.activeState(),
            self.selection.state(),
        );
    }

    fn activeState(self: *const Terminal) *const GridNs {
        return self.screen_state.activeConst();
    }

    fn activeStateMut(self: *Terminal) *GridNs {
        return self.screen_state.active();
    }

    fn activeKittyKeyboard(self: *Terminal) *KittyKeyboardStack {
        return &self.activeKittyScreen().keyboard;
    }

    fn activeKittyKeyboardConst(self: *const Terminal) *const KittyKeyboardStack {
        return &self.activeKittyScreenConst().keyboard;
    }

    fn activeKittyKeyboardFlags(self: *const Terminal) u32 {
        return self.activeKittyKeyboardConst().flags;
    }

    fn activeKittyScreen(self: *Terminal) *KittyScreenState {
        return self.kitty.activeScreen(self.screen_state.alt_active);
    }

    fn activeKittyScreenConst(self: *const Terminal) *const KittyScreenState {
        return self.kitty.activeScreenConst(self.screen_state.alt_active);
    }

    fn applySemantic(self: *Terminal, sem_ev: Interpret.SemanticEvent) void {
        if (Interpret.reportAction(sem_ev)) |action| {
            TerminalReportNs.apply(self, action);
            return;
        }
        if (Interpret.kittyAction(sem_ev)) |action| {
            KittyNs.apply(self, action);
            return;
        }
        if (Interpret.modeAction(sem_ev)) |action| {
            TerminalModeNs.apply(self, action);
            return;
        }
        if (Interpret.hostAction(sem_ev)) |action| {
            Interpret.applyHost(self, action);
            return;
        }
        std.debug.assert(Interpret.screenAction(sem_ev) != null);
        if (Interpret.screenAction(sem_ev)) |screen_ev| self.activeStateMut().applyScreen(screen_ev);
    }

    fn rowIndex(row: u16) u32 {
        return row;
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
    _ = @import("test/apply_flow_regression.zig");
    _ = @import("test/terminal_graphics.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/action_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/terminal_end_to_end.zig");
}
