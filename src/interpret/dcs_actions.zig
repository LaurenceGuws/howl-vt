//! Responsibility: parse DCS action payloads.
//! Ownership: DCS action mapping helpers.
//! Reason: keep DCS transport consequences separate from the top-level action router.

pub fn requestStatusPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '$' and data[1] == 'q') return data[2..];
    return null;
}

const action_types = @import("action_types.zig");
const SemanticEvent = action_types.SemanticEvent;

pub fn process(data: []const u8) ?SemanticEvent {
    if (requestStatusPayload(data)) |payload| return SemanticEvent{ .dcs_request_status = payload };
    return null;
}
