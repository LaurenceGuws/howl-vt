//! VT byte-stream parser.

const std = @import("std");
const parse_table = @import("parser/parse_table.zig");
const string_control_mod = @import("parser/string_control.zig");
const utf8_mod = @import("parser/utf8.zig");

const ParseState = parse_table.ParseState;
const TransitionAction = parse_table.TransitionAction;
const ParamKind = enum {
    csi,
    dcs,
};
const BufferedControlKind = enum {
    dcs,
    apc,
    pm,
};

pub const DeccirCharsetState = struct {
    g0_designation: u8,
    g1_designation: u8,
    gl_index: u8,
};

const csi_max_params: usize = 16;
const csi_max_intermediates: usize = 4;

pub const max_params = csi_max_params;
pub const max_intermediates = csi_max_intermediates;

pub const OscTerminator = enum {
    bel,
    st,
};

pub const EscAction = struct {
    final: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
};

pub const DcsHook = struct {
    final: u8,
    params: [csi_max_params]i32,
    count: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
};

const CsiActionData = struct {
    final: u8,
    params: [csi_max_params]i32,
    separators: [csi_max_params]u8,
    count: u8,
    leader: u8,
    private: bool,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
};

pub const CsiAction = CsiActionData;

pub const Action = union(enum) {
    print: u21,
    execute: u8,
    invalid,
    csi_dispatch: CsiAction,
    osc_dispatch: struct { data: []const u8, term: OscTerminator },
    apc_start,
    apc_put: u8,
    apc_end,
    dcs_hook: DcsHook,
    dcs_put: u8,
    dcs_unhook,
    pm_start,
    pm_put: u8,
    pm_end,
    esc_dispatch: EscAction,
};

pub const PhaseActions = [3]?Action;

