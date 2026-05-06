//! Responsibility: map ESC final bytes to action names.
//! Ownership: ESC action mapping helpers.
//! Reason: keep simple ESC final dispatch separate from the top-level action router.

pub const EscAction = union(enum) {
    line_feed,
    next_line,
    reverse_index,
    primary_device_attributes,
    horizontal_tab_set,
    reset_screen,
    save_cursor,
    restore_cursor,
    application_keypad: bool,
};

const action_types = @import("action_types.zig");
const SemanticEvent = action_types.SemanticEvent;

pub fn action(final: u8) ?EscAction {
    return switch (final) {
        'D' => .line_feed,
        'E' => .next_line,
        'M' => .reverse_index,
        'Z' => .primary_device_attributes,
        'H' => .horizontal_tab_set,
        'c' => .reset_screen,
        '7' => .save_cursor,
        '8' => .restore_cursor,
        '=' => EscAction{ .application_keypad = true },
        '>' => EscAction{ .application_keypad = false },
        else => null,
    };
}

pub fn process(final: u8) ?SemanticEvent {
    switch (final) {
        0x17 => return SemanticEvent{ .legacy_control = .tek_copy },
        0x1C => return SemanticEvent{ .legacy_control = .tek_special_point_plot },
        'l' => return SemanticEvent{ .legacy_control = .hp_memory_lock },
        's' => return SemanticEvent{ .legacy_control = .tek_write_thru_short_dashed },
        else => {},
    }
    const mapped = action(final) orelse return null;
    return switch (mapped) {
        .line_feed => SemanticEvent.line_feed,
        .next_line => SemanticEvent.next_line,
        .reverse_index => SemanticEvent.reverse_index,
        .primary_device_attributes => SemanticEvent.primary_device_attributes,
        .horizontal_tab_set => SemanticEvent.horizontal_tab_set,
        .reset_screen => SemanticEvent.reset_screen,
        .save_cursor => SemanticEvent.save_cursor,
        .restore_cursor => SemanticEvent.restore_cursor,
        .application_keypad => |enabled| SemanticEvent{ .application_keypad = enabled },
    };
}
