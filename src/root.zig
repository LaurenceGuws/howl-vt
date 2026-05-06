//! Responsibility: provide the vt-core package entry owner.
//! Ownership: primary embeddable terminal boundary.
//! Reason: expose one host-neutral terminal object while keeping domain internals behind sibling owners.

const std = @import("std");
const grid_owner = @import("grid.zig");
const grid_model = @import("grid/model.zig");
const input_mod = @import("input.zig");
const interpret_owner = @import("interpret.zig");
const kitty_owner = @import("kitty.zig");
const locator_owner = @import("locator.zig");
const osc_color_owner = @import("osc_color.zig");
const selection_owner = @import("selection.zig");
const snapshot_owner = @import("snapshot.zig");
const terminal_mode_owner = @import("terminal_mode.zig");
const terminal_report_owner = @import("terminal_report.zig");

const GridNs = grid_owner.Grid;
const Input = input_mod.Input;
const Interpret = interpret_owner.Interpret;
const KittyNs = kitty_owner.Kitty;
const LocatorNs = locator_owner.Locator;
const OscColorNs = osc_color_owner.OscColor;
const Selection = selection_owner.Selection;
const Snapshot = snapshot_owner.Snapshot;
const TerminalModeNs = terminal_mode_owner.TerminalMode;
const TerminalReportNs = terminal_report_owner.TerminalReport;

