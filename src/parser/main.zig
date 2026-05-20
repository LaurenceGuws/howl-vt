const std = @import("std");
const parse_table = @import("parse_table.zig");
const string_control_mod = @import("string_control.zig");
const utf8_mod = @import("utf8.zig");

const ParseState = parse_table.ParseState;
const TransitionAction = parse_table.TransitionAction;
const ParamKind = enum {
    csi,
    dcs,
};
const BufferedControlKind = enum {
    apc,
    pm,
};

pub const DeccirCharsetState = struct {
    g0_designation: u8,
    g1_designation: u8,
    gl_index: u8,
};

// Ghostty raised this from 16 to 24 after hitting real 17-parameter SGR input
// from Kakoune. Howl now matches 24 because queued CSI and DCS events no longer
// carry this bound inline in the parsed-event union. Keep this aligned with the
// Ghostty reference unless later proof falsifies the current cut.
const csi_max_params = 24;
const csi_max_intermediates = 4;
// Start metadata controls small so ordinary title, report, and color traffic
// avoids immediate growth without preallocating the full metadata ceiling for
// every parser-owned control buffer.
const control_init_capacity = 256;
// Keep metadata-sized control strings explicitly small. The owned OSC, DCS,
// and PM protocols in Howl are title, color, report, clipboard, and similar
// metadata paths, not bulk transport.
const metadata_control_max_bytes = 4096;
// Large OSC payload families such as clipboard, text sizing, and file-transfer
// can legitimately exceed the metadata ceiling. Keep their parser-owned bound
// aligned to the same 1 MiB burst scale already used for APC and PTY transport
// proof until host-neutral protocol ownership says otherwise.
const large_osc_control_max_bytes = 1024 * 1024;
// APC is the one owned string-control family that legitimately carries large
// Kitty payload chunks, so keep its bound aligned to the same 1 MiB burst scale
// already derived from Alacritty's PTY read buffer and the host transport path.
// Re-derive it only if those owners stop sharing that burst scale.
const apc_max_bytes = 1024 * 1024;

pub const max_params = csi_max_params;
pub const max_intermediates = csi_max_intermediates;
pub const CsiSeparatorList = std.StaticBitSet(csi_max_params);
pub const max_metadata_control_bytes = metadata_control_max_bytes;
pub const max_large_osc_control_bytes = large_osc_control_max_bytes;
pub const max_apc_control_bytes = apc_max_bytes;
pub const OscKind = string_control_mod.OscKind;

pub const OscTerminator = enum {
    bel,
    st,
};

pub const EscAction = struct {
    final: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
};

pub const OscAction = struct {
    // Borrowed parser-owned payload slice. Callers that retain it past the
    // next `Parser.next` call must copy.
    kind: OscKind,
    command: ?u16,
    payload: []const u8,
    term: OscTerminator,
};

pub const DcsHook = struct {
    // Borrowed parser-owned slices. Callers that retain them past the next
    // `Parser.next` call must copy.
    final: u8,
    params: []const i32,
    count: u8,
    intermediates: []const u8,
    intermediates_len: u8,
};

const CsiActionData = struct {
    // Borrowed parser-owned slices. Callers that retain them past the next
    // `Parser.next` call must copy.
    final: u8,
    params: []const i32,
    separators: CsiSeparatorList,
    count: u8,
    leader: u8,
    private: bool,
    intermediates: []const u8,
    intermediates_len: u8,
};

pub const CsiAction = CsiActionData;

