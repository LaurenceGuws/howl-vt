//! Responsibility: export the selection domain owner surface.
//! Ownership: selection package boundary.
//! Reason: keep one canonical owner for selection state and data shapes.

const state = @import("selection/state.zig");

/// Canonical selection domain owner.
/// Selection position payload.
pub const SelectionPos = state.SelectionPos;
/// Read-only terminal selection payload.
pub const TerminalSelection = state.TerminalSelection;
/// Mutable selection state owner.
pub const SelectionState = state.SelectionState;