/// Host-neutral terminal facade.
pub const VtCore = struct {
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

    allocator: std.mem.Allocator,
    pipeline: Interpret.Pipeline,
    primary_state: GridNs.GridModel,
    alt_state: GridNs.GridModel,
    alt_active: bool,
    saved_primary_cursor: ?struct {
        row: u16,
        col: u16,
        wrap_pending: bool,
        cursor_visible: bool,
    } = null,
    selection: Selection.SelectionState,
    keyboard_action_mode: bool = false,
    application_cursor_keys: bool = false,
    application_keypad: bool = false,
    send_receive_mode: bool = false,
    newline_mode: bool = false,
    modify_other_keys: i8 = 0,
    focus_reporting: bool = false,
    bracketed_paste: bool = false,
    kitty_main: KittyScreenState = .{},
    kitty_alt: KittyScreenState = .{},
    mouse_tracking: Input.MouseTrackingMode = .off,
    mouse_protocol: Input.MouseProtocol = .none,
    saved_dec_modes: [16]TerminalModeNs.SavedDecMode = [_]TerminalModeNs.SavedDecMode{.{ .mode = 0, .state = 0 }} ** 16,
    saved_dec_mode_count: u8 = 0,
    xtchecksum_flags: u16 = 0,
    terminal_colors: TerminalColorState = .{},
    pending_output: std.ArrayList(u8),
    hyperlink_targets: std.ArrayList([]u8),
    pending_clipboard: ?ClipboardRequest = null,
    kitty: KittyGlobalState = .{},
    locator: LocatorState = .{},
    encode_buf: [64]u8 = undefined,
    encode_len: usize = 0,

    /// Initialize vt_core without cell storage.
    pub fn init(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var pipeline = try Interpret.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        const state = GridNs.GridModel.init(rows, cols);
        const alt_state = GridNs.GridModel.init(rows, cols);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .primary_state = state,
            .alt_state = alt_state,
            .alt_active = false,
            .selection = Selection.SelectionState.init(),
            .pending_output = std.ArrayList(u8).empty,
            .hyperlink_targets = std.ArrayList([]u8).empty,
        };
    }

    /// Initialize vt_core with cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) !VtCore {
        var pipeline = try Interpret.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try GridNs.GridModel.initWithCells(allocator, rows, cols);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.GridModel.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .primary_state = state,
            .alt_state = alt_state,
            .alt_active = false,
            .selection = Selection.SelectionState.init(),
            .pending_output = std.ArrayList(u8).empty,
            .hyperlink_targets = std.ArrayList([]u8).empty,
        };
    }

    /// Initialize vt_core with cell and history storage.
    pub fn initWithCellsAndHistory(allocator: std.mem.Allocator, rows: u16, cols: u16, history_capacity: u16) !VtCore {
        var pipeline = try Interpret.Pipeline.init(allocator);
        errdefer pipeline.deinit();
        var state = try GridNs.GridModel.initWithCellsAndHistory(allocator, rows, cols, history_capacity);
        errdefer state.deinit(allocator);
        var alt_state = try GridNs.GridModel.initWithCells(allocator, rows, cols);
        errdefer alt_state.deinit(allocator);
        return VtCore{
            .allocator = allocator,
            .pipeline = pipeline,
            .primary_state = state,
            .alt_state = alt_state,
            .alt_active = false,
            .selection = Selection.SelectionState.init(),
            .pending_output = std.ArrayList(u8).empty,
            .hyperlink_targets = std.ArrayList([]u8).empty,
        };
    }

    /// Release vt_core-owned resources.
    pub fn deinit(self: *VtCore) void {
        for (self.hyperlink_targets.items) |uri| self.allocator.free(uri);
        self.hyperlink_targets.deinit(self.allocator);
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.kitty.deinit(self.allocator);
        self.pending_output.deinit(self.allocator);
        self.primary_state.deinit(self.allocator);
        self.alt_state.deinit(self.allocator);
        self.pipeline.deinit();
    }

    /// Feed one input byte into parser state.
    pub fn feedByte(self: *VtCore, byte: u8) void {
        self.pipeline.feedByte(byte);
    }

    /// Feed a byte slice into parser state.
    pub fn feedSlice(self: *VtCore, bytes: []const u8) void {
        self.pipeline.feedSlice(bytes);
    }

    /// Apply queued events to the grid model.
    pub fn apply(self: *VtCore) void {
        for (self.pipeline.events()) |ev| {
            if (Interpret.process(ev)) |sem_ev| {
                self.applySemantic(sem_ev);
            }
        }
        self.pipeline.clear();
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Clear queued events without applying.
    pub fn clear(self: *VtCore) void {
        self.pipeline.clear();
    }

    pub fn pendingOutput(self: *const VtCore) []const u8 {
        return self.pending_output.items;
    }

    pub fn clearPendingOutput(self: *VtCore) void {
        self.pending_output.clearRetainingCapacity();
    }

    pub fn hyperlinkUriForId(self: *const VtCore, link_id: u32) ?[]const u8 {
        if (link_id == 0) return null;
        const idx = link_id - 1;
        if (idx >= self.hyperlink_targets.items.len) return null;
        return self.hyperlink_targets.items[idx];
    }

    pub fn pendingClipboardSet(self: *const VtCore) ?[]const u8 {
        if (self.pending_clipboard) |req| return req.raw;
        return null;
    }

    pub fn kittyShellMark(self: *const VtCore) KittyShellMark {
        return self.kitty.shell_mark;
    }

    pub fn kittyNotificationCount(self: *const VtCore) usize {
        return self.kitty.notifications.items.len;
    }

    pub fn kittyNotificationAt(self: *const VtCore, idx: usize) ?KittyNotificationRequest {
        if (idx >= self.kitty.notifications.items.len) return null;
        return self.kitty.notifications.items[idx];
    }

    pub fn kittyPointerShape(self: *const VtCore) []const u8 {
        return self.activeKittyScreenConst().pointer.currentName();
    }

    pub fn kittyColorStackDepth(self: *const VtCore) u16 {
        return self.kitty.color_stack_depth;
    }

    pub fn terminalColorState(self: *const VtCore) TerminalColorState {
        return self.terminal_colors;
    }

    pub fn kittyGraphicsImageCount(self: *const VtCore) usize {
        return self.kitty.graphics.imageCount();
    }

    pub fn kittyGraphicsImageAt(self: *const VtCore, idx: usize) ?KittyGraphicsImage {
        return self.kitty.graphics.imageAt(idx);
    }

    pub fn kittyGraphicsPlacementCount(self: *const VtCore) usize {
        return self.kitty.graphics.placementCount();
    }

    pub fn kittyGraphicsPlacementAt(self: *const VtCore, idx: usize) ?KittyGraphicsPlacement {
        return self.kitty.graphics.placementAt(idx);
    }

    pub fn kittyGraphicsFrameCount(self: *const VtCore) usize {
        return self.kitty.graphics.frameCount();
    }

    pub fn kittyGraphicsFrameAt(self: *const VtCore, idx: usize) ?KittyGraphicsFrame {
        return self.kitty.graphics.frameAt(idx);
    }

    pub fn clearPendingClipboardSet(self: *VtCore) void {
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        self.pending_clipboard = null;
    }

    /// Reset parser state and clear queue.
    pub fn reset(self: *VtCore) void {
        self.pipeline.reset();
    }

    /// Reset visible grid state only.
    pub fn resetScreen(self: *VtCore) void {
        self.activeStateMut().reset();
    }

    /// Resize visible screen while preserving history ring contents.
    pub fn resize(self: *VtCore, rows: u16, cols: u16) !void {
        try self.primary_state.resize(self.allocator, rows, cols);
        try self.alt_state.resize(self.allocator, rows, cols);
        self.selection.clearIfInvalidatedByGrid(self.activeState());
    }

    /// Return read-only grid model reference.
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
            .is_alternate_screen = self.alt_active,
            .screen = self.activeState(),
        };
    }

    pub fn peekDirtyRows(self: *const VtCore) ?DirtyRows {
        return self.activeState().peekDirtyRows();
    }

    pub fn clearDirtyRows(self: *VtCore) void {
        self.activeStateMut().clearDirtyRows();
    }

    /// Return queued event count.
    pub fn queuedEventCount(self: *const VtCore) usize {
        return self.pipeline.len();
    }

    /// Return the most recent queued title-set event before apply clears the queue.
    pub fn latestTitleSet(self: *const VtCore) ?[]const u8 {
        var i = self.pipeline.events().len;
        while (i > 0) {
            i -= 1;
            const ev = self.pipeline.events()[i];
            switch (ev) {
                .osc => |osc| if (osc.kind == .title) return osc.payload,
                else => {},
            }
        }
        return null;
    }

    /// Return history cell by recency index and column.
    pub fn historyRowAt(self: *const VtCore, history_idx: usize, col: u16) u21 {
        if (self.alt_active) return 0;
        return self.primary_state.historyRowAt(history_idx, col);
    }

    pub fn historyCellAt(self: *const VtCore, history_idx: usize, col: u16) GridNs.Cell {
        if (self.alt_active) return GridNs.default_cell;
        return self.primary_state.historyCellAt(history_idx, col);
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const VtCore) usize {
        if (self.alt_active) return 0;
        return self.primary_state.historyCount();
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const VtCore) u16 {
        return self.primary_state.historyCapacity();
    }

    pub fn isAlternateScreen(self: *const VtCore) bool {
        return self.alt_active;
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
        if (self.keyboard_action_mode) {
            self.encode_len = 0;
            return self.encode_buf[0..0];
        }
        const encoded = Input.Codec.encodeKey(self.encode_buf[0..], key, mod, self.application_cursor_keys, self.application_keypad, self.modify_other_keys, self.activeKittyKeyboardFlags());
        if (self.newline_mode and key == Input.key_enter and std.mem.eql(u8, encoded, "\r")) {
            self.encode_buf[0] = '\r';
            self.encode_buf[1] = '\n';
            self.encode_len = 2;
            return self.encode_buf[0..2];
        }
        self.encode_len = encoded.len;
        return encoded;
    }

    pub fn kittyKeyboardFlags(self: *const VtCore) u32 {
        return self.activeKittyKeyboardFlags();
    }

    pub fn isApplicationKeypad(self: *const VtCore) bool {
        return self.application_keypad;
    }

    pub fn modifyOtherKeys(self: *const VtCore) i8 {
        return self.modify_other_keys;
    }

    /// Encode mouse event payload (placeholder surface).
    pub fn encodeMouse(self: *VtCore, event: Input.MouseEvent) []const u8 {
        LocatorNs.handleMouseEvent(&self.locator, self.allocator, &self.pending_output, self.encode_buf[0..], event);
        const encoded = Input.Codec.encodeMouse(self.encode_buf[0..], event, self.mouse_tracking, self.mouse_protocol);
        self.encode_len = encoded.len;
        return encoded;
    }

    pub fn encodeFocusIn(self: *VtCore) []const u8 {
        const encoded = if (self.focus_reporting) "\x1b[I" else "";
        @memcpy(self.encode_buf[0..encoded.len], encoded);
        self.encode_len = encoded.len;
        return self.encode_buf[0..encoded.len];
    }

    pub fn encodeFocusOut(self: *VtCore) []const u8 {
        const encoded = if (self.focus_reporting) "\x1b[O" else "";
        @memcpy(self.encode_buf[0..encoded.len], encoded);
        self.encode_len = encoded.len;
        return self.encode_buf[0..encoded.len];
    }

    pub fn encodePasteStart(self: *VtCore) []const u8 {
        const encoded = if (self.bracketed_paste) "\x1b[200~" else "";
        @memcpy(self.encode_buf[0..encoded.len], encoded);
        self.encode_len = encoded.len;
        return self.encode_buf[0..encoded.len];
    }

    pub fn encodePasteEnd(self: *VtCore) []const u8 {
        const encoded = if (self.bracketed_paste) "\x1b[201~" else "";
        @memcpy(self.encode_buf[0..encoded.len], encoded);
        self.encode_len = encoded.len;
        return self.encode_buf[0..encoded.len];
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
        return if (self.alt_active) &self.alt_state else &self.primary_state;
    }

    fn activeStateMut(self: *VtCore) *GridNs.GridModel {
        return if (self.alt_active) &self.alt_state else &self.primary_state;
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
        return if (self.alt_active) &self.kitty_alt else &self.kitty_main;
    }

    fn activeKittyScreenConst(self: *const VtCore) *const KittyScreenState {
        return if (self.alt_active) &self.kitty_alt else &self.kitty_main;
    }

    fn resetTerminalState(self: *VtCore) void {
        self.activeStateMut().reset();
        self.kitty_main.pointer.len = 0;
        self.kitty_alt.pointer.len = 0;
        self.kitty.color_stack_depth = 0;
        self.locator = .{};
    }

    fn applySemantic(self: *VtCore, sem_ev: Interpret.SemanticEvent) void {
        switch (sem_ev) {
            .enter_alt_screen => |opts| TerminalModeNs.enterAltScreen(self, opts.clear, opts.save_cursor),
            .exit_alt_screen => |opts| TerminalModeNs.exitAltScreen(self, opts.restore_cursor),
            .application_cursor_keys => |enabled| self.application_cursor_keys = enabled,
            .application_keypad => |enabled| self.application_keypad = enabled,
            .ansi_mode_set => |modes| TerminalModeNs.setAnsiModes(self, modes.params[0..modes.param_count], true),
            .ansi_mode_reset => |modes| TerminalModeNs.setAnsiModes(self, modes.params[0..modes.param_count], false),
            .ansi_mode_query => |mode| TerminalReportNs.appendAnsiModeReport(self.allocator, &self.pending_output, self.encode_buf[0..], mode, TerminalModeNs.ansiModeState(self, mode)),
            .modify_other_keys_set => |value| self.modify_other_keys = value,
            .modify_other_keys_query => TerminalReportNs.appendModifyOtherKeysReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.modify_other_keys),
            .modify_other_keys_disable => self.modify_other_keys = -1,
            .focus_reporting => |enabled| self.focus_reporting = enabled,
            .bracketed_paste => |enabled| self.bracketed_paste = enabled,
            .kitty_keyboard_set => |req| self.activeKittyKeyboard().set(req.flags, req.mode),
            .kitty_keyboard_query => self.activeKittyKeyboardConst().appendReport(self.allocator, &self.pending_output, self.encode_buf[0..]),
            .kitty_keyboard_push => |flags| self.activeKittyKeyboard().push(flags),
            .kitty_keyboard_pop => |count| self.activeKittyKeyboard().pop(count),
            .kitty_shell_mark => |mark| KittyNs.setShellMark(self.allocator, &self.kitty.shell_mark, mark),
            .kitty_notification => |notification| KittyNs.appendNotification(self.allocator, &self.kitty.notifications, notification),
            .kitty_pointer_shape => |cmd| switch (cmd.action) {
                '<' => self.activeKittyScreen().pointer.pop(),
                '>' => self.activeKittyScreen().pointer.push(cmd.names),
                '?' => self.activeKittyScreenConst().pointer.appendQuery(self.allocator, &self.pending_output, cmd.names),
                else => self.activeKittyScreen().pointer.set(cmd.names),
            },
            .kitty_color_stack => |cmd| switch (cmd) {
                .push => KittyNs.Color.pushState(&self.kitty.color_stack, &self.terminal_colors, &self.kitty.color_stack_depth),
                .pop => KittyNs.Color.popState(&self.kitty.color_stack, &self.terminal_colors, &self.kitty.color_stack_depth),
            },
            .terminal_color_control => |cmd| switch (cmd.command) {
                21 => KittyNs.Color.handleKittyControl(self.allocator, &self.terminal_colors, &self.pending_output, cmd.payload),
                4 => OscColorNs.handleXtermPaletteControl(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], cmd.payload),
                10 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], .foreground, cmd.payload),
                11 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], .background, cmd.payload),
                12 => OscColorNs.handleXtermSpecialColor(self.allocator, &self.terminal_colors, &self.pending_output, self.encode_buf[0..], .cursor, cmd.payload),
                104 => OscColorNs.resetXtermPalette(&self.terminal_colors, cmd.payload),
                110 => self.terminal_colors.foreground = GridNs.default_fg,
                111 => self.terminal_colors.background = GridNs.default_bg,
                112 => self.terminal_colors.cursor = null,
                else => {},
            },
            .mouse_tracking_off => self.mouse_tracking = .off,
            .mouse_tracking_x10 => self.mouse_tracking = .x10,
            .mouse_tracking_normal => self.mouse_tracking = .normal,
            .mouse_tracking_button_event => self.mouse_tracking = .button_event,
            .mouse_tracking_any_event => self.mouse_tracking = .any_event,
            .mouse_protocol_utf8 => |enabled| self.mouse_protocol = if (enabled) .utf8 else .none,
            .mouse_protocol_sgr => |enabled| self.mouse_protocol = if (enabled) .sgr else .none,
            .mouse_protocol_urxvt => |enabled| self.mouse_protocol = if (enabled) .urxvt else .none,
            .hyperlink_set => |uri| self.activeStateMut().setCurrentLinkId(self.internHyperlink(uri)),
            .hyperlink_clear => self.activeStateMut().setCurrentLinkId(0),
            .clipboard_set => |payload| self.setPendingClipboard(payload),
            .dec_mode_query => |mode| TerminalReportNs.appendDecModeReport(self.allocator, &self.pending_output, self.encode_buf[0..], mode, TerminalModeNs.decModeState(self, mode)),
            .dec_mode_save => |modes| TerminalModeNs.saveDecModes(self, modes.params[0..modes.param_count]),
            .dec_mode_restore => |modes| TerminalModeNs.restoreDecModes(self, modes.params[0..modes.param_count]),
            .device_status_report => self.appendPendingOutput("\x1b[0n"),
            .dec_device_status_report => |param| LocatorNs.appendDeviceStatusReport(self.allocator, &self.pending_output, self.encode_buf[0..], param),
            .cursor_position_report => TerminalReportNs.appendCursorPositionReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.renderView()),
            .dec_cursor_position_report => TerminalReportNs.appendDecCursorPositionReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.renderView()),
            .primary_device_attributes => self.appendPendingOutput("\x1b[?62;22c"),
            .secondary_device_attributes => self.appendPendingOutput("\x1b[>1;10;0c"),
            .tertiary_device_attributes => self.appendPendingOutput("\x1bP!|00000000\x1b\\"),
            .xtchecksum => |flags| self.xtchecksum_flags = flags,
            .rect_checksum_request => |req| {
                const checksum = TerminalReportNs.computeRectChecksum(self.activeState(), self.xtchecksum_flags, req.page, req.area);
                TerminalReportNs.appendRectChecksumReport(self.allocator, &self.pending_output, self.encode_buf[0..], req, checksum);
            },
            .selected_graphic_rendition_report => |area| TerminalReportNs.appendSelectedGraphicRenditionReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.activeState(), area),
            .presentation_state_report => |kind| switch (kind) {
                1 => TerminalReportNs.appendCursorInformationReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.renderView(), self.pipeline.deccirCharsetState()),
                2 => TerminalReportNs.appendTabStopReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.activeState()),
                else => self.appendPendingOutput("\x1bP0$u\x1b\\"),
            },
            .displayed_extent_report => TerminalReportNs.appendDisplayedExtentReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.renderView()),
            .terminal_parameters_report => |kind| TerminalReportNs.appendTerminalParametersReport(self.allocator, &self.pending_output, self.encode_buf[0..], kind),
            .xtreportcolors => TerminalReportNs.appendColorStackReport(self.allocator, &self.pending_output, self.encode_buf[0..], self.kitty.color_stack.len),
            .locator_reporting => |cfg| LocatorNs.setReporting(&self.locator, cfg.mode, cfg.unit),
            .locator_filter => |area| LocatorNs.setFilter(&self.locator, area),
            .locator_events => |modes| LocatorNs.setEvents(&self.locator, modes.params[0..modes.param_count]),
            .locator_request => |param| LocatorNs.appendReportForRequest(&self.locator, self.allocator, &self.pending_output, self.encode_buf[0..], param),
            .kitty_graphics => |cmd| self.kitty.graphics.handle(self.allocator, self.renderView(), &self.pending_output, self.encode_buf[0..], cmd),
            .reset_screen => self.resetTerminalState(),
            else => self.activeStateMut().apply(sem_ev),
        }
    }

    fn appendPendingOutput(self: *VtCore, bytes: []const u8) void {
        self.pending_output.appendSlice(self.allocator, bytes) catch {};
    }

    fn internHyperlink(self: *VtCore, uri: []const u8) u32 {
        for (self.hyperlink_targets.items, 0..) |existing, idx| {
            if (std.mem.eql(u8, existing, uri)) return @intCast(idx + 1);
        }
        const owned = self.allocator.dupe(u8, uri) catch return 0;
        self.hyperlink_targets.append(self.allocator, owned) catch {
            self.allocator.free(owned);
            return 0;
        };
        return @intCast(self.hyperlink_targets.items.len);
    }

    fn setPendingClipboard(self: *VtCore, payload: []const u8) void {
        if (self.pending_clipboard) |req| self.allocator.free(req.raw);
        const owned = self.allocator.dupe(u8, payload) catch {
            self.pending_clipboard = null;
            return;
        };
        self.pending_clipboard = .{ .raw = owned };
    }
};
test {
    _ = @import("test/pipeline_regression.zig");
    _ = @import("test/root_graphics.zig");
    _ = @import("test/root_input_modes_reports.zig");
    _ = @import("test/root_osc_and_colors.zig");
    _ = @import("test/root_surface.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/semantic_mapping.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/system_flows.zig");
}
