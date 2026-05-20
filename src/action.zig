//! Parser events, action routing, and action vocabulary.

const parsed_events = @import("parser/events.zig");
const route = @import("action/route.zig");
const vocabulary = @import("action/vocabulary.zig");

pub const Event = parsed_events.Event;
pub const SemanticEvent = route.SemanticEvent;
pub const ScreenAction = route.ScreenAction;
pub const ReportAction = route.ReportAction;
pub const ModeAction = route.ModeAction;
pub const KittyAction = route.KittyAction;
pub const HostAction = route.HostAction;
pub const DcsPayloadKind = route.DcsPayloadKind;
pub const KittyGraphicsCommand = vocabulary.KittyGraphicsCommand;
pub const KittyNotificationCommand = vocabulary.KittyNotificationCommand;
pub const KittyShellMark = vocabulary.KittyShellMark;
pub const LegacyControlKind = route.LegacyControlKind;
pub const EscAction = route.EscAction;

pub const process = route.process;
pub const screenAction = route.screenAction;
pub const reportAction = route.reportAction;
pub const modeAction = route.modeAction;
pub const kittyAction = route.kittyAction;
pub const hostAction = route.hostAction;
