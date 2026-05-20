//! CSI intermediate-byte semantic event mapping.

const events = @import("../../action/vocabulary.zig");
const params_mod = @import("params.zig");

const SemanticEvent = events.SemanticEvent;

pub fn process(final: u8, params: []const i32, intermediates: []const u8) ?SemanticEvent {
    if (intermediates.len == 2 and intermediates[0] == '\'' and intermediates[1] == '*') {
        if (final == '{') return SemanticEvent{ .locator_events = params_mod.collectParams(params) };
        return null;
    }
    if (intermediates.len == 1) {
        switch (intermediates[0]) {
            '"' => {
                if (final == 'q') return switch (params_mod.paramAtOrDefault0(params, 0)) {
                    0, 2 => SemanticEvent{ .character_protection = false },
                    1 => SemanticEvent{ .character_protection = true },
                    else => null,
                };
                if (final == 'v') return SemanticEvent.displayed_extent_report;
                return null;
            },
            '$' => return switch (final) {
                'p' => SemanticEvent{ .ansi_mode_query = params_mod.paramAtOrDefault0(params, 0) },
                'r' => SemanticEvent{ .rect_attrs_change = .{
                    .area = params_mod.rectArea(params, 0),
                    .attrs = params_mod.attrParams(params, 4),
                    .reverse = false,
                } },
                't' => SemanticEvent{ .rect_attrs_change = .{
                    .area = params_mod.rectArea(params, 0),
                    .attrs = params_mod.attrParams(params, 4),
                    .reverse = true,
                } },
                'v' => SemanticEvent{ .rect_copy = .{
                    .area = params_mod.rectArea(params, 0),
                    .source_page = params_mod.paramAtOrDefault1(params, 4),
                    .dest_top = params_mod.paramAtOrDefault1(params, 5) - 1,
                    .dest_left = params_mod.paramAtOrDefault1(params, 6) - 1,
                    .dest_page = params_mod.paramAtOrDefault1(params, 7),
                } },
                'x' => blk: {
                    const ch = params_mod.paramAtOrDefault0(params, 0);
                    if (!params_mod.isValidRectFillChar(ch)) break :blk null;
                    break :blk SemanticEvent{ .rect_fill = .{ .area = params_mod.rectArea(params, 1), .ch = ch } };
                },
                'z' => SemanticEvent{ .rect_erase = params_mod.rectArea(params, 0) },
                '{' => SemanticEvent{ .rect_selective_erase = params_mod.rectArea(params, 0) },
                'w' => SemanticEvent{ .presentation_state_report = params_mod.paramAtOrDefault0(params, 0) },
                else => null,
            },
            '*' => {
                if (final == 'x') return switch (params_mod.paramAtOrDefault0(params, 0)) {
                    0, 1 => SemanticEvent{ .attr_change_extent_rect = false },
                    2 => SemanticEvent{ .attr_change_extent_rect = true },
                    else => null,
                };
                if (final == 'y') return SemanticEvent{ .rect_checksum_request = .{
                    .request_id = params_mod.paramAtOrDefault0(params, 0),
                    .page = params_mod.paramAtOrDefault1(params, 1),
                    .area = params_mod.rectArea(params, 2),
                } };
                return null;
            },
            '+' => return switch (final) {
                'T' => SemanticEvent{ .scroll_down_lines = params_mod.paramAtOrDefault1(params, 0) },
                else => null,
            },
            '#' => return switch (final) {
                'S' => SemanticEvent.xttitlepos,
                'y' => SemanticEvent{ .xtchecksum = params_mod.paramAtOrDefault0(params, 0) },
                'R' => SemanticEvent.xtreportcolors,
                '|' => SemanticEvent{ .selected_graphic_rendition_report = params_mod.rectArea(params, 0) },
                else => null,
            },
            '\'' => return switch (final) {
                'w' => SemanticEvent{ .locator_filter = params_mod.optionalRectArea(params) },
                '}' => SemanticEvent{ .insert_columns = params_mod.paramAtOrDefault1(params, 0) },
                'z' => SemanticEvent{ .locator_reporting = .{ .mode = params_mod.paramAtOrDefault0(params, 0), .unit = params_mod.paramAtOrDefault0(params, 1) } },
                '|' => SemanticEvent{ .locator_request = params_mod.paramAtOrDefault0(params, 0) },
                '~' => SemanticEvent{ .delete_columns = params_mod.paramAtOrDefault1(params, 0) },
                else => null,
            },
            ' ' => return switch (final) {
                'q' => SemanticEvent{ .cursor_style = params_mod.cursorStyle(params_mod.paramAtOrDefault0(params, 0)) },
                '@' => SemanticEvent{ .shift_left_columns = params_mod.paramAtOrDefault1(params, 0) },
                'A' => SemanticEvent{ .shift_right_columns = params_mod.paramAtOrDefault1(params, 0) },
                else => null,
            },
            else => {},
        }
    }
    return null;
}
