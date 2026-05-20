const action = @import("action.zig");
const ffi = @import("ffi.zig");
const input = @import("input.zig");
const parser = @import("parser/main.zig");
const parser_owned_actions = @import("parser/owned_actions.zig");
const parser_queue = @import("parser/queue.zig");
const screen = @import("screen.zig");
const screen_set = @import("screen_set.zig");
const selection = @import("selection.zig");
const terminal = @import("terminal.zig");

pub const Action = action;
pub const Ffi = ffi;
pub const Input = input;
pub const Parser = parser;
pub const ParserQueue = parser_queue.Queue;
pub const ParserOwnedActions = parser_owned_actions;
pub const Screen = screen;
pub const ScreenSet = screen_set;
pub const Selection = selection;
pub const Terminal = terminal.Terminal;

test {
    _ = @import("test/action_mapping.zig");
    _ = @import("test/queue_regression.zig");
    _ = @import("test/parser_csi_behavior.zig");
    _ = @import("test/parser_behavior.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/terminal_end_to_end.zig");
    _ = @import("test/terminal_graphics.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
}
