const terminal = @import("../terminal/terminal.zig");

pub const HowlVtTerminal = opaque {};
pub const VtHandle = ?*HowlVtTerminal;

pub fn vtFromHandle(handle: VtHandle) ?*terminal.Terminal {
    const owned = handle orelse return null;
    return @ptrCast(@alignCast(owned));
}
