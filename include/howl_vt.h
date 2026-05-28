#ifndef HOWL_VT_H
#define HOWL_VT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HowlVtTerminal HowlVtTerminal;
typedef HowlVtTerminal *HowlVtHandle;

/* Shell input enums. */
enum {
  HOWL_VT_MOD_NONE = 0,
  HOWL_VT_MOD_SHIFT = 1,
  HOWL_VT_MOD_ALT = 2,
  HOWL_VT_MOD_CTRL = 4,
};

enum {
  HOWL_VT_KEY_ENTER = 1,
  HOWL_VT_KEY_TAB = 2,
  HOWL_VT_KEY_BACKSPACE = 3,
  HOWL_VT_KEY_ESCAPE = 4,
  HOWL_VT_KEY_UP = 5,
  HOWL_VT_KEY_DOWN = 6,
  HOWL_VT_KEY_LEFT = 7,
  HOWL_VT_KEY_RIGHT = 8,
  HOWL_VT_KEY_INSERT = 9,
  HOWL_VT_KEY_DELETE = 10,
  HOWL_VT_KEY_HOME = 11,
  HOWL_VT_KEY_END = 12,
  HOWL_VT_KEY_PAGEUP = 13,
  HOWL_VT_KEY_PAGEDOWN = 14,
  HOWL_VT_KEY_F1 = 23,
  HOWL_VT_KEY_F2 = 24,
  HOWL_VT_KEY_F3 = 25,
  HOWL_VT_KEY_F4 = 26,
  HOWL_VT_KEY_F5 = 27,
  HOWL_VT_KEY_F6 = 28,
  HOWL_VT_KEY_F7 = 29,
  HOWL_VT_KEY_F8 = 30,
  HOWL_VT_KEY_F9 = 31,
  HOWL_VT_KEY_F10 = 32,
  HOWL_VT_KEY_F11 = 33,
  HOWL_VT_KEY_F12 = 34,
};

typedef enum {
  HOWL_VT_MOUSE_BUTTON_NONE = 0,
  HOWL_VT_MOUSE_BUTTON_LEFT = 1,
  HOWL_VT_MOUSE_BUTTON_MIDDLE = 2,
  HOWL_VT_MOUSE_BUTTON_RIGHT = 3,
  HOWL_VT_MOUSE_BUTTON_WHEEL_UP = 4,
  HOWL_VT_MOUSE_BUTTON_WHEEL_DOWN = 5,
} HowlVtMouseButton;

typedef enum {
  HOWL_VT_MOUSE_PRESS = 0,
  HOWL_VT_MOUSE_RELEASE = 1,
  HOWL_VT_MOUSE_MOVE = 2,
  HOWL_VT_MOUSE_WHEEL = 3,
} HowlVtMouseEventKind;

typedef enum {
  HOWL_VT_CALL_OK = 0,
  HOWL_VT_CALL_MISSING_HANDLE = -1,
  HOWL_VT_CALL_INVALID_ARGUMENT = -2,
  HOWL_VT_CALL_FAILED = -3,
  HOWL_VT_CALL_SHORT_BUFFER = -4,
  HOWL_VT_CALL_LIMIT_REACHED = -5,
} HowlVtCallStatus;

enum {
  HOWL_VT_TITLE_MAX_BYTES = 1024,
  HOWL_VT_PENDING_OUTPUT_MAX_BYTES = 1024 * 1024,
  HOWL_VT_CLIPBOARD_SCRATCH_MAX_BYTES = 1024 * 1024,
  HOWL_VT_INPUT_ENCODE_MAX_BYTES = 64,
};

/* -------------------------------------------------------------------------- */
/* 1. Surface + Dirty                                                          */
/* -------------------------------------------------------------------------- */

typedef struct {
  uint8_t continuation;
  uint8_t reserved0;
  uint8_t reserved1;
  uint8_t reserved2;
} HowlVtSurfaceCellFlags;

typedef struct {
  uint8_t kind;
  uint32_t value;
} HowlVtColor;

typedef struct {
  uint8_t r;
  uint8_t g;
  uint8_t b;
} HowlVtRgb8;

typedef struct {
  HowlVtRgb8 foreground;
  HowlVtRgb8 background;
  HowlVtRgb8 cursor;
  HowlVtRgb8 palette[256];
} HowlVtRenderColorState;

typedef struct {
  uint8_t bold;
  uint8_t dim;
  uint8_t italic;
  uint8_t underline;
  uint8_t underline_color_set;
  uint8_t blink;
  uint8_t inverse;
  uint8_t invisible;
  uint8_t strikethrough;
  uint8_t selected;
} HowlVtSurfaceCellAttrs;

