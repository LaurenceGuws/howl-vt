//! Responsibility: export the interpret domain owner surface.
//! Ownership: interpret package boundary.
//! Reason: keep one canonical owner for parser-to-grid translation flow.

const bridge = @import("interpret/bridge.zig");
const semantic = @import("interpret/semantic.zig");
const pipeline = @import("interpret/pipeline.zig");

/// Canonical interpret domain owner.
pub const Interpret = struct {
    /// Parser-bridge event payload.
    pub const Event = bridge.Event;
    /// Parser-to-grid bridge owner.
    pub const Bridge = bridge.Bridge;
    /// Semantic event payload.
    pub const SemanticEvent = semantic.SemanticEvent;
    /// Grid-directed semantic subset.
    pub const ScreenAction = semantic.ScreenAction;
    /// Report and query semantic subset.
    pub const ReportAction = semantic.ReportAction;
    /// Mode and state semantic subset.
    pub const ModeAction = semantic.ModeAction;
    /// Kitty-family semantic subset.
    pub const KittyAction = semantic.KittyAction;
    /// Host/protocol-edge semantic subset.
    pub const HostAction = semantic.HostAction;
    /// End-to-end interpretation pipeline owner.
    pub const Pipeline = pipeline.Pipeline;

    /// One-shot semantic processing function.
    pub const process = semantic.process;
    /// Convert semantic events into grid-directed actions.
    pub const screenAction = semantic.screenAction;
    /// Convert semantic events into report/query actions.
    pub const reportAction = semantic.reportAction;
    /// Convert semantic events into mode/state actions.
    pub const modeAction = semantic.modeAction;
    /// Convert semantic events into kitty-family actions.
    pub const kittyAction = semantic.kittyAction;
    /// Convert semantic events into host/protocol-edge actions.
    pub const hostAction = semantic.hostAction;
};
