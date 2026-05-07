//! Responsibility: own mode and state consequences at the vt-core boundary.
//! Ownership: vt-core mode transitions.
//! Reason: keep mode bookkeeping and screen selection changes out of the main vt-core facade.

const input_mod = @import("../input.zig");
const interpret_owner = @import("../interpret.zig");
const grid_owner = @import("../grid.zig");
const terminal_mode_owner = @import("../terminal_mode.zig");

const GridNs = grid_owner;
const Input = input_mod;
const ModeAction = interpret_owner.ModeAction;
const TerminalModeNs = terminal_mode_owner;

pub const Context = struct {
    active_state: *GridNs.GridModel,
    alt_active: *bool,
    keyboard_action_mode: *bool,
    application_cursor_keys: *bool,
    application_keypad: *bool,
    send_receive_mode: *bool,
    newline_mode: *bool,
    modify_other_keys: *i8,
    key_format: *[8]u16,
    pointer_mode: *u2,
    kitty_clipboard: *bool,
    sixel_display_mode: *bool,
    reverse_wraparound_mode: *bool,
    extended_reverse_wraparound_mode: *bool,
    focus_reporting: *bool,
    bracketed_paste: *bool,
    mouse_tracking: *Input.MouseTrackingMode,
    mouse_protocol: *Input.MouseProtocol,
    saved_dec_modes: *[16]TerminalModeNs.SavedDecMode,
    saved_dec_mode_count: *u8,
    owner_ctx: *anyopaque,
    enter_alt_screen: *const fn (ctx: *anyopaque, clear_alt: bool, save_cursor: bool) void,
    exit_alt_screen: *const fn (ctx: *anyopaque, restore_cursor: bool) void,
    is_key_format_resource: *const fn (ctx: *anyopaque, resource: u8) bool,
};

pub fn apply(ctx: Context, action: ModeAction) void {
    switch (action) {
        .enter_alt_screen => |opts| {
            ctx.enter_alt_screen(ctx.owner_ctx, opts.clear, opts.save_cursor);
        },
        .exit_alt_screen => |opts| {
            ctx.exit_alt_screen(ctx.owner_ctx, opts.restore_cursor);
        },
        .application_cursor_keys => |enabled| {
            ctx.application_cursor_keys.* = enabled;
        },
        .application_keypad => |enabled| {
            ctx.application_keypad.* = enabled;
        },
        .ansi_mode_set => |modes| {
            setAnsiModes(ctx, modes.params[0..modes.param_count], true);
        },
        .ansi_mode_reset => |modes| {
            setAnsiModes(ctx, modes.params[0..modes.param_count], false);
        },
        .modify_other_keys_set => |value| {
            ctx.modify_other_keys.* = value;
        },
        .modify_other_keys_disable => {
            ctx.modify_other_keys.* = -1;
        },
        .key_format_change => |change| {
            if (change.resource) |resource| {
                if (ctx.is_key_format_resource(ctx.owner_ctx, resource)) ctx.key_format[resource] = change.value orelse 0;
            } else {
                ctx.key_format.* = [_]u16{0} ** 8;
            }
        },
        .pointer_mode => |value| {
            ctx.pointer_mode.* = value;
        },
        .kitty_clipboard_mode => |enabled| {
            ctx.kitty_clipboard.* = enabled;
        },
        .sixel_display_mode => |enabled| {
            ctx.sixel_display_mode.* = enabled;
        },
        .reverse_wraparound_mode => |enabled| {
            ctx.reverse_wraparound_mode.* = enabled;
        },
        .extended_reverse_wraparound_mode => |enabled| {
            ctx.extended_reverse_wraparound_mode.* = enabled;
        },
        .focus_reporting => |enabled| {
            ctx.focus_reporting.* = enabled;
        },
        .bracketed_paste => |enabled| {
            ctx.bracketed_paste.* = enabled;
        },
        .mouse_tracking_off => {
            ctx.mouse_tracking.* = .off;
        },
        .mouse_tracking_x10 => {
            ctx.mouse_tracking.* = .x10;
        },
        .mouse_tracking_normal => {
            ctx.mouse_tracking.* = .normal;
        },
        .mouse_tracking_button_event => {
            ctx.mouse_tracking.* = .button_event;
        },
        .mouse_tracking_any_event => {
            ctx.mouse_tracking.* = .any_event;
        },
        .mouse_protocol_utf8 => |enabled| {
            ctx.mouse_protocol.* = if (enabled) .utf8 else .none;
        },
        .mouse_protocol_sgr => |enabled| {
            ctx.mouse_protocol.* = if (enabled) .sgr else .none;
        },
        .mouse_protocol_urxvt => |enabled| {
            ctx.mouse_protocol.* = if (enabled) .urxvt else .none;
        },
        .dec_mode_save => |modes| {
            saveDecModes(ctx, modes.params[0..modes.param_count]);
        },
        .dec_mode_restore => |modes| {
            restoreDecModes(ctx, modes.params[0..modes.param_count]);
        },
    }
}