typedef struct {
  uint32_t codepoint;
  uint8_t combining_len;
  uint8_t reserved0;
  uint8_t reserved1;
  uint8_t reserved2;
  uint32_t combining[3];
  HowlVtSurfaceCellFlags flags;
  HowlVtColor fg_color;
  HowlVtColor bg_color;
  HowlVtColor underline_color;
  uint8_t underline_style;
  uint8_t reserved3;
  uint8_t reserved4;
  uint8_t reserved5;
  HowlVtSurfaceCellAttrs attrs;
  uint32_t link_id;
} HowlVtSurfaceCell;

typedef struct {
  const HowlVtSurfaceCell *ptr;
  size_t len;
} HowlVtSurfaceCellSpan;

typedef struct {
  const uint8_t *ptr;
  size_t len;
} HowlVtByteSpan;

typedef struct {
  const uint16_t *ptr;
  size_t len;
} HowlVtU16Span;

typedef struct {
  uint16_t row;
  uint16_t col;
  uint8_t visible;
  uint8_t shape;
  uint8_t blink;
} HowlVtCursor;

typedef struct {
  uint8_t shape;
  uint8_t blink;
} HowlVtCursorStyle;

typedef struct {
  int32_t row;
  uint16_t col;
  uint16_t reserved0;
} HowlVtSelectionPos;

typedef struct {
  uint8_t active;
  uint8_t selecting;
  uint16_t reserved0;
  HowlVtSelectionPos start;
  HowlVtSelectionPos end;
} HowlVtSelection;

typedef struct {
  int32_t status;
  HowlVtSelection selection;
} HowlVtSelectionResult;

typedef struct {
  HowlVtCursorStyle default_cursor_style;
} HowlVtTerminalInitOptions;

typedef struct {
  HowlVtSurfaceCellSpan surface_cells;
  uint16_t cols;
  uint16_t rows;
  uint64_t scroll_row;
  uint8_t is_alternate_screen;
  uint8_t reserved0;
  uint16_t reserved1;
  HowlVtByteSpan dirty_rows;
  HowlVtU16Span dirty_cols_start;
  HowlVtU16Span dirty_cols_end;
  HowlVtCursor cursor;
  HowlVtRenderColorState colors;
  HowlVtSelection selection;
} HowlVtSurface;

typedef struct {
  uint16_t rows;
  uint16_t cols;
  uint64_t history_count;
  uint8_t is_alternate_screen;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t snapshot_seq;
  uint64_t dirty_generation;
} HowlVtVisibleMeta;

typedef struct {
  int32_t status;
  HowlVtVisibleMeta meta;
} HowlVtVisibleMetaResult;

typedef struct {
  uint32_t image_count;
  uint32_t placement_count;
  uint32_t virtual_placement_count;
  uint32_t placeholder_run_count;
  uint8_t is_alternate_screen;
  uint8_t reserved0;
  uint64_t publication_seq;
  uint64_t dirty_generation;
} HowlVtGraphicsMeta;

typedef struct {
  int32_t status;
  HowlVtGraphicsMeta meta;
} HowlVtGraphicsMetaResult;

enum {
  HOWL_VT_GRAPHICS_ROW_ANCHOR_ON_SCREEN = 1,
  HOWL_VT_GRAPHICS_ROW_ANCHOR_SCROLLBACK_ABOVE = 2,
  HOWL_VT_GRAPHICS_ROW_ANCHOR_BELOW_SCREEN = 3,
};

enum {
  HOWL_VT_GRAPHICS_PLACEMENT_GENERATED_PLACEHOLDER = 1u,
};

typedef struct {
  uint8_t kind;
  uint8_t reserved0;
  uint16_t reserved1;
  uint32_t value;
} HowlVtGraphicsRowAnchor;

typedef struct {
  uint32_t image_id;
  uint32_t image_ref_id;
  uint32_t image_number;
  uint16_t format;
  uint16_t reserved0;
  uint32_t width;
  uint32_t height;
  uint64_t payload_len;
} HowlVtGraphicsImage;

/* Graphics payload bytes are exposed exactly as VT retains them today.
 * They are protocol payload bytes, not decoded/render-ready image bytes. */

typedef struct {
  int32_t status;
  HowlVtGraphicsImage image;
} HowlVtGraphicsImageResult;

