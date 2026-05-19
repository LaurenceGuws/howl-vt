//! CSI semantic event routing.

const events = @import("../action/vocabulary.zig");
const parser_mod = @import("../parser.zig");
const intermediate = @import("csi/intermediate.zig");
const leader = @import("csi/leader.zig");
const plain = @import("csi/plain.zig");
const private = @import("csi/private.zig");

const SemanticEvent = events.SemanticEvent;

pub fn process(final: u8, params: [parser_mod.max_params]i32, separators: [parser_mod.max_params]u8, count: u8, leader_byte: u8, is_private: bool, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (is_private) return private.process(final, params, count, leader_byte, intermediates, intermediates_len);
    if (leader_byte != 0) return leader.process(final, params, count, leader_byte, intermediates, intermediates_len);
    if (intermediate.process(final, params, count, intermediates, intermediates_len)) |event| return event;
    return plain.process(final, params, separators, count, intermediates, intermediates_len);
}
