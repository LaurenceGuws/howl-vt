//! Responsibility: handle kitty-family semantic consequences for vt-core.
//! Ownership: root dispatch helper for kitty protocol state and host output.
//! Reason: keep kitty-specific dispatch out of the main root dispatcher.

const kitty_owner = @import("kitty.zig");
const interpret_owner = @import("interpret.zig");

const KittyAction = interpret_owner.Interpret.KittyAction;
const KittyNs = kitty_owner.Kitty;

pub const RootKittyDispatch = struct {
    pub fn apply(self: anytype, action: KittyAction) void {
        switch (action) {
            .kitty_keyboard_set => |req| {
                activeKittyKeyboard(self).set(req.flags, req.mode);
            },
            .kitty_keyboard_query => {
                activeKittyKeyboardConst(self).appendReport(self.allocator, &self.pending_output, self.encode_buf[0..]);
            },
            .kitty_keyboard_push => |flags| {
                activeKittyKeyboard(self).push(flags);
            },
            .kitty_keyboard_pop => |count| {
                activeKittyKeyboard(self).pop(count);
            },
            .kitty_shell_mark => |mark| {
                KittyNs.setShellMark(self.allocator, &self.kitty.shell_mark, mark);
            },
            .kitty_notification => |notification| {
                KittyNs.appendNotification(self.allocator, &self.kitty.notifications, notification);
            },
            .kitty_pointer_shape => |cmd| {
                switch (cmd.action) {
                    '<' => activeKittyScreen(self).pointer.pop(),
                    '>' => activeKittyScreen(self).pointer.push(cmd.names),
                    '?' => activeKittyScreenConst(self).pointer.appendQuery(self.allocator, &self.pending_output, cmd.names),
                    else => activeKittyScreen(self).pointer.set(cmd.names),
                }
            },
            .kitty_color_stack => |cmd| {
                switch (cmd) {
                    .push => KittyNs.Color.pushState(&self.kitty.color_stack, &self.terminal_colors, &self.kitty.color_stack_depth),
                    .pop => KittyNs.Color.popState(&self.kitty.color_stack, &self.terminal_colors, &self.kitty.color_stack_depth),
                }
            },
            .kitty_graphics => |cmd| {
                self.kitty.graphics.handle(self.allocator, self.renderView(), &self.pending_output, self.encode_buf[0..], cmd);
            },
        }
    }

    fn activeKittyKeyboard(self: anytype) @TypeOf(&self.kitty_main.keyboard) {
        return &activeKittyScreen(self).keyboard;
    }

    fn activeKittyKeyboardConst(self: anytype) @TypeOf(&self.kitty_main.keyboard) {
        return &activeKittyScreenConst(self).keyboard;
    }

    fn activeKittyScreen(self: anytype) @TypeOf(&self.kitty_main) {
        return if (self.alt_active) &self.kitty_alt else &self.kitty_main;
    }

    fn activeKittyScreenConst(self: anytype) @TypeOf(&self.kitty_main) {
        return if (self.alt_active) &self.kitty_alt else &self.kitty_main;
    }
};
