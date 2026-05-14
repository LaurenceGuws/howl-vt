
test {
    _ = @import("test/action_mapping.zig");
    _ = @import("test/apply_flow_regression.zig");
    _ = @import("test/screen_state_behavior.zig");
    _ = @import("test/snapshot_regression.zig");
    _ = @import("test/terminal_end_to_end.zig");
    _ = @import("test/terminal_graphics.zig");
    _ = @import("test/terminal_modes_reports.zig");
    _ = @import("test/terminal_osc_colors.zig");
    _ = @import("test/terminal_surface.zig");
}
