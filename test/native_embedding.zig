//! Verifies the curated native embedding root without repository-local imports.

const std = @import("std");
const howl_vt = @import("howl_vt");

test "native root owns feed snapshot acknowledgement resize and cleanup" {
    var terminal = try howl_vt.Terminal.initWithCells(std.testing.allocator, 2, 8);
    defer terminal.deinit();

    const feed = try terminal.feed("A\x1b[31mB");
    try std.testing.expect(feed.state_changed);

    const publication = terminal.surfaceSnapshot();
    try std.testing.expectEqual(@as(u16, 2), publication.snapshot.view.rows);
    try std.testing.expectEqual(@as(u16, 8), publication.snapshot.view.cols);
    try std.testing.expectEqual(@as(u21, 'A'), publication.snapshot.view.cellAt(0, 0));
    try std.testing.expectEqual(@as(u21, 'B'), publication.snapshot.view.cellAt(0, 1));
    try std.testing.expect(terminal.ackSurface(publication.snapshot_seq));

    try terminal.resize(3, 10);
    const resized = terminal.surfaceSnapshot().snapshot.view;
    try std.testing.expectEqual(@as(u16, 3), resized.rows);
    try std.testing.expectEqual(@as(u16, 10), resized.cols);
}
