//! Responsibility: own kitty protocol consequences at the vt-core boundary.
//! Ownership: vt-core kitty state and host output.
//! Reason: keep kitty-specific state and replies out of the main vt-core facade.

const kitty_owner = @import("../kitty.zig");
const interpret_owner = @import("../interpret.zig");

const KittyAction = interpret_owner.Interpret.KittyAction;
const KittyNs = kitty_owner.Kitty;

pub const VtCoreKitty = struct {
    pub fn apply(self: anytype, action: KittyAction) void {
        switch (action) {
            .kitty_keyboard_set => |req| {
                activeKittyKeyboard(self).set(req.flags, req.mode);
            },
            .kitty_keyboard_query => {
                activeKittyKeyboardConst(self).appendReport(self.allocator, &self.host.pending_output, self.encode.buf[0..]);
            },
            .kitty_keyboard_push => |flags| {
                activeKittyKeyboard(self).push(flags);
            },
            .kitty_keyboard_pop => |count| {
                activeKittyKeyboard(self).pop(count);
            },
            .kitty_shell_mark => |mark| {
                KittyNs.setShellMark(self.allocator, &self.kitty.global.shell_mark, mark);
            },
            .kitty_notification => |notification| {
                KittyNs.appendNotification(self.allocator, &self.kitty.global.notifications, notification);
            },
            .kitty_pointer_shape => |cmd| {
                switch (cmd.action) {
                    '<' => activeKittyScreen(self).pointer.pop(),
                    '>' => activeKittyScreen(self).pointer.push(cmd.names),
                    '?' => activeKittyScreenConst(self).pointer.appendQuery(self.allocator, &self.host.pending_output, cmd.names),
                    else => activeKittyScreen(self).pointer.set(cmd.names),
                }
            },
            .kitty_color_stack => |cmd| {
                switch (cmd) {
                    .push => KittyNs.Color.pushState(&self.kitty.global.color_stack, &self.host.terminal_colors, &self.kitty.global.color_stack_depth),
                    .pop => KittyNs.Color.popState(&self.kitty.global.color_stack, &self.host.terminal_colors, &self.kitty.global.color_stack_depth),
                }
            },
            .kitty_graphics => |cmd| {
                self.kitty.global.graphics.handle(self.allocator, self.renderView(), &self.host.pending_output, self.encode.buf[0..], cmd);
            },
        }
    }

    fn activeKittyKeyboard(self: anytype) *KittyNs.Key.Stack {
        return &activeKittyScreen(self).keyboard;
    }

    fn activeKittyKeyboardConst(self: anytype) *const KittyNs.Key.Stack {
        return &activeKittyScreenConst(self).keyboard;
    }

    fn activeKittyScreen(self: anytype) *KittyNs.ScreenState {
        return self.kitty.activeScreen(self.screen_state.alt_active);
    }

    fn activeKittyScreenConst(self: anytype) *const KittyNs.ScreenState {
        return self.kitty.activeScreenConst(self.screen_state.alt_active);
    }
};
