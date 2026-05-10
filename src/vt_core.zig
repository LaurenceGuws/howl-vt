//! Responsibility: provide the vt-core package entry owner.
//! Ownership: primary embeddable terminal boundary.
//! Reason: expose one host-neutral terminal object while keeping domain internals behind sibling owners.

const std = @import("std");
const grid = @import("grid/grid.zig");
const grid_model = @import("grid/state.zig");
const input = @import("input/input.zig");
const interpret = @import("interpret/interpret.zig");
const osc_actions = @import("interpret/osc_actions.zig");
const kitty = @import("kitty/kitty.zig");
const locator = @import("locator.zig");
const osc_color = @import("osc_color.zig");
const parser = @import("parser.zig");
const selection = @import("selection/selection.zig");
const snapshot = @import("snapshot/snapshot.zig");
const mode = @import("mode.zig");
const report = @import("report.zig");

const GridNs = grid;
const Input = input;
const Interpret = interpret;
const OscActions = osc_actions;
const KittyNs = kitty;
const LocatorNs = locator;
const OscColorNs = osc_color;
const ParserNs = parser;
const Selection = selection;
const Snapshot = snapshot;
const TerminalModeNs = mode;
const TerminalReportNs = report;

/// Explicit package-surface grid owner alias retained for downstream runtime/render code.
pub const Grid = GridNs;
/// Explicit package-surface parser owner alias retained for fuzz/protocol tools.
pub const Parser = ParserNs;

