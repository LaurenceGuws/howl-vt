const state = @import("selection/state.zig");

pub const SelectionPos = state.SelectionPos;
pub const TerminalSelection = state.TerminalSelection;
pub const SelectionState = state.SelectionState;

pub const terminalState = state.terminalState;
pub const terminalStart = state.terminalStart;
pub const terminalUpdate = state.terminalUpdate;
pub const terminalFinish = state.terminalFinish;
pub const terminalClear = state.terminalClear;
