//! Private source root for deterministic parser and terminal simulations.

const parser_mod = @import("parser.zig");
const parser_owned_actions = @import("parser_owned_actions.zig");
const terminal_mod = @import("terminal.zig");

pub const Parser = parser_mod;
pub const ParserOwnedActions = parser_owned_actions;
pub const Terminal = terminal_mod.Terminal;
