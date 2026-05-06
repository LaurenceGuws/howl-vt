//! Responsibility: export the snapshot domain owner surface.
//! Ownership: snapshot package boundary.
//! Reason: keep one canonical owner for observable-state capture types.

const data = @import("snapshot/data.zig");

/// Canonical snapshot domain owner.
pub const Snapshot = struct {
    /// Serializable vt-core snapshot payload.
    pub const VtCoreSnapshot = data.VtCoreSnapshot;
};
