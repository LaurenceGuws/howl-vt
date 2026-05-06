//! Responsibility: map CSI intermediate-byte sequences into typed terminal actions.
//! Ownership: interpret CSI intermediate action mapping.
//! Reason: group rectangular, locator, and report CSI variants by syntax owner.

const action_types = @import("action_types.zig");
const csi_params = @import("csi_params.zig");

const SemanticEvent = action_types.SemanticEvent;

pub fn process(final: u8, params: [16]i32, count: u8, intermediates: [4]u8, intermediates_len: u8) ?SemanticEvent {
    if (intermediates_len == 2 and intermediates[0] == '\'' and intermediates[1] == '*') {
        if (final == '{') return SemanticEvent{ .locator_events = csi_params.collectParams(params, count) };
        return null;
    }
    if (intermediates_len == 1) {
        switch (intermediates[0]) {
            '"' => {
                if (final == 'q') return switch (csi_params.paramOrDefault0(params[0])) {
                    0, 2 => SemanticEvent{ .character_protection = false },
                    1 => SemanticEvent{ .character_protection = true },
                    else => null,
                };
                if (final == 'v') return SemanticEvent.displayed_extent_report;
                return null;
            },
            '$' => return switch (final) {
                'p' => SemanticEvent{ .ansi_mode_query = csi_params.paramOrDefault0(params[0]) },
                'r' => SemanticEvent{ .rect_attrs_change = .{
                    .area = csi_params.rectArea(params, count, 0),
                    .attrs = csi_params.attrParams(params, count, 4),
                    .reverse = false,
                } },
                't' => SemanticEvent{ .rect_attrs_change = .{
                    .area = csi_params.rectArea(params, count, 0),
                    .attrs = csi_params.attrParams(params, count, 4),
                    .reverse = true,
                } },
                'v' => SemanticEvent{ .rect_copy = .{
                    .area = csi_params.rectArea(params, count, 0),
                    .source_page = if (count >= 5) csi_params.paramOrDefault1(params[4]) else 1,
                    .dest_top = if (count >= 6) csi_params.paramOrDefault1(params[5]) - 1 else 0,
                    .dest_left = if (count >= 7) csi_params.paramOrDefault1(params[6]) - 1 else 0,
                    .dest_page = if (count >= 8) csi_params.paramOrDefault1(params[7]) else 1,
                } },
                'x' => blk: {
                    const ch = csi_params.paramOrDefault0(params[0]);
                    if (!csi_params.isValidRectFillChar(ch)) break :blk null;
                    break :blk SemanticEvent{ .rect_fill = .{ .area = csi_params.rectArea(params, count, 1), .ch = ch } };
                },
                'z' => SemanticEvent{ .rect_erase = csi_params.rectArea(params, count, 0) },
                '{' => SemanticEvent{ .rect_selective_erase = csi_params.rectArea(params, count, 0) },
                'w' => SemanticEvent{ .presentation_state_report = csi_params.paramOrDefault0(params[0]) },
                else => null,
            },
            '*' => {
                if (final == 'x') return switch (csi_params.paramOrDefault0(params[0])) {
                    0, 1 => SemanticEvent{ .attr_change_extent_rect = false },
                    2 => SemanticEvent{ .attr_change_extent_rect = true },
                    else => null,
                };
                if (final == 'y') return SemanticEvent{ .rect_checksum_request = .{
                    .request_id = csi_params.paramOrDefault0(params[0]),
                    .page = if (count >= 2) csi_params.paramOrDefault1(params[1]) else 1,
                    .area = csi_params.rectArea(params, count, 2),
                } };
                return null;
            },
            '+' => return switch (final) {
                'T' => SemanticEvent{ .scroll_down_lines = csi_params.paramOrDefault1(params[0]) },
                else => null,
            },
            '#' => return switch (final) {
                'S' => SemanticEvent.xttitlepos,
                'y' => SemanticEvent{ .xtchecksum = csi_params.paramOrDefault0(params[0]) },
                'R' => SemanticEvent.xtreportcolors,
                '|' => SemanticEvent{ .selected_graphic_rendition_report = csi_params.rectArea(params, count, 0) },
                else => null,
            },
            '\'' => return switch (final) {
                'w' => SemanticEvent{ .locator_filter = csi_params.optionalRectArea(params, count) },
                '}' => SemanticEvent{ .insert_columns = csi_params.paramOrDefault1(params[0]) },
                'z' => SemanticEvent{ .locator_reporting = .{ .mode = csi_params.paramOrDefault0(params[0]), .unit = csi_params.paramOrDefault0(if (count >= 2) params[1] else 0) } },
                '|' => SemanticEvent{ .locator_request = csi_params.paramOrDefault0(params[0]) },
                '~' => SemanticEvent{ .delete_columns = csi_params.paramOrDefault1(params[0]) },
                else => null,
            },
            ' ' => return switch (final) {
                'q' => SemanticEvent{ .cursor_style = csi_params.cursorStyle(csi_params.paramOrDefault0(params[0])) },
                '@' => SemanticEvent{ .shift_left_columns = csi_params.paramOrDefault1(params[0]) },
                'A' => SemanticEvent{ .shift_right_columns = csi_params.paramOrDefault1(params[0]) },
                else => null,
            },
            else => {},
        }
    }
    return null;
}
