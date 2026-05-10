//! Responsibility: export terminal control-plane protocol owners.
//! Ownership: vt-core control package boundary.
//! Reason: keep mode, report, locator, and OSC color owners out of the root facade.

pub const Locator = @import("locator.zig");
pub const Mode = @import("mode.zig");
pub const OscColor = @import("osc_color.zig");
pub const Report = @import("report.zig");
