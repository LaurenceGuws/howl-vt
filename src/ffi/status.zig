pub const HowlVtCallStatus = enum(c_int) {
    ok = 0,
    missing_handle = -1,
    invalid_argument = -2,
    failed = -3,
    short_buffer = -4,
    limit_reached = -5,
};
