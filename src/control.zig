//! Responsibility: export terminal control-plane protocol owners.
//! Ownership: vt-core control package boundary.
//! Reason: keep mode, report, locator, and OSC color owners out of the root facade.

pub const Locator = @import("control/locator.zig");
pub const Mode = @import("control/mode.zig");
pub const OscColor = @import("control/osc_color.zig");
pub const Report = @import("control/report.zig");
