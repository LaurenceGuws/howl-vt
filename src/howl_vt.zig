const action_route = @import("action/route.zig");
const action_vocabulary = @import("action/vocabulary.zig");
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
    _ = action_route;
    _ = action_vocabulary;
    _ = input_encode;
    _ = input_encoded;
    _ = input_event;
    _ = input_keyboard;
    _ = input_mouse;
    _ = input_tokens;
    _ = parser;
    _ = parser_owned_actions;
    _ = screen;
    _ = @import("screen/cursor_test.zig");
    _ = @import("screen/history_test.zig");
    _ = @import("screen/resize_test.zig");
    _ = @import("screen/tabs_test.zig");
    _ = @import("screen/write_test.zig");
    _ = @import("control/report_test.zig");
    _ = screen_set;
    _ = selection;
    _ = terminal;
    _ = @import("parser/csi_test.zig");
    _ = @import("parser/main_test.zig");
    _ = @import("parser/string_control_test.zig");
    _ = @import("xterm/csi_mapping_test.zig");
}
