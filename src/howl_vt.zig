const action = @import("action.zig");
const ffi = @import("ffi.zig");
const input_encode = @import("input/encode.zig");
const input_encoded = @import("input/encoded.zig");
const input_event = @import("input/event.zig");
const input_keyboard = @import("input/keyboard.zig");
const input_mouse = @import("input/mouse.zig");
const input_tokens = @import("input/tokens.zig");
const parser = @import("parser/main.zig");
const parser_owned_actions = @import("parser/owned_actions.zig");
const screen = @import("screen.zig");
const screen_set = @import("screen_set.zig");
const selection = @import("selection.zig");
const terminal = @import("terminal.zig");

pub const Parser = parser;
pub const ParserOwnedActions = parser_owned_actions;
pub const ScreenSet = screen_set;
pub const Terminal = terminal.Terminal;

test {
    _ = action;
    _ = ffi;
    _ = input_encode;
    _ = input_encoded;
    _ = input_event;
    _ = input_keyboard;
    _ = input_mouse;
    _ = input_tokens;
    _ = parser;
    _ = parser_owned_actions;
    _ = screen;
    _ = screen_set;
    _ = selection;
    _ = terminal;
    _ = @import("test/action_mapping.zig");
    _ = @import("test/parser_csi_behavior.zig");
    _ = @import("test/parser_behavior.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/terminal_end_to_end.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
}
