//! Exercises hostile bytes and lifecycle operations through the native embedding root.

const std = @import("std");
const howl_vt = @import("howl_vt");

const rows_max: u16 = 32;
const cols_max: u16 = 96;
const history_max: u16 = 128;
const operations_max: u8 = 32;
const feed_max: usize = 256;

const Operation = enum {
    feed,
    resize,
    reject_zero_resize,
    reset_and_reuse,
    inspect,
};

test "native Terminal hostile input and lifecycle" {
    try std.testing.fuzz({}, fuzzTerminal, .{});
}

fn fuzzTerminal(_: void, smith: *std.testing.Smith) !void {
    const initial_rows = smith.valueRangeAtMost(u16, 1, rows_max);
    const initial_cols = smith.valueRangeAtMost(u16, 1, cols_max);
    const history_capacity = smith.valueRangeAtMost(u16, 0, history_max);
    var terminal = try howl_vt.Terminal.initWithHistory(
        std.testing.allocator,
        initial_rows,
        initial_cols,
        history_capacity,
    );
    defer terminal.deinit();

    try assertPublicInvariants(&terminal, history_capacity);

    var operation_count: u8 = 0;
    while (operation_count < operations_max and !smith.eosWeightedSimple(7, 1)) : (operation_count += 1) {
        switch (smith.value(Operation)) {
            .feed => {
                var bytes: [feed_max]u8 = undefined;
                const len = smith.slice(&bytes);
                try feedHostile(&terminal, bytes[0..len]);
            },
            .resize => {
                const rows = smith.valueRangeAtMost(u16, 1, rows_max);
                const cols = smith.valueRangeAtMost(u16, 1, cols_max);
                try terminal.resize(rows, cols);
            },
            .reject_zero_resize => {
                const before = terminal.visibleMeta();
                if (smith.value(bool)) {
                    try std.testing.expectError(error.InvalidDimensions, terminal.resize(0, before.cols));
                } else {
                    try std.testing.expectError(error.InvalidDimensions, terminal.resize(before.rows, 0));
                }
                const after = terminal.visibleMeta();
                try std.testing.expectEqual(before.rows, after.rows);
                try std.testing.expectEqual(before.cols, after.cols);
                try std.testing.expectEqual(before.history_count, after.history_count);
                try std.testing.expectEqual(before.is_alternate_screen, after.is_alternate_screen);
                _ = try terminal.feed("R");
            },
            .reset_and_reuse => {
                terminal.resetScreen();
                _ = try terminal.feed("R");
            },
            .inspect => {},
        }
        try assertPublicInvariants(&terminal, history_capacity);
    }
}

fn feedHostile(terminal: *howl_vt.Terminal, bytes: []const u8) !void {
    _ = terminal.feed(bytes) catch |err| switch (err) {
        error.ConsequenceLimit,
        error.ParsedEventLimit,
        error.StringControlLimit,
        => {
            _ = try terminal.feed("R");
            return;
        },
        error.OutOfMemory => return err,
    };
}

fn assertPublicInvariants(terminal: *howl_vt.Terminal, history_capacity: u16) !void {
    const publication = terminal.surfaceSnapshot();
    const view = publication.snapshot.view;
    try std.testing.expect(view.rows > 0);
    try std.testing.expect(view.cols > 0);
    try std.testing.expect(view.cursor_row < view.rows);
    try std.testing.expect(view.cursor_col < view.cols);
    try std.testing.expect(view.history_count <= history_capacity);
    if (view.is_alternate_screen) try std.testing.expectEqual(@as(u32, 0), view.history_count);
    try std.testing.expect(publication.snapshot_seq != 0);

    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            _ = view.cellInfoAt(row, col);
        }
    }
    try std.testing.expect(terminal.ackSurface(publication.snapshot_seq));
}