typedef struct {
  uint32_t image_id;
  uint32_t placement_id;
  int32_t z_index;
  HowlVtGraphicsRowAnchor anchor;
  uint16_t anchor_col;
  uint16_t reserved0;
  uint32_t source_x;
  uint32_t source_y;
  uint32_t source_width;
  uint32_t source_height;
  uint32_t cell_x_offset;
  uint32_t cell_y_offset;
  uint32_t columns;
  uint32_t rows;
  uint32_t dest_left_cell_px;
  uint32_t dest_top_cell_px;
  uint32_t dest_right_cell_px;
  uint32_t dest_bottom_cell_px;
  uint32_t dest_grid_columns;
  uint32_t dest_grid_rows;
  uint32_t effective_columns;
  uint32_t effective_rows;
  uint32_t flags;
  uint64_t render_order_key;
} HowlVtGraphicsPlacement;

typedef struct {
  int32_t status;
  HowlVtGraphicsPlacement placement;
} HowlVtGraphicsPlacementResult;

typedef struct {
  uint32_t image_id;
  uint32_t placement_id;
  uint32_t source_x;
  uint32_t source_y;
  uint32_t source_width;
  uint32_t source_height;
  uint32_t columns;
  uint32_t rows;
} HowlVtGraphicsVirtualPlacement;

typedef struct {
  int32_t status;
  HowlVtGraphicsVirtualPlacement placement;
} HowlVtGraphicsVirtualPlacementResult;

typedef struct {
  uint32_t image_id;
  uint32_t placement_id;
  uint32_t virtual_placement_index;
  uint32_t run_order;
  uint16_t cell_row;
  uint16_t cell_col;
  uint32_t reserved0;
  uint32_t image_row;
  uint32_t image_col;
  uint32_t columns;
} HowlVtGraphicsPlaceholderRun;

typedef struct {
  int32_t status;
  HowlVtGraphicsPlaceholderRun run;
} HowlVtGraphicsPlaceholderRunResult;

typedef struct {
  int32_t status;
  uint64_t history_count;
  uint64_t scrollback_offset;
  uint64_t snapshot_seq;
  uint64_t dirty_generation;
  HowlVtSurface source;
} HowlVtSurfaceResult;

int32_t howl_vt_terminal_resize(HowlVtHandle handle, uint16_t rows, uint16_t cols);
int32_t howl_vt_terminal_set_cell_pixel_size(HowlVtHandle handle, uint32_t width, uint32_t height);
int32_t howl_vt_terminal_ack_surface(HowlVtHandle handle, uint64_t snapshot_seq);
HowlVtVisibleMetaResult howl_vt_terminal_query_visible_meta(HowlVtHandle handle, uint64_t scrollback_offset);
HowlVtGraphicsMetaResult howl_vt_terminal_query_graphics_meta(HowlVtHandle handle);
HowlVtGraphicsImageResult howl_vt_terminal_query_graphics_image(HowlVtHandle handle, uint64_t publication_seq, uint32_t image_index);
HowlVtGraphicsPlacementResult howl_vt_terminal_query_graphics_placement(HowlVtHandle handle, uint64_t publication_seq, uint32_t placement_index);
HowlVtGraphicsPlaceholderRunResult howl_vt_terminal_query_graphics_placeholder_run(HowlVtHandle handle, uint64_t publication_seq, uint32_t run_index);
HowlVtGraphicsVirtualPlacementResult howl_vt_terminal_query_graphics_virtual_placement(HowlVtHandle handle, uint64_t publication_seq, uint32_t placement_index);
HowlVtSurfaceResult howl_vt_terminal_copy_surface(HowlVtHandle handle, uint64_t scrollback_offset, HowlVtSurfaceCell *cells_ptr, size_t cells_cap, uint8_t *dirty_rows_ptr, size_t dirty_rows_cap, uint16_t *cols_start_ptr, size_t cols_start_cap, uint16_t *cols_end_ptr, size_t cols_end_cap);
HowlVtSelectionResult howl_vt_terminal_query_selection(HowlVtHandle handle);
int32_t howl_vt_terminal_start_selection(HowlVtHandle handle, int32_t row, uint16_t col);
int32_t howl_vt_terminal_update_selection(HowlVtHandle handle, int32_t row, uint16_t col);
int32_t howl_vt_terminal_finish_selection(HowlVtHandle handle);
int32_t howl_vt_terminal_clear_selection(HowlVtHandle handle);

/* -------------------------------------------------------------------------- */
/* 2. Protocol Metadata Host Output                                            */
/* -------------------------------------------------------------------------- */

