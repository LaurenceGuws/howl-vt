test {
    _ = @import("unit/terminal_test.zig");
    _ = @import("unit/terminal_modes_test.zig");
    _ = @import("unit/terminal_osc_test.zig");
    _ = @import("unit/terminal_surface_test.zig");
    _ = @import("unit/screen_test.zig");
    _ = @import("unit/route_test.zig");
    _ = @import("unit/terminal_snapshot_test.zig");
    _ = @import("unit/terminal_end_to_end_test.zig");
    _ = @import("unit/screen/cursor_test.zig");
    _ = @import("unit/screen/history_test.zig");
    _ = @import("unit/screen/resize_test.zig");
    _ = @import("unit/screen/tabs_test.zig");
    _ = @import("unit/screen/write_test.zig");
    _ = @import("unit/report_test.zig");
    _ = @import("unit/parser/csi_test.zig");
    _ = @import("unit/parser/events_test.zig");
    _ = @import("unit/parser/main_test.zig");
    _ = @import("unit/parser/string_control_test.zig");
    _ = @import("unit/csi_mapping_test.zig");
}
