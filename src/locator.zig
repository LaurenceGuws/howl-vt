//! Responsibility: own the locator protocol state and reply behavior.
//! Ownership: locator protocol domain owner.
//! Reason: keep locator tracking and DECLRP formatting out of the vt-core facade.

const std = @import("std");
const input_mod = @import("input/input.zig");
const interpret_owner = @import("interpret/interpret.zig");

const Input = input_mod;
const Interpret = interpret_owner;

pub const ReportingMode = enum(u2) {
    disabled,
    continuous,
    one_shot,
};

pub const FilterRect = struct {
    top: u16,
    left: u16,
    bottom: u16,
    right: u16,
};

pub const State = struct {
    mode: ReportingMode = .disabled,
    coordinate_unit: u16 = 0,
    report_button_down: bool = false,
    report_button_up: bool = false,
    filter_rect: ?FilterRect = null,
    last_row: ?u16 = null,
    last_col: ?u16 = null,
    last_pixel_x: ?u32 = null,
    last_pixel_y: ?u32 = null,
    last_buttons_down: u8 = 0,
};

pub fn setReporting(state: *State, mode: u16, unit: u16) void {
    state.mode = switch (mode) {
        1 => .continuous,
        2 => .one_shot,
        else => .disabled,
    };
    state.coordinate_unit = unit;
}

pub fn setFilter(state: *State, area: Interpret.SemanticEvent.OptionalRectArea) void {
    const row = state.last_row orelse 0;
    const col = state.last_col orelse 0;
    const top = area.top orelse row;
    const left = area.left orelse col;
    const bottom = area.bottom orelse row;
    const right = area.right orelse col;
    if (area.top == null and area.left == null and area.bottom == null and area.right == null) {
        state.filter_rect = null;
        return;
    }
    if (top > bottom or left > right) return;
    state.filter_rect = .{ .top = top, .left = left, .bottom = bottom, .right = right };
}

pub fn setEvents(state: *State, modes: []const u16) void {
    for (modes) |mode| switch (mode) {
        0 => {
            state.report_button_down = false;
            state.report_button_up = false;
            state.filter_rect = null;
        },
        1 => state.report_button_down = true,
        2 => state.report_button_down = false,
        3 => state.report_button_up = true,
        4 => state.report_button_up = false,
        else => {},
    };
}

pub fn appendReportForRequest(state: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, param: u16) void {
    if (param > 1) return;
    if (state.mode == .disabled or state.last_row == null or state.last_col == null) {
        output.appendSlice(allocator, "\x1b[0&w") catch {};
        return;
    }
    appendReport(state, allocator, output, encode_buf, 1, state.last_buttons_down, state.last_row.?, state.last_col.?);
}

pub fn appendDeviceStatusReport(allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, param: u16) void {
    const text = switch (param) {
        55 => std.fmt.bufPrint(encode_buf, "\x1b[?50n", .{}) catch return,
        56 => std.fmt.bufPrint(encode_buf, "\x1b[?57;1n", .{}) catch return,
        else => return,
    };
    output.appendSlice(allocator, text) catch {};
}

pub fn handleMouseEvent(state: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, event: Input.MouseEvent) void {
    if (event.row < 0) return;
    const row: u16 = @intCast(event.row);
    const col = event.col;
    state.last_row = row;
    state.last_col = col;
    state.last_pixel_x = event.pixel_x;
    state.last_pixel_y = event.pixel_y;
    state.last_buttons_down = event.buttons_down;

    if (state.mode == .disabled) return;

    if (state.filter_rect) |rect| {
        if (row < rect.top or row > rect.bottom or col < rect.left or col > rect.right) {
            appendReport(state, allocator, output, encode_buf, 10, event.buttons_down, row, col);
            state.filter_rect = null;
            return;
        }
    }

    const event_code: ?u16 = switch (event.kind) {
        .press => if (state.report_button_down) switch (event.button) {
            .left => 2,
            .middle => 4,
            .right => 6,
            else => null,
        } else null,
        .release => if (state.report_button_up) switch (event.button) {
            .left => 3,
            .middle => 5,
            .right => 7,
            else => null,
        } else null,
        else => null,
    };
    if (event_code) |code| appendReport(state, allocator, output, encode_buf, code, event.buttons_down, row, col);
}

fn appendReport(state: *State, allocator: std.mem.Allocator, output: *std.ArrayList(u8), encode_buf: []u8, event_code: u16, buttons_down: u8, row: u16, col: u16) void {
    const button_mask = buttonsMask(buttons_down);
    const coords = coordinates(state, row, col);
    const text = std.fmt.bufPrint(encode_buf, "\x1b[{d};{d};{d};{d};0&w", .{ event_code, button_mask, coords.row + 1, coords.col + 1 }) catch return;
    output.appendSlice(allocator, text) catch {};
    if (state.mode == .one_shot) state.mode = .disabled;
}

fn coordinates(state: *const State, row: u16, col: u16) struct { row: u32, col: u32 } {
    if (state.coordinate_unit == 1) {
        return .{ .row = state.last_pixel_y orelse row, .col = state.last_pixel_x orelse col };
    }
    return .{ .row = row, .col = col };
}

fn buttonsMask(buttons_down: u8) u16 {
    var mask: u16 = 0;
    if ((buttons_down & 0b001) != 0) mask |= 4;
    if ((buttons_down & 0b010) != 0) mask |= 2;
    if ((buttons_down & 0b100) != 0) mask |= 1;
    return mask;
}
