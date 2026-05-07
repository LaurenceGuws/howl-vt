//! Responsibility: own kitty protocol consequences at the vt-core boundary.
//! Ownership: vt-core kitty state and host output.
//! Reason: keep kitty-specific state and replies out of the main vt-core facade.

const std = @import("std");
const kitty_owner = @import("../kitty.zig");
const interpret_owner = @import("../interpret.zig");
const osc_color_owner = @import("../osc_color.zig");

const KittyAction = interpret_owner.Interpret.KittyAction;
const KittyNs = kitty_owner.Kitty;
const OscColorNs = osc_color_owner.OscColor;

pub const VtCoreKitty = struct {
    pub const Context = struct {
        allocator: std.mem.Allocator,
        pending_output: *std.ArrayList(u8),
        encode_buf: []u8,
        active_screen: *KittyNs.ScreenState,
        active_screen_const: *const KittyNs.ScreenState,
        global: *KittyNs.GlobalState,
        terminal_colors: *OscColorNs.State,
        graphics_cursor: KittyNs.Graphics.RenderCursorView,
    };

    pub fn apply(ctx: Context, action: KittyAction) void {
        switch (action) {
            .kitty_keyboard_set => |req| {
                activeKittyKeyboard(ctx).set(req.flags, req.mode);
            },
            .kitty_keyboard_query => {
                activeKittyKeyboardConst(ctx).appendReport(ctx.allocator, ctx.pending_output, ctx.encode_buf);
            },
            .kitty_keyboard_push => |flags| {
                activeKittyKeyboard(ctx).push(flags);
            },
            .kitty_keyboard_pop => |count| {
                activeKittyKeyboard(ctx).pop(count);
            },
            .kitty_shell_mark => |mark| {
                KittyNs.setShellMark(ctx.allocator, &ctx.global.shell_mark, mark);
            },
            .kitty_notification => |notification| {
                KittyNs.appendNotification(ctx.allocator, &ctx.global.notifications, notification);
            },
            .kitty_pointer_shape => |cmd| {
                switch (cmd.action) {
                    '<' => ctx.active_screen.pointer.pop(),
                    '>' => ctx.active_screen.pointer.push(cmd.names),
                    '?' => ctx.active_screen_const.pointer.appendQuery(ctx.allocator, ctx.pending_output, cmd.names),
                    else => ctx.active_screen.pointer.set(cmd.names),
                }
            },
            .kitty_color_stack => |cmd| {
                switch (cmd) {
                    .push => KittyNs.Color.pushState(&ctx.global.color_stack, ctx.terminal_colors, &ctx.global.color_stack_depth),
                    .pop => KittyNs.Color.popState(&ctx.global.color_stack, ctx.terminal_colors, &ctx.global.color_stack_depth),
                }
            },
            .kitty_multiple_cursor => |cmd| switch (cmd) {
                .support_query => ctx.pending_output.appendSlice(ctx.allocator, "\x1b[>1;2;3;29;30;40;100;101 q") catch {},
                .clear_all => ctx.active_screen.multiple_cursor_count = 0,
                .cursor_query => ctx.pending_output.appendSlice(ctx.allocator, "\x1b[>100 q") catch {},
                .color_query => ctx.pending_output.appendSlice(ctx.allocator, "\x1b[>101;30:0;40:0 q") catch {},
            },
            .kitty_file_transfer => |payload| KittyNs.setOptionalPayload(ctx.allocator, &ctx.global.file_transfer_request, payload),
            .kitty_text_size => |payload| KittyNs.setOptionalPayload(ctx.allocator, &ctx.global.text_size_request, payload),
            .kitty_graphics => |cmd| {
                ctx.global.graphics.handle(ctx.allocator, ctx.graphics_cursor, ctx.pending_output, ctx.encode_buf, cmd);
            },
        }
    }

    fn activeKittyKeyboard(ctx: Context) *KittyNs.Key.Stack {
        return &ctx.active_screen.keyboard;
    }

    fn activeKittyKeyboardConst(ctx: Context) *const KittyNs.Key.Stack {
        return &ctx.active_screen_const.keyboard;
    }
};
