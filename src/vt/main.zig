//! VT namespace wrapper for the howl-vt-core module.

const std = @import("std");

pub const c_api = @import("../ffi.zig");

const terminal = @import("../terminal.zig");

pub const Input = @import("../input.zig");
pub const Grid = @import("../grid.zig").Grid;
pub const Parser = @import("../parser.zig").Parser;
pub const Snapshot = @import("../snapshot.zig");
pub const Selection = @import("../selection.zig");
pub const VtCore = terminal.VtCore;

test {
    _ = terminal;
    std.testing.refAllDecls(@This());
}
