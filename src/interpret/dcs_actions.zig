//! Responsibility: parse DCS action payloads.
//! Ownership: DCS action mapping helpers.
//! Reason: keep DCS transport consequences separate from the top-level action router.

pub fn requestStatusPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '$' and data[1] == 'q') return data[2..];
    return null;
}

pub fn requestTermcapPayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '+' and data[1] == 'q') return data[2..];
    return null;
}

pub fn requestResourcePayload(data: []const u8) ?[]const u8 {
    if (data.len >= 2 and data[0] == '+' and data[1] == 'Q') return data[2..];
    return null;
}

const action_types = @import("action_types.zig");
const SemanticEvent = action_types.SemanticEvent;

pub fn process(data: []const u8) ?SemanticEvent {
    if (requestStatusPayload(data)) |payload| return SemanticEvent{ .dcs_request_status = payload };
    if (requestTermcapPayload(data)) |payload| return SemanticEvent{ .dcs_request_termcap = payload };
    if (requestResourcePayload(data)) |payload| return SemanticEvent{ .dcs_request_resource = payload };
    if (data.len >= 2 and data[0] == '+' and data[1] == 'p') return SemanticEvent{ .dcs_payload = .{ .kind = .xtsettcap, .payload = data[2..] } };
    if (contains(data, "$t")) return SemanticEvent{ .dcs_payload = .{ .kind = .decrsps, .payload = data } };
    if (contains(data, "|")) return SemanticEvent{ .dcs_payload = .{ .kind = .decudk, .payload = data } };
    if (contains(data, "!u")) return SemanticEvent{ .dcs_payload = .{ .kind = .decaupss, .payload = data } };
    if (contains(data, "q")) return SemanticEvent{ .dcs_payload = .{ .kind = .sixel, .payload = data } };
    if (contains(data, "p")) return SemanticEvent{ .dcs_payload = .{ .kind = .regis, .payload = data } };
    return null;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    return @import("std").mem.indexOf(u8, haystack, needle) != null;
}
