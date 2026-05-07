//! Responsibility: export the interpret domain owner surface.
//! Ownership: interpret package boundary.
//! Reason: keep one canonical owner for parser-to-grid translation flow.

const parser_events = @import("interpret/parser_events.zig");
const actions = @import("interpret/actions.zig");
const apply_flow = @import("interpret/apply_flow.zig");

/// Canonical interpret domain owner.
/// Parser event payload.
pub const Event = parser_events.Event;
/// Parser event queue owner.
pub const ParserEvents = parser_events.ParserEvents;
/// Semantic event payload.
pub const SemanticEvent = actions.SemanticEvent;
/// Grid-directed action subset.
pub const ScreenAction = actions.ScreenAction;
/// Report and query action subset.
pub const ReportAction = actions.ReportAction;
/// Mode and state action subset.
pub const ModeAction = actions.ModeAction;
/// Kitty-family action subset.
pub const KittyAction = actions.KittyAction;
/// Host/protocol-edge action subset.
pub const HostAction = actions.HostAction;
/// DCS payload classification.
pub const DcsPayloadKind = actions.DcsPayloadKind;
/// Legacy C0/ESC host-neutral control classification.
pub const LegacyControlKind = actions.LegacyControlKind;
/// ESC-final action subset.
pub const EscAction = actions.EscAction;
/// End-to-end interpretation apply-flow owner.
pub const ApplyFlow = apply_flow.ApplyFlow;

/// One-shot action mapping function.
pub const process = actions.process;
/// Convert terminal events into grid-directed actions.
pub const screenAction = actions.screenAction;
/// Convert terminal events into report/query actions.
pub const reportAction = actions.reportAction;
/// Convert terminal events into mode/state actions.
pub const modeAction = actions.modeAction;
/// Convert terminal events into kitty-family actions.
pub const kittyAction = actions.kittyAction;
/// Convert terminal events into host/protocol-edge actions.
pub const hostAction = actions.hostAction;
