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
const render_state = @import("render_state.zig");
const hyperlink = @import("hyperlink.zig");
const visible_info = @import("visible_info.zig");

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
pub const FfiVisibleInfo = visible_info.FfiVisibleInfo;
pub const FfiVisibleInfoResult = visible_info.FfiVisibleInfoResult;

pub const FfiSelection = selection.FfiSelection;
pub const FfiSelectionPos = selection.FfiSelectionPos;
pub const FfiSelectionResult = selection.FfiSelectionResult;

pub const FfiRuntimeObligation = runtime.FfiRuntimeObligation;
pub const FfiRuntimeObligationResult = runtime.FfiRuntimeObligationResult;
pub const FfiRuntimeProgressResult = runtime.FfiRuntimeProgressResult;

pub const FfiRenderState = render_state.FfiRenderState;
pub const FfiRenderStateHandle = render_state.FfiRenderStateHandle;
pub const FfiRowIterator = render_state.FfiRowIterator;
pub const FfiRowIteratorHandle = render_state.FfiRowIteratorHandle;
pub const FfiRowCells = render_state.FfiRowCells;
pub const FfiRowCellsHandle = render_state.FfiRowCellsHandle;
pub const FfiDirty = render_state.FfiDirty;
pub const FfiCursorVisualStyle = render_state.FfiCursorVisualStyle;
pub const FfiData = render_state.FfiData;
pub const FfiOption = render_state.FfiOption;
pub const FfiRowData = render_state.FfiRowData;
pub const FfiRowOption = render_state.FfiRowOption;
pub const FfiRowCellsData = render_state.FfiRowCellsData;
pub const FfiRowSelection = render_state.FfiRowSelection;
pub const FfiRowHighlight = render_state.FfiRowHighlight;
pub const FfiRenderStateColor = render_state.FfiRenderStateColor;
pub const FfiRenderStateRgb8 = render_state.FfiRenderStateRgb8;
pub const FfiRenderStateCellFlags = render_state.FfiRenderStateCellFlags;
pub const FfiRenderStateCellAttrs = render_state.FfiRenderStateCellAttrs;
pub const FfiRenderStateCell = render_state.FfiRenderStateCell;
pub const FfiColors = render_state.FfiColors;

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
pub const terminalQueryVisibleInfo = visible_info.terminalQueryVisibleInfo;
pub const terminalCopyVisibleHyperlink = hyperlink.terminalCopyVisibleHyperlink;

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

pub const renderStateInit = render_state.renderStateInit;
pub const renderStateDeinit = render_state.renderStateDeinit;
pub const renderStateUpdate = render_state.renderStateUpdate;
pub const renderStateAck = render_state.renderStateAck;
pub const renderStateUpdateHighlightsForHyperlink = render_state.renderStateUpdateHighlightsForHyperlink;
pub const renderStateGet = render_state.renderStateGet;
pub const renderStateGetMulti = render_state.renderStateGetMulti;
pub const renderStateSet = render_state.renderStateSet;
pub const renderStateColorsGet = render_state.renderStateColorsGet;
pub const renderStateRowIteratorInit = render_state.renderStateRowIteratorInit;
pub const renderStateRowIteratorDeinit = render_state.renderStateRowIteratorDeinit;
pub const renderStateRowIteratorNext = render_state.renderStateRowIteratorNext;
pub const renderStateRowGet = render_state.renderStateRowGet;
pub const renderStateRowGetMulti = render_state.renderStateRowGetMulti;
pub const renderStateRowSet = render_state.renderStateRowSet;
pub const renderStateRowCellsInit = render_state.renderStateRowCellsInit;
pub const renderStateRowCellsDeinit = render_state.renderStateRowCellsDeinit;
pub const renderStateRowCellsNext = render_state.renderStateRowCellsNext;
pub const renderStateRowCellsSelect = render_state.renderStateRowCellsSelect;
pub const renderStateRowCellsGet = render_state.renderStateRowCellsGet;
pub const renderStateRowCellsGetMulti = render_state.renderStateRowCellsGetMulti;

comptime {
    std.debug.assert(host_state.title_max_bytes == 1024);
    std.debug.assert(host_state.pending_output_max_bytes == 1024 * 1024);
    std.debug.assert(host_state.retained_payload_max_bytes == 1024 * 1024);
    std.debug.assert(@sizeOf(input_encode.Scratch) == 64);
    std.debug.assert(@sizeOf(FfiRgb8) == 3);
    std.debug.assert(@sizeOf(FfiVisibleInfo) == 40);
    std.debug.assert(@alignOf(FfiVisibleInfo) == 8);
    std.debug.assert(@sizeOf(FfiVisibleInfoResult) == 48);
    std.debug.assert(@alignOf(FfiVisibleInfoResult) == 8);
    std.debug.assert(@sizeOf(FfiRenderStateRgb8) == 3);
    std.debug.assert(@sizeOf(FfiRenderStateColor) == 8);
    std.debug.assert(@sizeOf(FfiRenderStateCellFlags) == 4);
    std.debug.assert(@sizeOf(FfiRenderStateCellAttrs) == 10);
    std.debug.assert(@sizeOf(FfiRenderStateCell) == 68);
    std.debug.assert(@sizeOf(FfiRenderColorState) == 777);
    std.debug.assert(@sizeOf(FfiColors) == 792);
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
    _ = render_state;
}
