const action_route = @import("route.zig");
const action_vocabulary = @import("vocabulary.zig");
const input_encode = @import("input/encode.zig");
const input_encoded = @import("input/encoded.zig");
const input_event = @import("input/event.zig");
const input_keyboard = @import("input/keyboard.zig");
const input_mouse = @import("input/mouse.zig");
const parser_mod = @import("parser/main.zig");
const parser_owned_actions = @import("parser/owned_actions.zig");
const screen_set = @import("screen_set.zig");
const terminal_mod = @import("terminal.zig");

pub const Parser = parser_mod;
pub const ParserOwnedActions = parser_owned_actions;
pub const ScreenSet = screen_set;
pub const Terminal = terminal_mod.Terminal;

test {
    _ = action_route;
    _ = action_vocabulary;
    _ = input_encode;
    _ = input_encoded;
    _ = input_event;
    _ = input_keyboard;
    _ = input_mouse;
    _ = parser_mod;
    _ = parser_owned_actions;
    _ = screen_set;
    _ = terminal_mod;
}
