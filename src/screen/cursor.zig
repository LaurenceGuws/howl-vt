const color = @import("color.zig");

pub const CursorShape = enum {
    block,
    underline,
    bar,
    none,
};

pub const CursorStyle = struct {
    shape: CursorShape,
    blink: bool,
};

pub const CursorStyleCommand = union(enum) {
    restore_default,
    program_override: CursorStyle,
};

pub const Rgb = color.Rgb;

pub const default_cursor_style = CursorStyle{ .shape = .block, .blink = true };

pub const SemanticCursor = struct {
    row: u16,
    col: u16,
    visible: bool,
    effective_shape: CursorShape,
    blink_intent: bool,
    default_style: CursorStyle,
    program_override_style: ?CursorStyle,
    cursor_color: ?Rgb,
    cursor_text_color: ?Rgb,
    position_changed_by_client_at: u64,

    pub fn init(default_style: CursorStyle) SemanticCursor {
        return .{
            .row = 0,
            .col = 0,
            .visible = true,
            .effective_shape = default_style.shape,
            .blink_intent = default_style.blink,
            .default_style = default_style,
            .program_override_style = null,
            .cursor_color = null,
            .cursor_text_color = null,
            .position_changed_by_client_at = 0,
        };
    }

    pub fn reset(self: *SemanticCursor) void {
        const default_style = self.default_style;
        self.* = init(default_style);
    }

    pub fn resetForAltEntry(self: *SemanticCursor) void {
        self.row = 0;
        self.col = 0;
        self.effective_shape = .none;
        self.blink_intent = true;
        self.program_override_style = null;
        self.position_changed_by_client_at = 0;
    }

    pub fn effectiveStyle(self: *const SemanticCursor) CursorStyle {
        return .{ .shape = self.effective_shape, .blink = self.blink_intent };
    }

    pub fn setDefaultStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.default_style = style;
        if (self.program_override_style == null) self.applyStyle(style);
    }

    pub fn setProgramStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.program_override_style = style;
        self.applyStyle(style);
    }

    pub fn restoreSavedStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.program_override_style = if (style.shape == self.default_style.shape and style.blink == self.default_style.blink) null else style;
        self.applyStyle(style);
    }

    pub fn restoreDefaultStyle(self: *SemanticCursor) void {
        self.program_override_style = null;
        self.applyStyle(self.default_style);
    }

    pub fn setPositionByClient(self: *SemanticCursor, row: u16, col: u16) void {
        if (self.row != row or self.col != col) self.position_changed_by_client_at +|= 1;
        self.row = row;
        self.col = col;
    }

    pub fn setPositionStructural(self: *SemanticCursor, row: u16, col: u16) void {
        self.row = row;
        self.col = col;
    }

    pub fn setRowByClient(self: *SemanticCursor, row: u16) void {
        self.setPositionByClient(row, self.col);
    }

    pub fn setRowStructural(self: *SemanticCursor, row: u16) void {
        self.setPositionStructural(row, self.col);
    }

    pub fn setColByClient(self: *SemanticCursor, col: u16) void {
        self.setPositionByClient(self.row, col);
    }

    pub fn setColStructural(self: *SemanticCursor, col: u16) void {
        self.setPositionStructural(self.row, col);
    }

    fn applyStyle(self: *SemanticCursor, style: CursorStyle) void {
        self.effective_shape = style.shape;
        self.blink_intent = style.blink;
    }
};
