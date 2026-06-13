const ffi = @import("src/ffi/main.zig");

pub const FfiBytesResult = ffi.FfiBytesResult;
pub const FfiFeedResult = ffi.FfiFeedResult;
pub const FfiVisibleMetaResult = ffi.FfiVisibleMetaResult;
pub const FfiRuntimeObligationResult = ffi.FfiRuntimeObligationResult;
pub const FfiRuntimeProgressResult = ffi.FfiRuntimeProgressResult;
pub const FfiSelectionResult = ffi.FfiSelectionResult;
pub const HowlVtCallStatus = ffi.HowlVtCallStatus;

pub const terminalInit = ffi.terminalInit;
pub const terminalInitWithOptions = ffi.terminalInitWithOptions;
pub const terminalDeinit = ffi.terminalDeinit;
pub const terminalResize = ffi.terminalResize;
pub const terminalSetCellPixelSize = ffi.terminalSetCellPixelSize;
pub const terminalAckSurface = ffi.terminalAckSurface;
pub const terminalStartSelection = ffi.terminalStartSelection;
pub const terminalFeed = ffi.terminalFeed;
pub const terminalCopyTitle = ffi.terminalCopyTitle;
pub const terminalQueryVisibleMeta = ffi.terminalQueryVisibleMeta;
pub const terminalQuerySelection = ffi.terminalQuerySelection;
pub const terminalQueryRuntimeObligation = ffi.terminalQueryRuntimeObligation;
pub const terminalProgressRuntime = ffi.terminalProgressRuntime;
pub const terminalEncodeKey = ffi.terminalEncodeKey;
