//! Responsibility: capture and represent vt_core observable state snapshots.
//! Ownership: snapshot data authority.
//! Reason: provide host-neutral read-only snapshots for replay and diagnostic access.
//!
//! VtCoreSnapshot is a deterministic, read-only capture of vt_core observable state
//! at a point in time, aligned to the snapshot replay contract.
//! Snapshots are host-neutral data structures without persistence format or
//! cross-version guarantees.

const std = @import("std");
const selection_mod = @import("../selection/selection.zig");
const grid_mod = @import("../grid/grid.zig");

const Selection = selection_mod;
const Grid = grid_mod.Grid;

/// Deterministic snapshot of vt_core observable state.
///
/// Captures visible screen cells, cursor position, modes, history buffer, and
/// selection state. Does NOT capture parser state, queued events, or encode buffers.
///
/// Snapshots are deterministic: identical observable vt_core state produces
/// identical snapshots. Split-feed input chunking is transparent (same bytes fed
/// as chunks vs atomically produce identical final snapshot).
///
/// Snapshots own allocated buffers (cells, history); caller must call deinit()
/// to release them.
pub const VtCoreSnapshot = struct {
    /// Allocator used for cell and history buffer allocation.
    allocator: std.mem.Allocator,

    /// Screen dimensions: rows.
    rows: u16,

    /// Screen dimensions: columns.
    cols: u16,

    /// Cursor row in viewport coordinates (0 to rows-1).
    cursor_row: u16,

    /// Cursor column in viewport coordinates (0 to cols-1).
    cursor_col: u16,

    /// Cursor visibility mode state.
    cursor_visible: bool,

    /// Auto-wrap mode state.
    auto_wrap: bool,

    /// Owned copy of visible screen cell buffer (null if no cells configured).
    cells: ?[]u21,

    /// Owned copy of history buffer (null if no history configured).
    history: ?[]u21,

    /// Current number of rows in history buffer.
    history_count: usize,

    /// Configured history buffer capacity.
    history_capacity: u16,

    /// History write index for circular buffer wraparound calculation.
    history_write_idx: usize,

    /// Active selection state snapshot (null if inactive).
    selection: ?Selection.TerminalSelection,

    /// Capture snapshot from vt_core observable state; allocates owned buffers.
    ///
    /// This method extracts the observable state from a Grid and optional
    /// selection state, allocating owned copies of cell and history buffers.
    ///
    /// Determinism: identical screen and selection state produce identical snapshots.
    /// The snapshot captures only observable state; parser state, queued events,
    /// and encode buffers are not included.
    ///
    /// Memory: allocated cells and history buffers are owned by the returned snapshot.
    /// Caller must call snapshot.deinit() to release them. If allocation fails,
    /// the error is returned and no partial allocation is left outstanding.
    pub fn captureFromScreen(allocator: std.mem.Allocator, screen: *const Grid, selection: ?Selection.TerminalSelection) !VtCoreSnapshot {
        var snapshot = VtCoreSnapshot{
            .allocator = allocator,
            .rows = screen.rows,
            .cols = screen.cols,
            .cursor_row = screen.cursor_row,
            .cursor_col = screen.cursor_col,
            .cursor_visible = screen.cursor_visible,
            .auto_wrap = screen.auto_wrap,
            .cells = null,
            .history = null,
            .history_count = screen.history_count,
            .history_capacity = screen.history_capacity,
            .history_write_idx = screen.history_write_idx,
            .selection = selection,
        };
        errdefer {
            if (snapshot.cells) |c| allocator.free(c);
            if (snapshot.history) |h| allocator.free(h);
        }

        // Copy visible screen cells if present.
        if (screen.cells != null) {
            const size = @as(usize, screen.rows) * @as(usize, screen.cols);
            const owned_cells = try allocator.alloc(u21, size);
            var row: u16 = 0;
            while (row < screen.rows) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_cells[@as(usize, row) * @as(usize, screen.cols) + @as(usize, col)] = screen.cellAt(row, col);
                }
            }
            snapshot.cells = owned_cells;
        }

        // Copy history buffer if present.
        if (screen.history_count > 0 and screen.cols > 0) {
            const size = screen.history_count * @as(usize, screen.cols);
            const owned_history = try allocator.alloc(u21, size);
            var row: usize = 0;
            while (row < screen.history_count) : (row += 1) {
                var col: u16 = 0;
                while (col < screen.cols) : (col += 1) {
                    owned_history[row * @as(usize, screen.cols) + @as(usize, col)] = @intCast(screen.historyCellAt(screen.history_count - 1 - row, col).codepoint);
                }
            }
            snapshot.history = owned_history;
        }

        return snapshot;
    }

    /// Release owned cell and history buffers.
    ///
    /// Frees allocated buffers and clears their references. Safe to call multiple
    /// times; subsequent calls are no-ops. Must be called exactly once when snapshot
    /// is no longer needed.
    pub fn deinit(self: *VtCoreSnapshot) void {
        if (self.cells) |c| self.allocator.free(c);
        self.cells = null;
        if (self.history) |h| self.allocator.free(h);
        self.history = null;
    }

    /// Return visible cell codepoint by row and column (read-only).
    ///
    /// Returns the codepoint value at the given viewport coordinates.
    /// Returns 0 (null/empty) if row >= rows, col >= cols, or cells not configured.
    /// Reads are deterministic and never mutate snapshot state.
    pub fn cellAt(self: *const VtCoreSnapshot, row: u16, col: u16) u21 {
        const c = self.cells orelse return 0;
        if (row >= self.rows or col >= self.cols) return 0;
        return c[@as(usize, row) * self.cols + col];
    }

    /// Return history cell codepoint by recency index and column (read-only).
    ///
    /// Reads history in recency order: history_idx=0 is most recent row (-1 in
    /// History Selection coordinate model), history_idx=1 is next older, etc.
    ///
    /// Reads the flattened history projection in recency order. Returns 0 if
    /// history_idx >= history_count,
    /// col >= cols, or history not configured.
    ///
    /// Determinism: identical history buffer and indices produce identical results.
    /// Reads are const and never mutate snapshot state.
    pub fn historyRowAt(self: *const VtCoreSnapshot, history_idx: usize, col: u16) u21 {
        const h = self.history orelse return 0;
        if (history_idx >= self.history_count or col >= self.cols) return 0;
        const logical_slot = self.history_count - 1 - history_idx;
        return h[logical_slot * @as(usize, self.cols) + @as(usize, col)];
    }
};
