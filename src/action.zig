const parsed_events = @import("parser/events.zig");
const route = @import("action/route.zig");
const vocabulary = @import("action/vocabulary.zig");
const esc = @import("xterm/esc.zig");

pub const Event = parsed_events.Event;
pub const SemanticEvent = vocabulary.SemanticEvent;
pub const ScreenAction = vocabulary.ScreenAction;
pub const ReportAction = vocabulary.ReportAction;
pub const ModeAction = vocabulary.ModeAction;
pub const KittyAction = vocabulary.KittyAction;
pub const HostAction = vocabulary.HostAction;
pub const DcsPayloadKind = vocabulary.DcsPayloadKind;
pub const KittyGraphicsCommand = vocabulary.KittyGraphicsCommand;
pub const KittyNotificationCommand = vocabulary.KittyNotificationCommand;
pub const KittyShellMark = vocabulary.KittyShellMark;
pub const LegacyControlKind = vocabulary.LegacyControlKind;
pub const EscAction = esc.EscAction;

pub const process = route.process;
pub const screenAction = route.screenAction;
pub const apply = route.apply;
