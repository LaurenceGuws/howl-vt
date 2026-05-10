//! Responsibility: export the grid domain owner surface.
//! Ownership: grid package boundary.
//! Reason: keep one canonical owner for grid state and behavior.

const state = @import("state.zig");
const types = @import("types.zig");

/// Canonical grid domain owner.
/// Main terminal screen state.
pub const GridModel = state.GridModel;
pub const Color = types.Color;
pub const UnderlineStyle = types.UnderlineStyle;
pub const CellAttrs = types.CellAttrs;
pub const Cell = types.Cell;
pub const CursorShape = types.CursorShape;
pub const CursorStyle = types.CursorStyle;
pub const default_fg = types.default_fg;
pub const default_bg = types.default_bg;
pub const default_cell_attrs = types.default_cell_attrs;
pub const default_cell = types.default_cell;
pub const defaultCell = types.defaultCell;
pub const isCellContinuation = types.isCellContinuation;
