const std = @import("std");
const host_state = @import("../host_state.zig");

pub const Shape = enum {
    alias,
    cell,
    copy,
    crosshair,
    default,
    e_resize,
    ew_resize,
    grab,
    grabbing,
    help,
    move,
    n_resize,
    ne_resize,
    nesw_resize,
    no_drop,
    not_allowed,
    ns_resize,
    nw_resize,
    nwse_resize,
    pointer,
    progress,
    s_resize,
    se_resize,
    sw_resize,
    text,
    vertical_text,
    w_resize,
    wait,
    zoom_in,
    zoom_out,
};

pub const Stack = struct {
    stack: [16]Shape = undefined,
    len: u8 = 0,

    pub fn currentName(self: *const Stack) []const u8 {
        if (self.len == 0) return "0";
        return shapeName(self.stack[self.len - 1]);
    }

    pub fn set(self: *Stack, names: []const u8) void {
        self.len = 0;
        const shape = firstShape(names) orelse return;
        self.stack[0] = shape;
        self.len = 1;
    }

    pub fn push(self: *Stack, names: []const u8) void {
        var parts = std.mem.splitScalar(u8, names, ',');
        while (parts.next()) |name| {
            const shape = parseShapeName(name) orelse continue;
            if (self.len == self.stack.len) {
                std.mem.copyForwards(Shape, self.stack[0 .. self.stack.len - 1], self.stack[1..self.stack.len]);
                self.len -= 1;
            }
            self.stack[self.len] = shape;
            self.len += 1;
        }
    }

    pub fn pop(self: *Stack) void {
        if (self.len > 0) self.len -= 1;
    }

    pub fn appendQuery(self: *const Stack, allocator: std.mem.Allocator, output: *std.ArrayList(u8), names: []const u8) host_state.ApplyError!void {
        const start = host_state.byteCount(output.items);
        errdefer host_state.restorePendingOutput(output, start);
        try host_state.appendOutput(output, allocator, "\x1b]22;");
        var first = true;
        var parts = std.mem.splitScalar(u8, names, ',');
        while (parts.next()) |name| {
            if (!first) try host_state.appendOutput(output, allocator, ",");
            first = false;
            if (std.mem.eql(u8, name, "__current__")) {
                try host_state.appendOutput(output, allocator, self.currentName());
            } else if (std.mem.eql(u8, name, "__default__") or std.mem.eql(u8, name, "__grabbed__")) {
                try host_state.appendOutput(output, allocator, "default");
            } else {
                try host_state.appendOutput(output, allocator, if (parseShapeName(name) != null) "1" else "0");
            }
        }
        try host_state.appendOutput(output, allocator, "\x1b\\");
    }
};

fn firstShape(names: []const u8) ?Shape {
    var parts = std.mem.splitScalar(u8, names, ',');
    while (parts.next()) |name| {
        if (parseShapeName(name)) |shape| return shape;
    }
    return null;
}

fn parseShapeName(name: []const u8) ?Shape {
    if (std.mem.eql(u8, name, "alias")) return .alias;
    if (std.mem.eql(u8, name, "cell")) return .cell;
    if (std.mem.eql(u8, name, "copy")) return .copy;
    if (std.mem.eql(u8, name, "crosshair")) return .crosshair;
    if (std.mem.eql(u8, name, "default")) return .default;
    if (std.mem.eql(u8, name, "e-resize")) return .e_resize;
    if (std.mem.eql(u8, name, "ew-resize")) return .ew_resize;
    if (std.mem.eql(u8, name, "grab")) return .grab;
    if (std.mem.eql(u8, name, "grabbing")) return .grabbing;
    if (std.mem.eql(u8, name, "help")) return .help;
    if (std.mem.eql(u8, name, "move")) return .move;
    if (std.mem.eql(u8, name, "n-resize")) return .n_resize;
    if (std.mem.eql(u8, name, "ne-resize")) return .ne_resize;
    if (std.mem.eql(u8, name, "nesw-resize")) return .nesw_resize;
    if (std.mem.eql(u8, name, "no-drop")) return .no_drop;
    if (std.mem.eql(u8, name, "not-allowed")) return .not_allowed;
    if (std.mem.eql(u8, name, "ns-resize")) return .ns_resize;
    if (std.mem.eql(u8, name, "nw-resize")) return .nw_resize;
    if (std.mem.eql(u8, name, "nwse-resize")) return .nwse_resize;
    if (std.mem.eql(u8, name, "pointer")) return .pointer;
    if (std.mem.eql(u8, name, "progress")) return .progress;
    if (std.mem.eql(u8, name, "s-resize")) return .s_resize;
    if (std.mem.eql(u8, name, "se-resize")) return .se_resize;
    if (std.mem.eql(u8, name, "sw-resize")) return .sw_resize;
    if (std.mem.eql(u8, name, "text")) return .text;
    if (std.mem.eql(u8, name, "vertical-text")) return .vertical_text;
    if (std.mem.eql(u8, name, "w-resize")) return .w_resize;
    if (std.mem.eql(u8, name, "wait")) return .wait;
    if (std.mem.eql(u8, name, "zoom-in")) return .zoom_in;
    if (std.mem.eql(u8, name, "zoom-out")) return .zoom_out;
    return null;
}

fn shapeName(shape: Shape) []const u8 {
    return switch (shape) {
        .alias => "alias",
        .cell => "cell",
        .copy => "copy",
        .crosshair => "crosshair",
        .default => "default",
        .e_resize => "e-resize",
        .ew_resize => "ew-resize",
        .grab => "grab",
        .grabbing => "grabbing",
        .help => "help",
        .move => "move",
        .n_resize => "n-resize",
        .ne_resize => "ne-resize",
        .nesw_resize => "nesw-resize",
        .no_drop => "no-drop",
        .not_allowed => "not-allowed",
        .ns_resize => "ns-resize",
        .nw_resize => "nw-resize",
        .nwse_resize => "nwse-resize",
        .pointer => "pointer",
        .progress => "progress",
        .s_resize => "s-resize",
        .se_resize => "se-resize",
        .sw_resize => "sw-resize",
        .text => "text",
        .vertical_text => "vertical-text",
        .w_resize => "w-resize",
        .wait => "wait",
        .zoom_in => "zoom-in",
        .zoom_out => "zoom-out",
    };
}
