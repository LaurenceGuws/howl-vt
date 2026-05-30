const std = @import("std");

pub const C0Action = enum {
    line_feed,
    carriage_return,
    backspace,
    horizontal_tab,
};

pub const C0 = enum(u8) {
    backspace = 0x08,
    horizontal_tab = 0x09,
    line_feed = 0x0A,
    vertical_tab = 0x0B,
    form_feed = 0x0C,
    carriage_return = 0x0D,
    file_separator = 0x1C,
    group_separator = 0x1D,
    record_separator = 0x1E,
    unit_separator = 0x1F,
    _,
};

const events = @import("../action/vocabulary.zig");
const SemanticEvent = events.SemanticEvent;

pub fn fromByte(byte: u8) C0 {
    return @enumFromInt(byte);
}

pub fn action(control: C0) ?C0Action {
    return switch (control) {
        .line_feed, .vertical_tab, .form_feed => .line_feed,
        .carriage_return => .carriage_return,
        .backspace => .backspace,
        .horizontal_tab => .horizontal_tab,
        else => null,
    };
}

pub fn process(control: C0) ?SemanticEvent {
    switch (control) {
        .file_separator => return SemanticEvent{ .legacy_control = .tek_point_plot },
        .group_separator => return SemanticEvent{ .legacy_control = .tek_graph },
        .record_separator => return SemanticEvent{ .legacy_control = .tek_incremental_plot },
        .unit_separator => return SemanticEvent{ .legacy_control = .tek_alpha },
        else => {},
    }
    const mapped = action(control) orelse return null;
    return switch (mapped) {
        .line_feed => SemanticEvent.line_feed,
        .carriage_return => SemanticEvent.carriage_return,
        .backspace => SemanticEvent.backspace,
        .horizontal_tab => SemanticEvent.horizontal_tab,
    };
}

test "c0 handled controls keep protocol values" {
    try std.testing.expectEqual(@as(u8, 0x08), @intFromEnum(C0.backspace));
    try std.testing.expectEqual(@as(u8, 0x09), @intFromEnum(C0.horizontal_tab));
    try std.testing.expectEqual(@as(u8, 0x0A), @intFromEnum(C0.line_feed));
    try std.testing.expectEqual(@as(u8, 0x0B), @intFromEnum(C0.vertical_tab));
    try std.testing.expectEqual(@as(u8, 0x0C), @intFromEnum(C0.form_feed));
    try std.testing.expectEqual(@as(u8, 0x0D), @intFromEnum(C0.carriage_return));
}
