//! C0 semantic mapping.

pub const C0Action = enum {
    line_feed,
    carriage_return,
    backspace,
    horizontal_tab,
};

const events = @import("../action/vocabulary.zig");
const SemanticEvent = events.SemanticEvent;

pub fn action(control: u8) ?C0Action {
    return switch (control) {
        0x0A, 0x0B, 0x0C => .line_feed,
        0x0D => .carriage_return,
        0x08 => .backspace,
        0x09 => .horizontal_tab,
        else => null,
    };
}

pub fn process(control: u8) ?SemanticEvent {
    switch (control) {
        0x1C => return SemanticEvent{ .legacy_control = .tek_point_plot },
        0x1D => return SemanticEvent{ .legacy_control = .tek_graph },
        0x1E => return SemanticEvent{ .legacy_control = .tek_incremental_plot },
        0x1F => return SemanticEvent{ .legacy_control = .tek_alpha },
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
