//! Responsibility: handle mode and state semantic consequences for vt-core.
//! Ownership: root dispatch helper for mode/state transitions.
//! Reason: keep mode bookkeeping and state toggles out of the main root dispatcher.

const interpret_owner = @import("interpret.zig");
const terminal_mode_owner = @import("terminal_mode.zig");

const ModeAction = interpret_owner.Interpret.ModeAction;
const TerminalModeNs = terminal_mode_owner.TerminalMode;

pub const RootModeDispatch = struct {
    pub fn apply(self: anytype, action: ModeAction) void {
        switch (action) {
            .enter_alt_screen => |opts| {
                TerminalModeNs.enterAltScreen(self, opts.clear, opts.save_cursor);
            },
            .exit_alt_screen => |opts| {
                TerminalModeNs.exitAltScreen(self, opts.restore_cursor);
            },
            .application_cursor_keys => |enabled| {
                self.application_cursor_keys = enabled;
            },
            .application_keypad => |enabled| {
                self.application_keypad = enabled;
            },
            .ansi_mode_set => |modes| {
                TerminalModeNs.setAnsiModes(self, modes.params[0..modes.param_count], true);
            },
            .ansi_mode_reset => |modes| {
                TerminalModeNs.setAnsiModes(self, modes.params[0..modes.param_count], false);
            },
            .modify_other_keys_set => |value| {
                self.modify_other_keys = value;
            },
            .modify_other_keys_disable => {
                self.modify_other_keys = -1;
            },
            .focus_reporting => |enabled| {
                self.focus_reporting = enabled;
            },
            .bracketed_paste => |enabled| {
                self.bracketed_paste = enabled;
            },
            .mouse_tracking_off => {
                self.mouse_tracking = .off;
            },
            .mouse_tracking_x10 => {
                self.mouse_tracking = .x10;
            },
            .mouse_tracking_normal => {
                self.mouse_tracking = .normal;
            },
            .mouse_tracking_button_event => {
                self.mouse_tracking = .button_event;
            },
            .mouse_tracking_any_event => {
                self.mouse_tracking = .any_event;
            },
            .mouse_protocol_utf8 => |enabled| {
                self.mouse_protocol = if (enabled) .utf8 else .none;
            },
            .mouse_protocol_sgr => |enabled| {
                self.mouse_protocol = if (enabled) .sgr else .none;
            },
            .mouse_protocol_urxvt => |enabled| {
                self.mouse_protocol = if (enabled) .urxvt else .none;
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
