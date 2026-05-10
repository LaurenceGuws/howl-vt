//! Scrollback preservation regression tests.

const std = @import("std");
const scrollback = @import("fuzz_scrollback");

test "scrollback regression: deterministic seeded churn" {
    const seed: u64 = 0x6f686f776c5f7363;
    const a = try scrollback.runScenario(std.testing.allocator, seed, 1_500);
    const b = try scrollback.runScenario(std.testing.allocator, seed, 1_500);

    try std.testing.expectEqual(a.structural_hash, b.structural_hash);
    try std.testing.expectEqual(a.logical_hash, b.logical_hash);
    try std.testing.expectEqual(a.history_count, b.history_count);
    try std.testing.expectEqual(a.rows, b.rows);
    try std.testing.expectEqual(a.cols, b.cols);
}

test "scrollback regression: high-churn invariants hold" {
    const seeds = [_]u64{
        0x1111111111111111,
        0x2222222222222222,
        0x3333333333333333,
        0x4444444444444444,
        0x5555555555555555,
    };

    for (seeds) |seed| {
        _ = try scrollback.runScenario(std.testing.allocator, seed, 2_000);
    }
}

test "scrollback regression: resize and zoom churn preserve canonical logical content" {
    try scrollback.runCanonicalPreservation(std.testing.allocator, 0x7a6964655f726566, .{});
}