/// Host-neutral terminal facade.
pub const VtCore = struct {
    /// Explicit grid compatibility surface retained for render/runtime owners.
    pub const Grid = GridNs;
    pub const DirtyRows = grid_model.DirtyRows;
    /// Host control signals routed to transport/runtime owner.
    pub const ControlSignal = enum {
        hangup,
        interrupt,
        terminate,
        resize_notify,
    };

    /// Key type alias exported by vt-core facade.
    pub const Key = Input.Key;
    /// Modifier type alias exported by vt-core facade.
    pub const Modifier = Input.Modifier;
    /// Mouse button type alias exported by vt-core facade.
    pub const MouseButton = Input.MouseButton;
    /// Mouse event kind alias exported by vt-core facade.
    pub const MouseEventKind = Input.MouseEventKind;

    /// No modifiers set.
    pub const mod_none: Modifier = Input.mod_none;
    /// Shift modifier bit.
    pub const mod_shift: Modifier = Input.mod_shift;
    /// Alt modifier bit.
    pub const mod_alt: Modifier = Input.mod_alt;
    /// Control modifier bit.
    pub const mod_ctrl: Modifier = Input.mod_ctrl;

    /// Enter key alias.
    pub const key_enter: Key = Input.key_enter;
    /// Tab key alias.
    pub const key_tab: Key = Input.key_tab;
    /// Backspace key alias.
    pub const key_backspace: Key = Input.key_backspace;
    /// Escape key alias.
    pub const key_escape: Key = Input.key_escape;
    /// Arrow up key alias.
    pub const key_up: Key = Input.key_up;
    /// Arrow down key alias.
    pub const key_down: Key = Input.key_down;
    /// Arrow left key alias.
    pub const key_left: Key = Input.key_left;
    /// Arrow right key alias.
    pub const key_right: Key = Input.key_right;
    /// Insert key alias.
    pub const key_insert: Key = Input.key_insert;
    /// Delete key alias.
    pub const key_delete: Key = Input.key_delete;
    /// Home key alias.
    pub const key_home: Key = Input.key_home;
    /// End key alias.
    pub const key_end: Key = Input.key_end;
    /// Page-up key alias.
    pub const key_pageup: Key = Input.key_pageup;
    /// Page-down key alias.
    pub const key_pagedown: Key = Input.key_pagedown;
    /// F1 key alias.
    pub const key_f1: Key = Input.key_f1;
    /// F2 key alias.
    pub const key_f2: Key = Input.key_f2;
    /// F3 key alias.
    pub const key_f3: Key = Input.key_f3;
    /// F4 key alias.
    pub const key_f4: Key = Input.key_f4;
    /// F5 key alias.
    pub const key_f5: Key = Input.key_f5;
    /// F6 key alias.
    pub const key_f6: Key = Input.key_f6;
    /// F7 key alias.
    pub const key_f7: Key = Input.key_f7;
    /// F8 key alias.
    pub const key_f8: Key = Input.key_f8;
    /// F9 key alias.
    pub const key_f9: Key = Input.key_f9;
    /// F10 key alias.
    pub const key_f10: Key = Input.key_f10;
    /// F11 key alias.
    pub const key_f11: Key = Input.key_f11;
    /// F12 key alias.
    pub const key_f12: Key = Input.key_f12;
    pub const key_kp_0: Key = Input.key_kp_0;
    pub const key_kp_1: Key = Input.key_kp_1;
    pub const key_kp_2: Key = Input.key_kp_2;
    pub const key_kp_3: Key = Input.key_kp_3;
    pub const key_kp_4: Key = Input.key_kp_4;
    pub const key_kp_5: Key = Input.key_kp_5;
    pub const key_kp_6: Key = Input.key_kp_6;
    pub const key_kp_7: Key = Input.key_kp_7;
    pub const key_kp_8: Key = Input.key_kp_8;
    pub const key_kp_9: Key = Input.key_kp_9;
    pub const key_kp_decimal: Key = Input.key_kp_decimal;
    pub const key_kp_add: Key = Input.key_kp_add;
    pub const key_kp_subtract: Key = Input.key_kp_subtract;
    pub const key_kp_multiply: Key = Input.key_kp_multiply;
    pub const key_kp_divide: Key = Input.key_kp_divide;
    pub const key_kp_enter: Key = Input.key_kp_enter;

    pub const mouse_button_none: MouseButton = Input.MouseButton.none;
    pub const mouse_button_left: MouseButton = Input.MouseButton.left;
    pub const mouse_button_middle: MouseButton = Input.MouseButton.middle;
    pub const mouse_button_right: MouseButton = Input.MouseButton.right;
    pub const mouse_button_wheel_up: MouseButton = Input.MouseButton.wheel_up;
    pub const mouse_button_wheel_down: MouseButton = Input.MouseButton.wheel_down;

    pub const mouse_press: MouseEventKind = Input.MouseEventKind.press;
    pub const mouse_release: MouseEventKind = Input.MouseEventKind.release;
    pub const mouse_move: MouseEventKind = Input.MouseEventKind.move;
    pub const mouse_wheel: MouseEventKind = Input.MouseEventKind.wheel;

    /// Read-only render-facing view of visible terminal state.
    pub const RenderView = struct {
        rows: u16,
        cols: u16,
        cursor_row: u16,
        cursor_col: u16,
        cursor_visible: bool,
        cursor_shape: GridNs.CursorShape,
        is_alternate_screen: bool,
        screen: *const GridNs.GridModel,

        pub fn cellAt(self: RenderView, row: u16, col: u16) u21 {
            return self.screen.cellAt(row, col);
        }

        pub fn cellInfoAt(self: RenderView, row: u16, col: u16) GridNs.Cell {
            return self.screen.cellInfoAt(row, col);
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
        len: usize = 0,
    };

    const ScreenState = struct {
        const CursorSnapshot = struct {
            row: u16,
            col: u16,
            wrap_pending: bool,
            cursor_visible: bool,
        };

        primary: GridNs.GridModel,
        alternate: GridNs.GridModel,
        alt_active: bool = false,
        saved_primary_cursor: ?CursorSnapshot = null,

        fn init(primary: GridNs.GridModel, alternate: GridNs.GridModel) ScreenState {
            return .{ .primary = primary, .alternate = alternate };
        }

        pub fn active(self: *ScreenState) *GridNs.GridModel {
            return if (self.alt_active) &self.alternate else &self.primary;
        }

        pub fn activeConst(self: *const ScreenState) *const GridNs.GridModel {
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
            }
            if (clear_alt) self.alternate.reset();
            self.alt_active = true;
            self.alternate.markAllDirty();
        }

        pub fn exitAlt(self: *ScreenState, restore_cursor: bool) void {
            self.alt_active = false;
            if (restore_cursor) {
                if (self.saved_primary_cursor) |saved| {
                    self.primary.cursor_row = @min(saved.row, self.primary.rows -| 1);
                    self.primary.cursor_col = @min(saved.col, self.primary.cols -| 1);
                    self.primary.wrap_pending = saved.wrap_pending;
                    self.primary.cursor_visible = saved.cursor_visible;
                }
                self.saved_primary_cursor = null;
            }
            self.primary.markAllDirty();
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

    /// Initialize vt_core without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var apply_flow = try Interpret.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        const state = GridNs.GridModel.init(rows, cols);
        const alt_state = GridNs.GridModel.init(rows, cols);
        return VtCore{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenState.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Initialize vt_core with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var apply_flow = try Interpret.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        var state = try GridNs.GridModel.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.GridModel.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenState.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Initialize vt_core with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !VtCore {
        var apply_flow = try Interpret.ApplyFlow.init(allocator);
        errdefer apply_flow.deinit();
        var state = try GridNs.GridModel.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.GridModel.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .apply_flow = apply_flow,
            .screen_state = ScreenState.init(state, alt_state),
            .selection = Selection.SelectionState.init(),
            .host = HostState.init(),
        };
    }

    /// Release vt_core-owned resources.
    pub fn deinit(self: *VtCore) void {
        self.host.deinit(self.allocator);
        self.kitty.deinit(self.allocator);
        self.screen_state.deinit(self.allocator);
        self.apply_flow.deinit();
    }

    /// Feed one input byte into parser state.
    pub fn feedByte(self: *VtCore, byte: u8) void {
        self.apply_flow.feedByte(byte);
    }

    /// Feed a byte slice into parser state.
    pub fn feedSlice(self: *VtCore, bytes: []const u8) void {
        self.apply_flow.feedSlice(bytes);
    }

    /// Apply queued events to the screen state.
    pub fn apply(self: *VtCore) void {
        for (self.apply_flow.events()) |ev| {
            if (Interpret.process(ev)) |sem_ev| {
                self.applySemantic(sem_ev);
            }
        }
        self.apply_flow.clear();
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Clear queued events without applying.
    pub fn clear(self: *VtCore) void {
        self.apply_flow.clear();
    }

    pub fn pendingOutput(self: *const VtCore) []const u8 {
        return self.host.pending_output.items;
    }

    pub fn clearPendingOutput(self: *VtCore) void {
        self.host.pending_output.clearRetainingCapacity();
    }

    pub fn hyperlinkUriForId(self: *const VtCore, link_id: u32) ?[]const u8 {
        if (link_id == 0) return null;
        const idx = link_id - 1;
        if (idx >= self.host.hyperlink_targets.items.len) return null;
        return self.host.hyperlink_targets.items[idx];
    }

    pub fn pendingClipboardSet(self: *const VtCore) ?[]const u8 {
        if (self.host.pending_clipboard) |req| return req.raw;
        return null;
    }

    pub fn drainPendingClipboardSet(self: *VtCore, allocator: std.mem.Allocator) !?[]u8 {
        const pending = self.pendingClipboardSet() orelse return null;
        defer self.clearPendingClipboardSet();
        return OscActions.decodeClipboardSet(allocator, pending) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        };
    }

    pub fn kittyClipboardMode(self: *const VtCore) bool {
        return self.modes.kitty_clipboard;
    }

    pub fn sixelDisplayMode(self: *const VtCore) bool {
        return self.modes.sixel_display_mode;
    }

    pub fn reverseWraparoundMode(self: *const VtCore) bool {
        return self.modes.reverse_wraparound_mode;
    }

    pub fn extendedReverseWraparoundMode(self: *const VtCore) bool {
        return self.modes.extended_reverse_wraparound_mode;
    }

    pub fn mediaCopyRequest(self: *const VtCore) ?u16 {
        return self.host.media_copy_request;
    }

    pub fn dcsPayloadKind(self: *const VtCore) ?Interpret.DcsPayloadKind {
        if (self.host.dcs_payload) |payload| return payload.kind;
        return null;
    }

    pub fn dcsPayload(self: *const VtCore) ?[]const u8 {
        if (self.host.dcs_payload) |payload| return payload.payload;
        return null;
    }

    pub fn legacyControl(self: *const VtCore) ?Interpret.LegacyControlKind {
        return self.host.legacy_control;
    }

    pub fn kittyShellMark(self: *const VtCore) KittyShellMark {
        return self.kitty.global.shell_mark;
    }

    pub fn kittyNotificationCount(self: *const VtCore) usize {
        return self.kitty.global.notifications.items.len;
    }

    pub fn kittyNotificationAt(self: *const VtCore, idx: usize) ?KittyNotificationRequest {
        if (idx >= self.kitty.global.notifications.items.len) return null;
        return self.kitty.global.notifications.items[idx];
    }

    pub fn kittyFileTransferRequest(self: *const VtCore) ?[]const u8 {
        return self.kitty.global.file_transfer_request;
    }

    pub fn kittyTextSizeRequest(self: *const VtCore) ?[]const u8 {
        return self.kitty.global.text_size_request;
    }

    pub fn kittyPointerShape(self: *const VtCore) []const u8 {
        return self.activeKittyScreenConst().pointer.currentName();
    }

    pub fn kittyMultipleCursorCount(self: *const VtCore) u16 {
        return self.activeKittyScreenConst().multiple_cursor_count;
    }

    pub fn pointerMode(self: *const VtCore) u2 {
        return self.modes.pointer_mode;
    }

    pub fn kittyColorStackDepth(self: *const VtCore) u16 {
        return self.kitty.global.color_stack_depth;
    }

    pub fn terminalColorState(self: *const VtCore) TerminalColorState {
        return self.host.colors;
    }

    pub fn kittyGraphicsImageCount(self: *const VtCore) usize {
        return self.kitty.global.graphics.imageCount();
    }

    pub fn kittyGraphicsImageAt(self: *const VtCore, idx: usize) ?KittyGraphicsImage {
        return self.kitty.global.graphics.imageAt(idx);
    }

    pub fn kittyGraphicsPlacementCount(self: *const VtCore) usize {
        return self.kitty.global.graphics.placementCount();
    }

    pub fn kittyGraphicsPlacementAt(self: *const VtCore, idx: usize) ?KittyGraphicsPlacement {
        return self.kitty.global.graphics.placementAt(idx);
    }

    pub fn kittyGraphicsFrameCount(self: *const VtCore) usize {
        return self.kitty.global.graphics.frameCount();
    }

    pub fn kittyGraphicsFrameAt(self: *const VtCore, idx: usize) ?KittyGraphicsFrame {
        return self.kitty.global.graphics.frameAt(idx);
    }

    pub fn clearPendingClipboardSet(self: *VtCore) void {
        if (self.host.pending_clipboard) |req| self.allocator.free(req.raw);
        self.host.pending_clipboard = null;
    }

    /// Reset parser state and clear queue.
    pub fn reset(self: *VtCore) void {
        self.apply_flow.reset();
    }

    /// Reset visible grid state only.
    pub fn resetScreen(self: *VtCore) void {
        self.activeStateMut().reset();
    }

    /// Resize visible screen while preserving history ring contents.
    pub fn resize(self: *VtCore, rows: u16, cols: u16) !void {
        try self.screen_state.resize(self.allocator, rows, cols);
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Return read-only screen state reference.
    pub fn screen(self: *const VtCore) *const GridNs.GridModel {
        return self.activeState();
    }

    /// Return a stable render-facing snapshot view of visible state.
    pub fn renderView(self: *const VtCore) RenderView {
        return .{
            .rows = self.activeState().rows,
            .cols = self.activeState().cols,
            .cursor_row = self.activeState().cursor_row,
            .cursor_col = self.activeState().cursor_col,
            .cursor_visible = self.activeState().cursor_visible,
            .cursor_shape = self.activeState().cursor_style.shape,
            .is_alternate_screen = self.screen_state.alt_active,
            .screen = self.activeState(),
        };
    }

    pub fn peekDirtyRows(self: *const VtCore) ?DirtyRows {
        return self.activeState().peekDirtyRows();
    }

    pub fn clearDirtyRows(self: *VtCore) void {
        self.activeStateMut().clearDirtyRows();
    }

    pub fn synchronizedOutputActive(self: *const VtCore) bool {
        return self.modes.synchronized_output;
    }

    /// Return queued event count.
    pub fn queuedEventCount(self: *const VtCore) usize {
        return self.apply_flow.len();
    }

    /// Return the most recent queued title-set event before apply clears the queue.
    pub fn latestTitleSet(self: *const VtCore) ?[]const u8 {
        var i = self.apply_flow.events().len;
        while (i > 0) {
            i -= 1;
            const ev = self.apply_flow.events()[i];
            switch (ev) {
                .osc => |osc| if (osc.kind == .title) return osc.payload,
                else => {},
            }
        }
        return null;
    }

    /// Return history cell by recency index and column.
    pub fn historyRowAt(self: *const VtCore, history_idx: usize, col: u16) u21 {
        if (self.screen_state.alt_active) return 0;
        return self.screen_state.primary.historyRowAt(history_idx, col);
    }

    pub fn historyCellAt(self: *const VtCore, history_idx: usize, col: u16) GridNs.Cell {
        if (self.screen_state.alt_active) return GridNs.default_cell;
        return self.screen_state.primary.historyCellAt(history_idx, col);
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const VtCore) usize {
        if (self.screen_state.alt_active) return 0;
        return self.screen_state.primary.historyCount();
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const VtCore) u16 {
        return self.screen_state.primary.historyCapacity();
    }

    pub fn isAlternateScreen(self: *const VtCore) bool {
        return self.screen_state.alt_active;
    }

    /// Return active selection snapshot or null.
    pub fn selectionState(self: *const VtCore) ?Selection.TerminalSelection {
        return self.selection.state();
    }

    /// Start selection at row/column coordinates.
    pub fn selectionStart(self: *VtCore, row: i32, col: u16) void {
        self.selection.start(row, col);
    }

    /// Update selection end coordinates.
    pub fn selectionUpdate(self: *VtCore, row: i32, col: u16) void {
        self.selection.update(row, col);
    }

    /// Finish current active selection.
    pub fn selectionFinish(self: *VtCore) void {
        self.selection.finish();
    }

    /// Clear current selection state.
    pub fn selectionClear(self: *VtCore) void {
        self.selection.clear();
    }

    /// Encode logical key and modifiers.
    pub fn encodeKey(self: *VtCore, key: Input.Key, mod: Input.Modifier) []const u8 {
        if (self.modes.keyboard_action_mode) {
            self.encode.len = 0;
            return self.encode.buf[0..0];
        }
        const encoded = Input.Codec.encodeKey(self.encode.buf[0..], key, mod, self.modes.application_cursor_keys, self.modes.application_keypad, self.modes.modify_other_keys, self.modes.key_format[4], self.activeKittyKeyboardFlags());
        if (self.modes.newline_mode and key == Input.key_enter and std.mem.eql(u8, encoded, "\r")) {
            self.encode.buf[0] = '\r';
            self.encode.buf[1] = '\n';
            self.encode.len = 2;
            return self.encode.buf[0..2];
        }
        self.encode.len = encoded.len;
        return encoded;
    }

    pub fn kittyKeyboardFlags(self: *const VtCore) u32 {
        return self.activeKittyKeyboardFlags();
    }

    pub fn isApplicationKeypad(self: *const VtCore) bool {
        return self.modes.application_keypad;
    }

    pub fn modifyOtherKeys(self: *const VtCore) i8 {
        return self.modes.modify_other_keys;
    }

    pub fn keyFormatOption(self: *const VtCore, resource: u8) u16 {
        return if (self.isKeyFormatResource(resource)) self.modes.key_format[resource] else 0;
    }

    pub fn isKeyFormatResource(self: *const VtCore, resource: u8) bool {
        _ = self;
        return resource <= 4 or resource == 6 or resource == 7;
    }

    /// Encode mouse event payload (placeholder surface).
    pub fn encodeMouse(self: *VtCore, event: Input.MouseEvent) []const u8 {
        LocatorNs.handleMouseEvent(&self.host.locator, self.allocator, &self.host.pending_output, self.encode.buf[0..], event);
        const encoded = Input.Codec.encodeMouse(self.encode.buf[0..], event, self.modes.mouse_tracking, self.modes.mouse_protocol);
        self.encode.len = encoded.len;
        return encoded;
    }

    pub fn encodeFocusIn(self: *VtCore) []const u8 {
        const encoded = if (self.modes.focus_reporting) "\x1b[I" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        self.encode.len = encoded.len;
        return self.encode.buf[0..encoded.len];
    }

    pub fn encodeFocusOut(self: *VtCore) []const u8 {
        const encoded = if (self.modes.focus_reporting) "\x1b[O" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        self.encode.len = encoded.len;
        return self.encode.buf[0..encoded.len];
    }

    pub fn encodePasteStart(self: *VtCore) []const u8 {
        const encoded = if (self.modes.bracketed_paste) "\x1b[200~" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        self.encode.len = encoded.len;
        return self.encode.buf[0..encoded.len];
    }

    pub fn encodePasteEnd(self: *VtCore) []const u8 {
        const encoded = if (self.modes.bracketed_paste) "\x1b[201~" else "";
        @memcpy(self.encode.buf[0..encoded.len], encoded);
        self.encode.len = encoded.len;
        return self.encode.buf[0..encoded.len];
    }

    /// Parse host key token into vt-core key constant.
    pub fn parseKeyToken(name: []const u8) ?Key {
        return Input.Codec.parseKeyToken(name);
    }

    /// Parse host modifier bitfield into vt-core modifier mask.
    pub fn parseModifierBits(mods: i32) Modifier {
        return Input.Codec.parseModifierBits(mods);
    }

    /// Parse host control token into control signal.
    pub fn parseControlToken(name: []const u8) ?ControlSignal {
        if (std.mem.eql(u8, name, "interrupt")) return .interrupt;
        if (std.mem.eql(u8, name, "terminate")) return .terminate;
        return null;
    }

    /// Capture deterministic snapshot of vt_core observable state.
    ///
    /// Returns an VtCoreSnapshot containing visible cells, cursor, modes, history,
    /// and selection state at the time of the call. Snapshots are host-neutral and
    /// do not capture parser state, queued events, or internal encode buffers.
    ///
    /// Determinism: identical observable vt_core state produces identical snapshots.
    /// Identical byte sequences fed via feedByte/feedSlice, followed by apply(),
    /// produce identical snapshots regardless of how bytes are chunked.
    ///
    /// Memory: allocates owned copies of cell and history buffers. Caller must
    /// call snapshot.deinit() to release them when done.
    ///
    /// Error: returns allocation error if owned buffer allocation fails.
    pub fn snapshot(self: *const VtCore) !Snapshot.VtCoreSnapshot {
        return Snapshot.VtCoreSnapshot.captureFromScreen(
            self.allocator,
            self.activeState(),
            self.selection.state(),
        );
    }

    fn activeState(self: *const VtCore) *const GridNs.GridModel {
        return self.screen_state.activeConst();
    }

    fn activeStateMut(self: *VtCore) *GridNs.GridModel {
        return self.screen_state.active();
    }

    fn activeKittyKeyboard(self: *VtCore) *KittyKeyboardStack {
        return &self.activeKittyScreen().keyboard;
    }

    fn activeKittyKeyboardConst(self: *const VtCore) *const KittyKeyboardStack {
        return &self.activeKittyScreenConst().keyboard;
    }

    fn activeKittyKeyboardFlags(self: *const VtCore) u32 {
        return self.activeKittyKeyboardConst().flags;
    }

    fn activeKittyScreen(self: *VtCore) *KittyScreenState {
        return self.kitty.activeScreen(self.screen_state.alt_active);
    }

    fn activeKittyScreenConst(self: *const VtCore) *const KittyScreenState {
        return self.kitty.activeScreenConst(self.screen_state.alt_active);
    }

    fn applySemantic(self: *VtCore, sem_ev: Interpret.SemanticEvent) void {
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
        if (Interpret.screenAction(sem_ev)) |screen_ev| self.activeStateMut().applyScreen(screen_ev);
    }
};

test "vt core tracks synchronized output private mode" {
    var vt = try VtCore.init(std.testing.allocator, 2, 8);
    defer vt.deinit();

    vt.feedSlice("\x1b[?2026h");
    vt.apply();
    try std.testing.expect(vt.synchronizedOutputActive());

    vt.feedSlice("\x1b[?2026l");
    vt.apply();
    try std.testing.expect(!vt.synchronizedOutputActive());
}

test {
    _ = @import("test/apply_flow_regression.zig");
    _ = @import("test/vt_core_graphics.zig");
    _ = @import("test/vt_core_modes_reports.zig");
    _ = @import("test/vt_core_osc_colors.zig");
    _ = @import("test/vt_core_surface.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/action_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/vt_core_end_to_end.zig");
}
