const std = @import("std");
const host_state = @import("../host_state.zig");
const input_encode = @import("../input/encode.zig");

const bytes = @import("bytes.zig");
const handle = @import("handle.zig");
const host_output = @import("host_output.zig");
const input = @import("input.zig");
const lifecycle = @import("lifecycle.zig");
const runtime = @import("runtime.zig");
const selection = @import("selection.zig");
const status = @import("status.zig");
const surface = @import("surface.zig");

pub const HowlVtCallStatus = status.HowlVtCallStatus;
pub const HowlVtTerminal = handle.HowlVtTerminal;
pub const VtHandle = handle.VtHandle;

pub const FfiByteSpan = bytes.FfiByteSpan;
pub const FfiBytesResult = bytes.FfiBytesResult;
pub const FfiU16Span = bytes.FfiU16Span;

pub const FfiFeedResult = lifecycle.FfiFeedResult;
pub const FfiCursorStyle = lifecycle.FfiCursorStyle;
pub const FfiTerminalInitOptions = lifecycle.FfiTerminalInitOptions;

pub const FfiColor = surface.FfiColor;
pub const FfiCursor = surface.FfiCursor;
pub const FfiRenderColorState = surface.FfiRenderColorState;
pub const FfiRgb8 = surface.FfiRgb8;
pub const FfiSurface = surface.FfiSurface;
pub const FfiSurfaceCell = surface.FfiSurfaceCell;
pub const FfiSurfaceCellAttrs = surface.FfiSurfaceCellAttrs;
pub const FfiSurfaceCellFlags = surface.FfiSurfaceCellFlags;
pub const FfiSurfaceCellSpan = surface.FfiSurfaceCellSpan;
pub const FfiSurfaceResult = surface.FfiSurfaceResult;
pub const FfiVisibleMeta = surface.FfiVisibleMeta;
pub const FfiVisibleMetaResult = surface.FfiVisibleMetaResult;

pub const FfiSelection = selection.FfiSelection;
pub const FfiSelectionPos = selection.FfiSelectionPos;
pub const FfiSelectionResult = selection.FfiSelectionResult;

pub const FfiRuntimeObligation = runtime.FfiRuntimeObligation;
pub const FfiRuntimeObligationResult = runtime.FfiRuntimeObligationResult;
pub const FfiRuntimeProgressResult = runtime.FfiRuntimeProgressResult;

pub const terminalInit = lifecycle.terminalInit;
pub const terminalInitWithOptions = lifecycle.terminalInitWithOptions;
pub const terminalDeinit = lifecycle.terminalDeinit;
pub const terminalFeed = lifecycle.terminalFeed;
pub const terminalCopyTitle = lifecycle.terminalCopyTitle;
pub const terminalResize = lifecycle.terminalResize;
pub const terminalSetCellPixelSize = lifecycle.terminalSetCellPixelSize;

pub const terminalAckSurface = surface.terminalAckSurface;
pub const terminalQueryVisibleMeta = surface.terminalQueryVisibleMeta;
pub const terminalCopySurface = surface.terminalCopySurface;
pub const terminalCopySurfaceHyperlink = surface.terminalCopySurfaceHyperlink;

pub const terminalQuerySelection = selection.terminalQuerySelection;
pub const terminalStartSelection = selection.terminalStartSelection;
pub const terminalUpdateSelection = selection.terminalUpdateSelection;
pub const terminalFinishSelection = selection.terminalFinishSelection;
pub const terminalClearSelection = selection.terminalClearSelection;
pub const terminalCopySelection = selection.terminalCopySelection;

pub const terminalCopyPendingOutput = host_output.terminalCopyPendingOutput;
pub const terminalClearPendingOutput = host_output.terminalClearPendingOutput;
pub const terminalDrainPendingClipboard = host_output.terminalDrainPendingClipboard;

pub const terminalQueryRuntimeObligation = runtime.terminalQueryRuntimeObligation;
pub const terminalProgressRuntime = runtime.terminalProgressRuntime;

pub const terminalEncodeKey = input.terminalEncodeKey;
pub const terminalEncodeFocus = input.terminalEncodeFocus;
pub const terminalEncodePasteStart = input.terminalEncodePasteStart;
pub const terminalEncodePasteEnd = input.terminalEncodePasteEnd;
pub const terminalEncodeMouse = input.terminalEncodeMouse;
pub const terminalEncodePaste = input.terminalEncodePaste;

comptime {
    std.debug.assert(host_state.title_max_bytes == 1024);
    std.debug.assert(host_state.pending_output_max_bytes == 1024 * 1024);
    std.debug.assert(host_state.retained_payload_max_bytes == 1024 * 1024);
    std.debug.assert(@sizeOf(input_encode.Scratch) == 64);
    std.debug.assert(@sizeOf(FfiRgb8) == 3);
    std.debug.assert(@sizeOf(FfiRenderColorState) == 777);
}

test {
    _ = bytes;
    _ = handle;
    _ = host_output;
    _ = input;
    _ = lifecycle;
    _ = runtime;
    _ = selection;
    _ = status;
    _ = surface;
}
