//! Responsibility: export the parser domain owner surface.
//! Ownership: parser package boundary.
//! Reason: keep one canonical owner for stream decoding and parser state machines.

const parser = @import("parser/parser.zig");
const stream = @import("parser/stream.zig");
const csi = @import("parser/csi.zig");
const string_control = @import("parser/string_control.zig");

/// Canonical parser domain owner.
pub const ParserApi = struct {
    /// Main terminal parser.
    pub const Parser = parser.Parser;
    /// Parser event sink contract.
    pub const Sink = parser.Sink;
    /// OSC terminator enum.
    pub const OscTerminator = parser.OscTerminator;

    /// Byte-stream owner.
    pub const Stream = stream.Stream;
    /// Stream event payload.
    pub const StreamEvent = stream.StreamEvent;

    /// CSI action enum.
    pub const CsiAction = csi.CsiAction;
    /// CSI parser owner.
    pub const CsiParser = csi.CsiParser;
    /// String-control parser helper.
    pub const StringControl = string_control.StringControl;
    /// Maximum supported CSI parameter count.
    pub const max_params = csi.max_params;
    /// Maximum supported CSI intermediate count.
    pub const max_intermediates = csi.max_intermediates;
};
