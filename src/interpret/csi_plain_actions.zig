//! Responsibility: map plain CSI final bytes into typed terminal actions.
//! Ownership: interpret plain CSI action mapping.
//! Reason: keep common cursor/edit/report CSI mapping separate from private and intermediate variants.

const action_types = @import("action_types.zig");
const csi_params = @import("csi_params.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, separators: [16]u8, count: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    switch (final) {
        '@' => return SemanticEvent{ .insert_chars = csi_params.paramOrDefault1(params[0]) },
        'A' => return SemanticEvent{ .cursor_up = csi_params.paramOrDefault1(params[0]) },
        'B', 'e' => return SemanticEvent{ .cursor_down = csi_params.paramOrDefault1(params[0]) },
        'C', 'a' => return SemanticEvent{ .cursor_forward = csi_params.paramOrDefault1(params[0]) },
        'b' => return SemanticEvent{ .repeat_preceding = csi_params.paramOrDefault1(params[0]) },
        'D' => return SemanticEvent{ .cursor_back = csi_params.paramOrDefault1(params[0]) },
        'E' => return SemanticEvent{ .cursor_next_line = csi_params.paramOrDefault1(params[0]) },
        'F' => return SemanticEvent{ .cursor_prev_line = csi_params.paramOrDefault1(params[0]) },
        'G', '`' => return SemanticEvent{ .cursor_horizontal_absolute = csi_params.paramOrDefault1(params[0]) - 1 },
        'd' => return SemanticEvent{ .cursor_vertical_absolute = csi_params.paramOrDefault1(params[0]) - 1 },
        'I' => return SemanticEvent{ .horizontal_tab_forward = csi_params.paramOrDefault1(params[0]) },
        'g' => switch (csi_params.paramOrDefault0(params[0])) {
            0 => return SemanticEvent.tab_clear_current,
            3 => return SemanticEvent.tab_clear_all,
            else => return null,
        },
        'Z' => return SemanticEvent{ .horizontal_tab_back = csi_params.paramOrDefault1(params[0]) },
        'L' => return SemanticEvent{ .insert_lines = csi_params.paramOrDefault1(params[0]) },
        'M' => return SemanticEvent{ .delete_lines = csi_params.paramOrDefault1(params[0]) },
        'P' => return SemanticEvent{ .delete_chars = csi_params.paramOrDefault1(params[0]) },
        'S' => return SemanticEvent{ .scroll_up_lines = csi_params.paramOrDefault1(params[0]) },
        'T' => return SemanticEvent{ .scroll_down_lines = csi_params.paramOrDefault1(params[0]) },
        'h' => return SemanticEvent{ .ansi_mode_set = csi_params.collectParams(params, count) },
        'l' => return SemanticEvent{ .ansi_mode_reset = csi_params.collectParams(params, count) },
        'm' => return SemanticEvent{ .sgr = .{ .params = params, .separators = separators, .param_count = count } },
        's' => if (count == 0) return SemanticEvent.save_cursor else return SemanticEvent{ .set_left_right_margins = .{
            .left = csi_params.paramOrDefault1(params[0]) - 1,
            .right = if (count >= 2 and params[1] > 0) csi_params.paramOrDefault1(params[1]) - 1 else null,
        } },
        'u' => return SemanticEvent.restore_cursor,
        'H', 'f' => {
            const row = csi_params.paramOrDefault1(params[0]);
            const col = csi_params.paramOrDefault1(if (count >= 1) params[1] else 0);
            return SemanticEvent{ .cursor_position = .{ .row = row - 1, .col = col - 1 } };
        },
        'r' => return SemanticEvent{ .set_scroll_region = .{
            .top = csi_params.paramOrDefault1(params[0]) - 1,
            .bottom = if (count >= 2 and params[1] > 0) csi_params.paramOrDefault1(params[1]) - 1 else null,
        } },
        'J' => return SemanticEvent{ .erase_display = csi_params.eraseMode(params[0]) },
        'K' => return SemanticEvent{ .erase_line = csi_params.eraseMode(params[0]) },
        'X' => return SemanticEvent{ .erase_chars = csi_params.paramOrDefault1(params[0]) },
        'x' => return SemanticEvent{ .parameters_report = csi_params.paramOrDefault0(params[0]) },
        'n' => switch (csi_params.paramOrDefault0(params[0])) {
            5 => return SemanticEvent.device_status_report,
            6 => return SemanticEvent.cursor_position_report,
            else => return null,
        },
        'c' => return SemanticEvent.primary_device_attributes,
        'p' => {
            if (count == 0 and intermediates_len == 1 and intermediates[0] == '!') {
                return SemanticEvent.reset_screen;
            }
            return null;
        },
        else => return null,
    }
}
