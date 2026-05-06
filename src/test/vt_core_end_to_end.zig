//! Responsibility: end-to-end vt-core flow coverage across module boundaries.
//! Ownership: vt-core end-to-end tests.
//! Reason: keep host-facing byte-to-screen flows explicit and deterministic.

const std = @import("std");
const vt = @import("vt_core");

test "vt-core: parser apply flow applies bytes to grid state deterministically" {
    const allocator = std.testing.allocator;
    var vt_core = try vt.VtCore.initWithCells(allocator, 3, 8);
    defer vt_core.deinit();

    vt_core.feedSlice("ab");
    vt_core.feedByte('c');
    vt_core.feedSlice("\r\nxy");
    vt_core.apply();

    const s = vt_core.screen();
    try std.testing.expectEqual(@as(u21, 'a'), s.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'b'), s.cellAt(0, 1));
    try std.testing.expectEqual(@as(u21, 'c'), s.cellAt(0, 2));
    try std.testing.expectEqual(@as(u21, 'x'), s.cellAt(1, 0));
    try std.testing.expectEqual(@as(u21, 'y'), s.cellAt(1, 1));
    try std.testing.expectEqual(@as(u16, 1), s.cursor_row);
    try std.testing.expectEqual(@as(u16, 2), s.cursor_col);
}