/// Stateful parser for terminal input streams.
pub const Parser = struct {
    utf8: utf8_mod.Utf8Decoder,
    state: ParseState,
    csi_params: [csi_max_params]i32,
    csi_separators: [csi_max_params]u8,
    csi_count: u8,
    csi_leader: u8,
    csi_private: bool,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
    csi_in_param: bool,
    osc_finish_term: ?OscTerminator,
    osc: string_control_mod.StringControl,
    apc: string_control_mod.StringControl,
    dcs: string_control_mod.StringControl,
    pm: string_control_mod.StringControl,

    /// Initialize parser state and owned buffers.
    pub fn init(allocator: std.mem.Allocator) !Parser {
        var osc = try string_control_mod.StringControl.init(allocator, 256, 4096, true);
        errdefer osc.deinit();

        var apc = try string_control_mod.StringControl.init(allocator, 256, 1024 * 1024, false);
        errdefer apc.deinit();

        var dcs = try string_control_mod.StringControl.init(allocator, 256, 4096, false);
        errdefer dcs.deinit();

        var pm = try string_control_mod.StringControl.init(allocator, 256, 4096, false);
        errdefer pm.deinit();

        return .{
            .utf8 = .{},
            .state = .ground,
            .csi_params = [_]i32{0} ** csi_max_params,
            .csi_separators = [_]u8{0} ** csi_max_params,
            .csi_count = 0,
            .csi_leader = 0,
            .csi_private = false,
            .intermediates = [_]u8{0} ** csi_max_intermediates,
            .intermediates_len = 0,
            .csi_in_param = false,
            .osc_finish_term = null,
            .osc = osc,
            .apc = apc,
            .dcs = dcs,
            .pm = pm,
        };
    }

    /// Release parser-owned buffers.
    pub fn deinit(self: *Parser) void {
        self.osc.deinit();
        self.apc.deinit();
        self.dcs.deinit();
        self.pm.deinit();
    }

    /// Reset parser state and transient buffers.
    pub fn reset(self: *Parser) void {
        self.utf8.reset();
        self.clear();
        self.state = .ground;
        self.osc_finish_term = null;
        self.osc.reset();
        self.apc.reset();
        self.dcs.reset();
        self.pm.reset();
    }

    /// Advance the parser by one byte and return ordered phase actions.
    pub fn next(self: *Parser, byte: u8) PhaseActions {
        self.cleanupBorrowedPhaseState();
        const Active = struct {
            action: ?Action = null,
            next_state: ParseState,
        };

        std.debug.assert(self.activeControlCount() <= 1);
        if (self.state == .ground and self.utf8.needed > 0) {
            const action = self.consumeGroundByte(byte);
            return .{ null, action, null };
        }

        const transition = parse_table.table[byte][@intFromEnum(self.state)];
        if (self.isActiveState()) {
            if (byte == 0x9C) {
                const current_state = self.state;
                const sos_kind = if (current_state == .sos_pm_apc_string) self.sosPmApcKind() else null;
                defer self.state = .ground;

                switch (current_state) {
                    .osc_string => {
                        self.osc.finishSt();
                        self.osc_finish_term = .st;
                    },
                    .dcs_passthrough => self.dcs.finishSt(),
                    .sos_pm_apc_string => switch (sos_kind.?) {
                        .apc => self.apc.finishSt(),
                        .pm => self.pm.finishSt(),
                        .dcs => unreachable,
                    },
                    else => unreachable,
                }

                return self.buildPhases(current_state, .ground, null, byte, sos_kind);
            }

            const active_escaping = switch (self.state) {
                .osc_string => self.osc.escaping(),
                .dcs_passthrough => self.dcs.escaping(),
                .sos_pm_apc_string => switch (self.sosPmApcKind()) {
                    .apc => self.apc.escaping(),
                    .pm => self.pm.escaping(),
                    .dcs => unreachable,
                },
                else => false,
            };
            if (byte != 0x1B and !active_escaping and (transition.state != self.state or transition.action != .none)) {
                const transition_action = self.doAction(transition.action, byte);
                const next_state = transition.state;
                const current_state = self.state;
                defer self.state = next_state;

                return self.buildPhases(current_state, next_state, transition_action, byte, null);
            }

            const current_state = self.state;
            const sos_kind = if (current_state == .sos_pm_apc_string) self.sosPmApcKind() else null;
            const active: Active = switch (self.state) {
                .osc_string => osc: {
                    const result = self.osc.feed(byte) orelse break :osc .{
                        .action = @as(?Action, null),
                        .next_state = ParseState.osc_string,
                    };
                    break :osc switch (result) {
                        .put => .{ .action = @as(?Action, null), .next_state = ParseState.osc_string },
                        .finish => |finish| {
                            self.osc_finish_term = switch (finish) {
                                .bel => .bel,
                                .st => .st,
                            };
                            break :osc .{ .action = @as(?Action, null), .next_state = ParseState.ground };
                        },
                    };
                },
                .dcs_passthrough => dcs: {
                    const result = self.dcs.feed(byte) orelse break :dcs .{
                        .action = @as(?Action, null),
                        .next_state = ParseState.dcs_passthrough,
                    };
                    break :dcs switch (result) {
                        .put => |payload_byte| .{ .action = .{ .dcs_put = payload_byte }, .next_state = ParseState.dcs_passthrough },
                        .finish => .{ .action = @as(?Action, null), .next_state = ParseState.ground },
                    };
                },
                .sos_pm_apc_string => switch (self.sosPmApcKind()) {
                    .apc => apc: {
                        const result = self.apc.feed(byte) orelse break :apc .{
                            .action = @as(?Action, null),
                            .next_state = ParseState.sos_pm_apc_string,
                        };
                        break :apc switch (result) {
                            .put => |payload_byte| .{ .action = .{ .apc_put = payload_byte }, .next_state = ParseState.sos_pm_apc_string },
                            .finish => .{ .action = @as(?Action, null), .next_state = ParseState.ground },
                        };
                    },
                    .pm => pm: {
                        const result = self.pm.feed(byte) orelse break :pm .{
                            .action = @as(?Action, null),
                            .next_state = ParseState.sos_pm_apc_string,
                        };
                        break :pm switch (result) {
                            .put => |payload_byte| .{ .action = .{ .pm_put = payload_byte }, .next_state = ParseState.sos_pm_apc_string },
                            .finish => .{ .action = @as(?Action, null), .next_state = ParseState.ground },
                        };
                    },
                    .dcs => unreachable,
                },
                else => unreachable,
            };
            defer self.state = active.next_state;
            return self.buildPhases(current_state, active.next_state, active.action, byte, sos_kind);
        }

        const transition_action = self.doAction(transition.action, byte);
        const next_state = transition.state;
        const current_state = self.state;
        defer self.state = next_state;

        return self.buildPhases(current_state, next_state, transition_action, byte, null);
    }

    fn collect(self: *Parser, byte: u8) void {
        if (self.intermediates_len >= self.intermediates.len) return;
        self.intermediates[self.intermediates_len] = byte;
        self.intermediates_len += 1;
    }

    fn buildPhases(self: *Parser, current_state: ParseState, next_state: ParseState, transition_action: ?Action, byte: u8, sos_kind: ?BufferedControlKind) PhaseActions {
        return .{
            if (current_state == next_state) null else switch (current_state) {
                .osc_string => exit: {
                    const term = self.osc_finish_term orelse break :exit null;
                    break :exit .{ .osc_dispatch = .{ .data = self.osc.data(), .term = term } };
                },
                .dcs_passthrough => dcs: {
                    self.dcs.clearFinished();
                    break :dcs .dcs_unhook;
                },
                .sos_pm_apc_string => exit: {
                    break :exit switch (sos_kind orelse self.sosPmApcKind()) {
                        .apc => apc: {
                            self.apc.clearFinished();
                            break :apc .apc_end;
                        },
                        .pm => pm: {
                            self.pm.clearFinished();
                            break :pm .pm_end;
                        },
                        .dcs => unreachable,
                    };
                },
                else => null,
            },
            transition_action,
            if (current_state == next_state) null else switch (next_state) {
                .escape, .csi_entry, .dcs_entry => entry: {
                    if (next_state == .escape) {
                        std.debug.assert(self.activeControlCount() <= 1);
                        self.utf8.reset();
                        self.osc.reset();
                        self.apc.reset();
                        self.dcs.reset();
                        self.pm.reset();
                        self.clear();
                        std.debug.assert(self.activeControlCount() == 0);
                    } else {
                        self.clear();
                    }
                    break :entry null;
                },
                .osc_string => entry: {
                    std.debug.assert(self.activeControlCount() == 0);
                    self.osc.start();
                    std.debug.assert(self.osc.active());
                    std.debug.assert(self.activeControlCount() == 1);
                    break :entry null;
                },
                .dcs_passthrough => entry: {
                    std.debug.assert(self.activeControlCount() == 0);
                    self.dcs.start();
                    std.debug.assert(self.dcs.active());
                    std.debug.assert(self.activeControlCount() == 1);
                    var final_count = self.csi_count;
                    if (self.csi_in_param) final_count += 1;
                    const hook = DcsHook{
                        .final = byte,
                        .params = self.csi_params,
                        .count = final_count,
                        .intermediates = self.intermediates,
                        .intermediates_len = self.intermediates_len,
                    };
                    self.clear();
                    break :entry .{ .dcs_hook = hook };
                },
                .sos_pm_apc_string => entry: {
                    break :entry switch (byte) {
                        '_', 0x9F => apc: {
                            std.debug.assert(self.activeControlCount() == 0);
                            self.apc.start();
                            std.debug.assert(self.apc.active());
                            std.debug.assert(self.activeControlCount() == 1);
                            break :apc .apc_start;
                        },
                        '^', 0x98, 0x9E => pm: {
                            std.debug.assert(self.activeControlCount() == 0);
                            self.pm.start();
                            std.debug.assert(self.pm.active());
                            std.debug.assert(self.activeControlCount() == 1);
                            break :pm .pm_start;
                        },
                        else => unreachable,
                    };
                },
                else => null,
            },
        };
    }

    fn doAction(self: *Parser, action: TransitionAction, byte: u8) ?Action {
        return switch (action) {
            .none => null,
            .print => .{ .print = byte },
            .ground => ground: {
                if (self.consumeGroundByte(byte)) |action_result| break :ground action_result;
                break :ground null;
            },
            .execute => .{ .execute = byte },
            .collect => collect: {
                if (self.state == .csi_entry and (byte == '<' or byte == '>' or byte == '=' or byte == '?')) {
                    if (self.csi_leader == 0) self.csi_leader = byte;
                    if (byte == '?') self.csi_private = true;
                    break :collect null;
                }

                self.collect(byte);
                break :collect null;
            },
            .ignore => null,
            .esc_dispatch => esc_dispatch: {
                const esc: Action = .{ .esc_dispatch = .{
                    .final = byte,
                    .intermediates = self.intermediates,
                    .intermediates_len = self.intermediates_len,
                } };
                self.clear();
                break :esc_dispatch esc;
            },
            .csi_dispatch => self.consumeCsiDispatch(byte),
            .osc_put => osc_put: {
                const result = self.osc.feed(byte) orelse break :osc_put null;
                break :osc_put switch (result) {
                    .put => null,
                    .finish => unreachable,
                };
            },
            .put => put: {
                const result = self.dcs.feed(byte) orelse break :put null;
                break :put switch (result) {
                    .put => |payload_byte| .{ .dcs_put = payload_byte },
                    .finish => unreachable,
                };
            },
            .apc_put => apc_put: {
                break :apc_put switch (self.sosPmApcKind()) {
                    .apc => apc: {
                        const result = self.apc.feed(byte) orelse break :apc null;
                        break :apc switch (result) {
                            .put => |payload_byte| .{ .apc_put = payload_byte },
                            .finish => unreachable,
                        };
                    },
                    .pm => pm: {
                        const result = self.pm.feed(byte) orelse break :pm null;
                        break :pm switch (result) {
                            .put => |payload_byte| .{ .pm_put = payload_byte },
                            .finish => unreachable,
                        };
                    },
                    .dcs => unreachable,
                };
            },
            .param => switch (self.state) {
                .csi_entry, .csi_param => csi: {
                    self.feedParamByte(.csi, byte);
                    break :csi null;
                },
                .dcs_entry, .dcs_param => dcs: {
                    self.feedParamByte(.dcs, byte);
                    break :dcs null;
                },
                else => unreachable,
            },
        };
    }

    fn cleanupBorrowedPhaseState(self: *Parser) void {
        if (self.osc_finish_term != null and self.state != .osc_string) {
            self.osc_finish_term = null;
            self.osc.clearFinished();
        }
    }

    fn isActiveState(self: *const Parser) bool {
        return switch (self.state) {
            .osc_string, .dcs_passthrough, .sos_pm_apc_string => true,
            else => false,
        };
    }

    fn sosPmApcKind(self: *const Parser) BufferedControlKind {
        if (self.apc.active()) {
            std.debug.assert(!self.pm.active());
            return .apc;
        }

        std.debug.assert(self.pm.active());
        return .pm;
    }

    fn activeControlCount(self: *const Parser) u3 {
        var count: u3 = 0;
        if (self.osc.active()) count += 1;
        if (self.apc.active()) count += 1;
        if (self.dcs.active()) count += 1;
        if (self.pm.active()) count += 1;
        return count;
    }

    fn clear(self: *Parser) void {
        self.csi_params[0] = 0;
        self.csi_count = 0;
        self.csi_separators[0] = 0;
        self.csi_leader = 0;
        self.csi_private = false;
        self.intermediates_len = 0;
        self.csi_in_param = false;
    }

    fn consumeGroundByte(self: *Parser, byte: u8) ?Action {
        return switch (self.utf8.feed(byte)) {
            .codepoint => |cp| .{ .print = cp },
            .invalid => .invalid,
            .incomplete => null,
        };
    }

    fn feedParamByte(self: *Parser, comptime kind: ParamKind, byte: u8) void {
        if (byte == ';' or byte == ':') {
            if (self.csi_count < self.csi_params.len) {
                self.csi_count += 1;
                if (self.csi_count < self.csi_params.len) {
                    self.csi_params[self.csi_count] = 0;
                    if (kind == .csi) self.csi_separators[self.csi_count] = byte;
                }
            }
            self.csi_in_param = false;
            return;
        }

        if (byte >= '0' and byte <= '9') {
            const digit: i32 = @intCast(byte - '0');
            if (self.csi_count >= self.csi_params.len) return;
            if (!self.csi_in_param) {
                self.csi_params[self.csi_count] = digit;
                self.csi_in_param = true;
            } else {
                self.csi_params[self.csi_count] = self.csi_params[self.csi_count] * 10 + digit;
            }
            return;
        }
    }

    fn consumeCsiDispatch(self: *Parser, byte: u8) ?Action {
        std.debug.assert(byte >= 0x40);
        std.debug.assert(byte <= 0x7E);

        var final_count = self.csi_count;
        if (self.csi_in_param) final_count += 1;
        const action = CsiActionData{
            .final = byte,
            .params = self.csi_params,
            .separators = self.csi_separators,
            .count = final_count,
            .leader = self.csi_leader,
            .private = self.csi_private,
            .intermediates = self.intermediates,
            .intermediates_len = self.intermediates_len,
        };
        self.clear();
        return .{ .csi_dispatch = action };
    }

};
