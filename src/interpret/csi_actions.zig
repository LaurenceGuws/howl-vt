//! Responsibility: route CSI parser events to CSI action-family owners.
//! Ownership: interpret CSI action router.
//! Reason: keep CSI dispatch separate from subfamily meaning.

const action_types = @import("action_types.zig");
const csi_intermediate_actions = @import("csi_intermediate_actions.zig");
const csi_leader_actions = @import("csi_leader_actions.zig");
const csi_plain_actions = @import("csi_plain_actions.zig");
const csi_private_actions = @import("csi_private_actions.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, separators: [16]u8, count: u8, leader: u8, private: bool, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (private) return csi_private_actions.process(final, params, count, leader, intermediates, intermediates_len);
    if (leader != 0) return csi_leader_actions.process(final, params, count, leader);
    if (csi_intermediate_actions.process(final, params, count, intermediates, intermediates_len)) |event| return event;
    return csi_plain_actions.process(final, params, separators, count, intermediates, intermediates_len);
}
