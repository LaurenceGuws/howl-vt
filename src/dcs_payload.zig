pub const DcsPayloadKind = enum {
    xtsettcap,
    decrsps,
    decudk,
    decaupss,
};

pub const DcsPayload = struct {
    kind: DcsPayloadKind,
    payload: []const u8,
};
