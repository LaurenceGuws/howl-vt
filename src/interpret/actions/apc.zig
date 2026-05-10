//! Responsibility: map APC parsed events into typed terminal actions.
//! Ownership: interpret APC action mapping.
//! Reason: keep APC string-protocol meaning separate from the top-level action router.

const event_mod = @import("../event.zig");
const kitty = @import("kitty.zig");

const SemanticEvent = event_mod.SemanticEvent;

pub fn process(data: []const u8) ?SemanticEvent {
    if (kitty.parseGraphics(data)) |cmd| return SemanticEvent{ .kitty_graphics = cmd };
    return null;
}
