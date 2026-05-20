//! CSI semantic event routing.

const events = @import("../action/vocabulary.zig");
const intermediate = @import("csi/intermediate.zig");
const leader = @import("csi/leader.zig");
const plain = @import("csi/plain.zig");
const private = @import("csi/private.zig");

const SemanticEvent = events.SemanticEvent;
const CsiSeparatorList = events.CsiSeparatorList;

pub fn process(final: u8, params: []const i32, separators: CsiSeparatorList, leader_byte: u8, is_private: bool, intermediates: []const u8) ?SemanticEvent {
    if (is_private) return private.process(final, params, leader_byte, intermediates);
    if (leader_byte != 0) return leader.process(final, params, leader_byte, intermediates);
    if (intermediate.process(final, params, intermediates)) |event| return event;
    return plain.process(final, params, separators, intermediates);
}
