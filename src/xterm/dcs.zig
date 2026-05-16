//! DCS semantic event mapping.

const parsed_events = @import("../parser/events.zig");

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

const events = @import("../action/vocabulary.zig");
const SemanticEvent = events.SemanticEvent;
const DcsEvent = @FieldType(parsed_events.Event, "dcs");

pub fn process(dcs: DcsEvent) ?SemanticEvent {
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 'q') return SemanticEvent{ .dcs_request_status = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'q') return SemanticEvent{ .dcs_request_termcap = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'Q') return SemanticEvent{ .dcs_request_resource = dcs.payload };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '+' and dcs.final == 'p') return SemanticEvent{ .dcs_payload = .{ .kind = .xtsettcap, .payload = dcs.payload } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '$' and dcs.final == 't') return SemanticEvent{ .dcs_payload = .{ .kind = .decrsps, .payload = dcs.body } };
    if (dcs.final == '|') return SemanticEvent{ .dcs_payload = .{ .kind = .decudk, .payload = dcs.body } };
    if (dcs.intermediates_len == 1 and dcs.intermediates[0] == '!' and dcs.final == 'u') return SemanticEvent{ .dcs_payload = .{ .kind = .decaupss, .payload = dcs.body } };
    if (dcs.final == 'q') return SemanticEvent{ .dcs_payload = .{ .kind = .sixel, .payload = dcs.body } };
    if (dcs.final == 'p') return SemanticEvent{ .dcs_payload = .{ .kind = .regis, .payload = dcs.body } };
    return null;
}
