pub const locator = @import("control/locator.zig");
pub const mode = @import("control/mode.zig");
pub const osc_color = @import("control/osc_color.zig");
pub const report = @import("control/report.zig");
pub const ffi = @import("ffi.zig");
pub const screen = @import("screen.zig");
pub const screen_set = @import("screen_set.zig");
pub const input = @import("input.zig");
pub const action = @import("action.zig");
pub const kitty = @import("kitty.zig");
pub const parser = @import("parser.zig");
pub const selection = @import("selection.zig");
pub const terminal = @import("terminal.zig");

test {
    _ = @import("test/action_mapping.zig");
    _ = @import("test/queue_regression.zig");
    _ = @import("test/parser_csi_behavior.zig");
    _ = @import("test/parser_behavior.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/terminal_end_to_end.zig");
    _ = @import("test/terminal_graphics.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
}