fn setAnsiModes(ctx: Context, modes: []const u16, enabled: bool) void {
    for (modes) |mode| switch (mode) {
        2 => ctx.keyboard_action_mode.* = enabled,
        4 => ctx.active_state.apply(.{ .insert_mode = enabled }),
        12 => ctx.send_receive_mode.* = enabled,
        20 => ctx.newline_mode.* = enabled,
        else => {},
    };
}

fn saveDecModes(ctx: Context, modes: []const u16) void {
    for (modes) |mode| {
        if (!canSetDecMode(mode)) continue;
        const slot = TerminalModeNs.savedDecModeSlot(ctx.saved_dec_modes[0..], ctx.saved_dec_mode_count, mode);
        ctx.saved_dec_modes[slot] = .{
            .mode = mode,
            .state = TerminalModeNs.decModeStateForView(decView(ctx), mode),
        };
    }
}

fn restoreDecModes(ctx: Context, modes: []const u16) void {
    for (modes) |mode| {
        const state = TerminalModeNs.savedDecModeState(ctx.saved_dec_modes[0..], ctx.saved_dec_mode_count.*, mode) orelse continue;
        switch (state) {
            1 => setDecMode(ctx, mode, true),
            2 => setDecMode(ctx, mode, false),
            else => {},
        }
    }
}

fn setDecMode(ctx: Context, mode: u16, enabled: bool) void {
    switch (mode) {
        1 => ctx.application_cursor_keys.* = enabled,
        6 => ctx.active_state.apply(.{ .origin_mode = enabled }),
        7 => ctx.active_state.apply(.{ .auto_wrap = enabled }),
        69 => ctx.active_state.apply(.{ .left_right_margin_mode = enabled }),
        25 => ctx.active_state.apply(.{ .cursor_visible = enabled }),
        66 => ctx.application_keypad.* = enabled,
        47 => if (enabled) ctx.enter_alt_screen(ctx.owner_ctx, false, false) else ctx.exit_alt_screen(ctx.owner_ctx, false),
        1047 => if (enabled) ctx.enter_alt_screen(ctx.owner_ctx, true, false) else ctx.exit_alt_screen(ctx.owner_ctx, false),
        1049 => if (enabled) ctx.enter_alt_screen(ctx.owner_ctx, true, true) else ctx.exit_alt_screen(ctx.owner_ctx, true),
        9 => ctx.mouse_tracking.* = if (enabled) .x10 else .off,
        1000 => ctx.mouse_tracking.* = if (enabled) .normal else .off,
        1002 => ctx.mouse_tracking.* = if (enabled) .button_event else .off,
        1003 => ctx.mouse_tracking.* = if (enabled) .any_event else .off,
        1004 => ctx.focus_reporting.* = enabled,
        1005 => ctx.mouse_protocol.* = if (enabled) .utf8 else .none,
        1006 => ctx.mouse_protocol.* = if (enabled) .sgr else .none,
        1015 => ctx.mouse_protocol.* = if (enabled) .urxvt else .none,
        2004 => ctx.bracketed_paste.* = enabled,
        5522 => ctx.kitty_clipboard.* = enabled,
        else => {},
    }
}

fn canSetDecMode(mode: u16) bool {
    return TerminalModeNs.decModeStateForView(decViewForDefaults(), mode) != 0;
}

fn decView(ctx: Context) TerminalModeNs.DecView {
    return .{
        .application_cursor_keys = ctx.application_cursor_keys.*,
        .application_keypad = ctx.application_keypad.*,
        .auto_wrap = ctx.active_state.auto_wrap,
        .left_right_margin_mode = ctx.active_state.left_right_margin_mode,
        .cursor_visible = ctx.active_state.cursor_visible,
        .alt_active = ctx.alt_active.*,
        .mouse_tracking = ctx.mouse_tracking.*,
        .mouse_protocol = ctx.mouse_protocol.*,
        .focus_reporting = ctx.focus_reporting.*,
        .bracketed_paste = ctx.bracketed_paste.*,
        .kitty_clipboard = ctx.kitty_clipboard.*,
    };
}

fn decViewForDefaults() TerminalModeNs.DecView {
    return .{
        .application_cursor_keys = false,
        .application_keypad = false,
        .auto_wrap = false,
        .left_right_margin_mode = false,
        .cursor_visible = false,
        .alt_active = false,
        .mouse_tracking = .off,
        .mouse_protocol = .none,
        .focus_reporting = false,
        .bracketed_paste = false,
        .kitty_clipboard = false,
    };
}