pub const Action = union(enum) {
    print: u21,
    execute: u8,
    invalid,
    csi_dispatch: CsiAction,
    osc_dispatch: OscAction,
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
    csi_separators: CsiSeparatorList,
    csi_count: u8,
    intermediates: [csi_max_intermediates]u8,
    intermediates_len: u8,
    csi_in_param: bool,
    osc: string_control_mod.OscControl,
    apc: string_control_mod.PassthroughControl,
    dcs: string_control_mod.PassthroughControl,
    pm: string_control_mod.PassthroughControl,

    /// Initialize parser state and owned buffers.
    pub fn init(allocator: std.mem.Allocator) !Parser {
        var osc = try string_control_mod.OscControl.init(
            allocator,
            control_init_capacity,
            metadata_control_max_bytes,
            large_osc_control_max_bytes,
        );
        errdefer osc.deinit();

        return .{
            .utf8 = .{},
            .state = .ground,
            .csi_params = [_]i32{0} ** csi_max_params,
            .csi_separators = CsiSeparatorList.initEmpty(),
            .csi_count = 0,
            .intermediates = [_]u8{0} ** csi_max_intermediates,
            .intermediates_len = 0,
            .csi_in_param = false,
            .osc = osc,
            .apc = string_control_mod.PassthroughControl.init(false),
            .dcs = string_control_mod.PassthroughControl.init(false),
            .pm = string_control_mod.PassthroughControl.init(false),
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
        self.osc.reset();
        self.apc.reset();
        self.dcs.reset();
        self.pm.reset();
    }

    pub fn takeStringControlFailed(self: *Parser) ?error{ OutOfMemory, StringControlLimit } {
        if (self.osc.takeFailure()) |failure| return failure;
        return null;
    }

    /// Advance the parser by one byte and return ordered phase actions.
    pub fn next(self: *Parser, byte: u8) PhaseActions {
        std.debug.assert(self.activeControlCount() <= 1);
        if (self.state == .ground and self.utf8.needed > 0) {
            const action = self.consumeGroundByte(byte);
            return .{ null, action, null };
        }

        const transition = parse_table.table[byte][@intFromEnum(self.state)];
        if (self.isActiveState()) {
            return self.nextActive(byte, transition);
        }

        const transition_action = self.doAction(transition.action, byte);
        const next_state = transition.state;
        const current_state = self.state;
        defer self.state = next_state;

        return self.buildPhases(current_state, next_state, transition_action, byte, null);
    }

    fn nextActive(self: *Parser, byte: u8, transition: parse_table.Transition) PhaseActions {
        const current_state = self.state;
        const sos_kind = if (current_state == .sos_pm_apc_string) self.sosPmApcKind() else null;
        const finishing_escape = byte == '\\' and switch (current_state) {
            .osc_string => self.osc.escaping(),
            .dcs_passthrough => self.dcs.escaping(),
            .sos_pm_apc_string => switch (sos_kind.?) {
                .apc => self.apc.escaping(),
                .pm => self.pm.escaping(),
            },
            else => false,
        };

        if (byte != 0x1B and byte != 0x9C and !finishing_escape and (transition.state != current_state or transition.action != .none)) {
            const transition_action = self.doAction(transition.action, byte);
            defer self.state = transition.state;
            return self.buildPhases(current_state, transition.state, transition_action, byte, null);
        }

        const next_state, const action = self.feedActiveByte(current_state, sos_kind, byte);
        defer self.state = next_state;
        return self.buildPhases(current_state, next_state, action, byte, sos_kind);
    }

    fn feedActiveByte(self: *Parser, current_state: ParseState, sos_kind: ?BufferedControlKind, byte: u8) struct { ParseState, ?Action } {
        return switch (current_state) {
            .osc_string => osc: {
                const result = self.osc.feed(byte) orelse break :osc .{ .osc_string, null };
                break :osc switch (result) {
                    .put => .{ .osc_string, null },
                    .finish => .{ .ground, null },
                };
            },
            .dcs_passthrough => dcs: {
                const result = self.dcs.feed(byte) orelse break :dcs .{ .dcs_passthrough, null };
                break :dcs switch (result) {
                    .put => |payload_byte| .{ .dcs_passthrough, .{ .dcs_put = payload_byte } },
                    .finish => .{ .ground, null },
                };
            },
            .sos_pm_apc_string => switch (sos_kind.?) {
                .apc => apc: {
                    const result = self.apc.feed(byte) orelse break :apc .{ .sos_pm_apc_string, null };
                    break :apc switch (result) {
                        .put => |payload_byte| .{ .sos_pm_apc_string, .{ .apc_put = payload_byte } },
                        .finish => .{ .ground, null },
                    };
                },
                .pm => pm: {
                    const result = self.pm.feed(byte) orelse break :pm .{ .sos_pm_apc_string, null };
                    break :pm switch (result) {
                        .put => |payload_byte| .{ .sos_pm_apc_string, .{ .pm_put = payload_byte } },
                        .finish => .{ .ground, null },
                    };
                },
            },
            else => unreachable,
        };
    }

    fn collect(self: *Parser, byte: u8) void {
        if (self.intermediates_len >= self.intermediates.len) return;
        self.intermediates[self.intermediates_len] = byte;
        self.intermediates_len += 1;
    }

    fn buildPhases(self: *Parser, current_state: ParseState, next_state: ParseState, transition_action: ?Action, byte: u8, sos_kind: ?BufferedControlKind) PhaseActions {
        if (current_state == next_state) {
            return .{ null, transition_action, null };
        }

        return .{
            self.exitPhase(current_state, byte, sos_kind),
            transition_action,
            self.entryPhase(next_state, byte),
        };
    }

    fn exitPhase(self: *Parser, state: ParseState, byte: u8, sos_kind: ?BufferedControlKind) ?Action {
        return switch (state) {
            .osc_string => exit: {
                const term = switch (byte) {
                    0x07 => OscTerminator.bel,
                    '\\', 0x9C => OscTerminator.st,
                    else => break :exit null,
                };
                break :exit .{ .osc_dispatch = .{
                    .kind = self.osc.currentKind(),
                    .command = self.osc.currentCommand(),
                    .payload = self.osc.payload(),
                    .term = term,
                } };
            },
            .dcs_passthrough => dcs: {
                self.dcs.clearFinished();
                break :dcs .dcs_unhook;
            },
            .sos_pm_apc_string => switch (sos_kind orelse self.sosPmApcKind()) {
                .apc => apc: {
                    self.apc.clearFinished();
                    break :apc .apc_end;
                },
                .pm => pm: {
                    self.pm.clearFinished();
                    break :pm .pm_end;
                },
            },
            else => null,
        };
    }

    fn entryPhase(self: *Parser, state: ParseState, byte: u8) ?Action {
        return switch (state) {
            .escape, .csi_entry, .dcs_entry => entry: {
                if (state == .escape) {
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
                break :entry self.dcsHook(byte);
            },
            .sos_pm_apc_string => switch (byte) {
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
            },
            else => null,
        };
    }

    fn dcsHook(self: *Parser, byte: u8) Action {
        var final_count = self.csi_count;
        if (self.csi_in_param) final_count += 1;
        const hook = DcsHook{
            .final = byte,
            .params = self.csi_params[0..final_count],
            .count = final_count,
            .intermediates = self.intermediates[0..self.intermediates_len],
            .intermediates_len = self.intermediates_len,
        };
        return .{ .dcs_hook = hook };
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
                _ = self.osc.feed(byte);
                break :osc_put null;
            },
            .put => put: {
                const payload_byte = self.bufferedPut(&self.dcs, byte) orelse break :put null;
                break :put .{ .dcs_put = payload_byte };
            },
            .apc_put => apc_put: {
                break :apc_put switch (self.sosPmApcKind()) {
                    .apc => apc: {
                        const payload_byte = self.bufferedPut(&self.apc, byte) orelse break :apc null;
                        break :apc .{ .apc_put = payload_byte };
                    },
                    .pm => pm: {
                        const payload_byte = self.bufferedPut(&self.pm, byte) orelse break :pm null;
                        break :pm .{ .pm_put = payload_byte };
                    },
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

    fn bufferedPut(self: *Parser, control: anytype, byte: u8) ?u8 {
        _ = self;
        const result = control.feed(byte) orelse return null;
        return switch (result) {
            .put => |payload_byte| payload_byte,
            .finish => unreachable,
        };
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
        self.csi_separators = CsiSeparatorList.initEmpty();
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
                if (kind == .csi and byte == ':') self.csi_separators.set(self.csi_count);
                self.csi_count += 1;
                if (self.csi_count < self.csi_params.len) {
                    self.csi_params[self.csi_count] = 0;
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

        var leader: u8 = 0;
        var private = false;
        var intermediate_start: u8 = 0;
        if (self.intermediates_len > 0) {
            switch (self.intermediates[0]) {
                '<', '>', '=', '?' => {
                    leader = self.intermediates[0];
                    private = leader == '?';
                    intermediate_start = 1;
                },
                else => {},
            }
        }

        var final_count = self.csi_count;
        if (self.csi_in_param) final_count += 1;
        const intermediates_len = self.intermediates_len - intermediate_start;
        const action = CsiActionData{
            .final = byte,
            .params = self.csi_params[0..final_count],
            .separators = self.csi_separators,
            .count = final_count,
            .leader = leader,
            .private = private,
            .intermediates = self.intermediates[intermediate_start .. intermediate_start + intermediates_len],
            .intermediates_len = intermediates_len,
        };
        return .{ .csi_dispatch = action };
    }
};
