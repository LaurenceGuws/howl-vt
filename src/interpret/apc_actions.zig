//! Responsibility: map APC parser events into typed terminal actions.
//! Ownership: interpret APC action mapping.
//! Reason: keep APC string-protocol meaning separate from the top-level action router.

const action_types = @import("action_types.zig");
const kitty_actions = @import("kitty_actions.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(data: []const u8) ?SemanticEvent {
    if (kitty_actions.parseGraphics(data)) |cmd| return SemanticEvent{ .kitty_graphics = cmd };
    return null;
}
