//! Responsibility: own mode and state consequences at the vt-core boundary.
//! Ownership: vt-core mode transitions.
//! Reason: keep mode bookkeeping and screen selection changes out of the main vt-core facade.

const interpret_owner = @import("../interpret.zig");
const terminal_mode_owner = @import("../terminal_mode.zig");

const ModeAction = interpret_owner.Interpret.ModeAction;
const TerminalModeNs = terminal_mode_owner.TerminalMode;

pub const VtCoreModes = struct {
    pub fn apply(self: anytype, action: ModeAction) void {
        switch (action) {
            .enter_alt_screen => |opts| {
                TerminalModeNs.enterAltScreen(self, opts.clear, opts.save_cursor);
            },
            .exit_alt_screen => |opts| {
                TerminalModeNs.exitAltScreen(self, opts.restore_cursor);
            },
            .application_cursor_keys => |enabled| {
                self.modes.application_cursor_keys = enabled;
            },
            .application_keypad => |enabled| {
                self.modes.application_keypad = enabled;
            },
            .ansi_mode_set => |modes| {
                TerminalModeNs.setAnsiModes(self, modes.params[0..modes.param_count], true);
            },
            .ansi_mode_reset => |modes| {
                TerminalModeNs.setAnsiModes(self, modes.params[0..modes.param_count], false);
            },
            .modify_other_keys_set => |value| {
                self.modes.modify_other_keys = value;
            },
            .modify_other_keys_disable => {
                self.modes.modify_other_keys = -1;
            },
            .key_format_change => |change| {
                if (change.resource) |resource| {
                    if (self.isKeyFormatResource(resource)) self.modes.key_format[resource] = change.value orelse 0;
                } else {
                    self.modes.key_format = [_]u16{0} ** 8;
                }
            },
            .pointer_mode => |value| {
                self.modes.pointer_mode = value;
            },
            .kitty_clipboard_mode => |enabled| {
                self.modes.kitty_clipboard = enabled;
            },
            .focus_reporting => |enabled| {
                self.modes.focus_reporting = enabled;
            },
            .bracketed_paste => |enabled| {
                self.modes.bracketed_paste = enabled;
            },
            .mouse_tracking_off => {
                self.modes.mouse_tracking = .off;
            },
            .mouse_tracking_x10 => {
                self.modes.mouse_tracking = .x10;
            },
            .mouse_tracking_normal => {
                self.modes.mouse_tracking = .normal;
            },
            .mouse_tracking_button_event => {
                self.modes.mouse_tracking = .button_event;
            },
            .mouse_tracking_any_event => {
                self.modes.mouse_tracking = .any_event;
            },
            .mouse_protocol_utf8 => |enabled| {
                self.modes.mouse_protocol = if (enabled) .utf8 else .none;
            },
            .mouse_protocol_sgr => |enabled| {
                self.modes.mouse_protocol = if (enabled) .sgr else .none;
            },
            .mouse_protocol_urxvt => |enabled| {
                self.modes.mouse_protocol = if (enabled) .urxvt else .none;
            },
            .dec_mode_save => |modes| {
                TerminalModeNs.saveDecModes(self, modes.params[0..modes.param_count]);
            },
            .dec_mode_restore => |modes| {
                TerminalModeNs.restoreDecModes(self, modes.params[0..modes.param_count]);
            },
        }
    }
};