typedef struct {
  int32_t status;
  uint64_t written;
  uint64_t needed;
} HowlVtBytesResult;

typedef struct {
  int32_t status;
  uint8_t state_changed;
  uint8_t title_changed;
  uint16_t reserved0;
} HowlVtFeedResult;

typedef struct {
  uint8_t pending_now;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t deadline_ns;
} HowlVtRuntimeObligation;

typedef struct {
  int32_t status;
  HowlVtRuntimeObligation obligation;
} HowlVtRuntimeObligationResult;

typedef struct {
  int32_t status;
  uint8_t state_changed;
  uint8_t reserved0;
  uint16_t reserved1;
  HowlVtRuntimeObligation obligation;
} HowlVtRuntimeProgressResult;

HowlVtHandle howl_vt_terminal_init(uint16_t rows, uint16_t cols, uint16_t history_capacity);
HowlVtHandle howl_vt_terminal_init_with_options(uint16_t rows, uint16_t cols, uint16_t history_capacity, HowlVtTerminalInitOptions options);
void howl_vt_terminal_deinit(HowlVtHandle handle);
HowlVtFeedResult howl_vt_terminal_feed(HowlVtHandle handle, const uint8_t *ptr, size_t len);
/* Graphics item queries and payload copies are publication-local.
 * Callers must first read `howl_vt_terminal_query_graphics_meta()` and pass the
 * returned `publication_seq` back to per-item queries/copies.
 *
 * Surface publication and graphics publication are separate today:
 * - `howl_vt_terminal_copy_surface()` yields a visible-surface `snapshot_seq`
 * - `howl_vt_terminal_query_graphics_meta()` yields a graphics `publication_seq`
 *
 * Graphics publication is conservative and may advance on any terminal mutation,
 * not only graphics-local changes. Callers that need one coherent acquisition of
 * visible text plus graphics must:
 * 1. copy the surface snapshot,
 * 2. query graphics meta,
 * 3. use that returned graphics `publication_seq` for item queries/copies, and
 * 4. restart acquisition if any graphics item query reports invalid publication.
 *
 * Do not mix item data from different graphics publication sequences. */
HowlVtBytesResult howl_vt_terminal_copy_surface_hyperlink(HowlVtHandle handle, uint64_t scrollback_offset, uint64_t snapshot_seq, uint16_t row, uint16_t col, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_copy_graphics_payload(HowlVtHandle handle, uint64_t publication_seq, uint32_t image_index, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_copy_selection(HowlVtHandle handle, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_copy_title(HowlVtHandle handle, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_copy_pending_output(HowlVtHandle handle, uint8_t *ptr, size_t cap);
void howl_vt_terminal_clear_pending_output(HowlVtHandle handle);
HowlVtBytesResult howl_vt_terminal_drain_pending_clipboard(HowlVtHandle handle, uint8_t *ptr, size_t cap);

/* -------------------------------------------------------------------------- */
/* 3. Runtime Obligation                                                       */
/* -------------------------------------------------------------------------- */

HowlVtRuntimeObligationResult howl_vt_terminal_query_runtime_obligation(HowlVtHandle handle, uint64_t now_ns);
HowlVtRuntimeProgressResult howl_vt_terminal_progress_runtime(HowlVtHandle handle, uint64_t now_ns);
int32_t howl_vt_terminal_note_drawn_graphics(HowlVtHandle handle, uint64_t publication_seq, const uint32_t *image_ref_ids, size_t count);

/* -------------------------------------------------------------------------- */
/* 4. Shell Input                                                              */
/* -------------------------------------------------------------------------- */

HowlVtBytesResult howl_vt_terminal_encode_key(HowlVtHandle handle, uint32_t key, uint8_t mods, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_encode_focus(HowlVtHandle handle, uint8_t focused, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_encode_paste_start(HowlVtHandle handle, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_encode_paste_end(HowlVtHandle handle, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_encode_mouse(
    HowlVtHandle handle,
    uint8_t kind,
    uint8_t button,
    int32_t row,
    uint16_t col,
    uint8_t pixel_x_valid,
    uint32_t pixel_x,
    uint8_t pixel_y_valid,
    uint32_t pixel_y,
    uint8_t mods,
    uint8_t buttons_down,
    uint8_t *ptr,
    size_t cap);
HowlVtBytesResult howl_vt_terminal_encode_paste(HowlVtHandle handle, const uint8_t *text_ptr, size_t text_len, uint8_t *ptr, size_t cap);

#ifdef __cplusplus
}
#endif

#endif
