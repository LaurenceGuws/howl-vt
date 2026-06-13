const action_route = @import("route.zig");
const action_vocabulary = @import("vocabulary.zig");
const input_encode = @import("input/encode.zig");
const input_encoded = @import("input/encoded.zig");
const input_event = @import("input/event.zig");
const input_keyboard = @import("input/keyboard.zig");
const input_mouse = @import("input/mouse.zig");
const terminal_core = @import("terminal/main.zig");

pub const Parser = terminal_core.Parser;
pub const ParserOwnedActions = terminal_core.ParserOwnedActions;
pub const ScreenSet = terminal_core.ScreenSet;
pub const Terminal = terminal_core.Terminal;

test {
    _ = action_route;
    _ = action_vocabulary;
    _ = input_encode;
    _ = input_encoded;
    _ = input_event;
    _ = input_keyboard;
    _ = input_mouse;
    _ = terminal_core;
}
