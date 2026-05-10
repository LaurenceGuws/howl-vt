//! Responsibility: map APC parsed events into typed terminal actions.
//! Ownership: interpret APC action mapping.
//! Reason: keep APC string-protocol meaning separate from the top-level action router.

const types = @import("types.zig");
const kitty = @import("kitty.zig");

const SemanticEvent = types.SemanticEvent;

pub fn process(data: []const u8) ?SemanticEvent {
    if (kitty.parseGraphics(data)) |cmd| return SemanticEvent{ .kitty_graphics = cmd };
    return null;
}
