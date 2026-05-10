//! APC semantic event mapping.

const events = @import("../event.zig");
const kitty = @import("kitty.zig");

const SemanticEvent = events.SemanticEvent;

pub fn process(data: []const u8) ?SemanticEvent {
    if (kitty.parseGraphics(data)) |cmd| return SemanticEvent{ .kitty_graphics = cmd };
    return null;
}
