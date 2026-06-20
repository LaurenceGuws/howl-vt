#ifndef HOWL_VT_H
#define HOWL_VT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct HowlVtTerminal HowlVtTerminal;
typedef HowlVtTerminal *HowlVtHandle;

enum {
    HOWL_VT_TITLE_MAX_BYTES = 1024,
    HOWL_VT_PENDING_OUTPUT_MAX_BYTES = 1024 * 1024,
    HOWL_VT_CLIPBOARD_SCRATCH_MAX_BYTES = 1024 * 1024,
    HOWL_VT_INPUT_ENCODE_MAX_BYTES = 64,
    HOWL_VT_MAX_EXTRA_CURSORS = 256,
};

typedef enum {
    HOWL_VT_CALL_OK = 0,
    HOWL_VT_CALL_MISSING_HANDLE = -1,
    HOWL_VT_CALL_INVALID_ARGUMENT = -2,
    HOWL_VT_CALL_FAILED = -3,
    HOWL_VT_CALL_SHORT_BUFFER = -4,
    HOWL_VT_CALL_LIMIT_REACHED = -5,
    HOWL_VT_CALL_NO_VALUE = -6,
} HowlVtCallStatus;

typedef struct HowlVtRenderState HowlVtRenderState;
typedef HowlVtRenderState *HowlVtRenderStateHandle;
typedef struct HowlVtRenderStateRowIterator HowlVtRenderStateRowIterator;
typedef HowlVtRenderStateRowIterator *HowlVtRenderStateRowIteratorHandle;
typedef struct HowlVtRenderStateRowCells HowlVtRenderStateRowCells;
typedef HowlVtRenderStateRowCells *HowlVtRenderStateRowCellsHandle;

typedef enum {
    HOWL_VT_RENDER_STATE_DIRTY_FALSE = 0,
    HOWL_VT_RENDER_STATE_DIRTY_PARTIAL = 1,
    HOWL_VT_RENDER_STATE_DIRTY_FULL = 2,
} HowlVtRenderStateDirty;

typedef enum {
    HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_BAR = 0,
    HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK = 1,
    HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_UNDERLINE = 2,
    HOWL_VT_RENDER_STATE_CURSOR_VISUAL_STYLE_BLOCK_HOLLOW = 3,
} HowlVtRenderStateCursorVisualStyle;

typedef enum {
    HOWL_VT_RENDER_STATE_DATA_INVALID = 0,
    HOWL_VT_RENDER_STATE_DATA_COLS = 1,
    HOWL_VT_RENDER_STATE_DATA_ROWS = 2,
    HOWL_VT_RENDER_STATE_DATA_DIRTY = 3,
    HOWL_VT_RENDER_STATE_DATA_ROW_ITERATOR = 4,
    HOWL_VT_RENDER_STATE_DATA_COLOR_BACKGROUND = 5,
    HOWL_VT_RENDER_STATE_DATA_COLOR_FOREGROUND = 6,
    HOWL_VT_RENDER_STATE_DATA_COLOR_CURSOR = 7,
    HOWL_VT_RENDER_STATE_DATA_COLOR_CURSOR_HAS_VALUE = 8,
    HOWL_VT_RENDER_STATE_DATA_COLOR_PALETTE = 9,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE = 10,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_VISIBLE = 11,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_BLINKING = 12,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_HAS_VALUE = 13,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_X = 14,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_Y = 15,
    HOWL_VT_RENDER_STATE_DATA_CURSOR_VIEWPORT_WIDE_TAIL = 16,
    HOWL_VT_RENDER_STATE_DATA_SNAPSHOT_SEQ = 17,
    HOWL_VT_RENDER_STATE_DATA_DIRTY_GENERATION = 18,
    HOWL_VT_RENDER_STATE_DATA_HISTORY_COUNT = 19,
    HOWL_VT_RENDER_STATE_DATA_SCROLLBACK_OFFSET = 20,
    HOWL_VT_RENDER_STATE_DATA_SCROLL_ROW = 21,
    HOWL_VT_RENDER_STATE_DATA_IS_ALTERNATE_SCREEN = 22,
} HowlVtRenderStateData;

typedef enum { HOWL_VT_RENDER_STATE_OPTION_DIRTY = 0 } HowlVtRenderStateOption;

typedef enum {
    HOWL_VT_RENDER_STATE_ROW_DATA_INVALID = 0,
    HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY = 1,
    HOWL_VT_RENDER_STATE_ROW_DATA_CELLS = 2,
    HOWL_VT_RENDER_STATE_ROW_DATA_SELECTION = 3,
    HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT_COUNT = 4,
    HOWL_VT_RENDER_STATE_ROW_DATA_HIGHLIGHT = 5,
    HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_START = 6,
    HOWL_VT_RENDER_STATE_ROW_DATA_DIRTY_COL_END = 7,
} HowlVtRenderStateRowData;

typedef enum { HOWL_VT_RENDER_STATE_ROW_OPTION_DIRTY = 0 } HowlVtRenderStateRowOption;

typedef enum {
    HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_INVALID = 0,
    HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_CELL = 1,
    HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_SELECTED = 2,
    HOWL_VT_RENDER_STATE_ROW_CELLS_DATA_HIGHLIGHTED = 3,
} HowlVtRenderStateRowCellsData;

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
    uint8_t continuation;
    uint8_t reserved0;
    uint8_t reserved1;
    uint8_t reserved2;
} HowlVtRenderStateCellFlags;

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
    uint8_t reserved0;
} HowlVtRenderStateCellAttrs;

typedef struct {
    uint32_t codepoint;
    uint8_t combining_len;
    uint8_t reserved0;
    uint8_t reserved1;
    uint8_t reserved2;
    uint32_t combining[3];
    HowlVtRenderStateCellFlags flags;
    HowlVtColor fg_color;
    HowlVtColor bg_color;
    HowlVtColor underline_color;
    uint8_t underline_style;
    uint8_t reserved3;
    uint8_t reserved4;
    uint8_t reserved5;
    HowlVtRenderStateCellAttrs attrs;
    uint16_t reserved6;
    uint32_t link_id;
} HowlVtRenderStateCell;

typedef struct {
    size_t size;
    uint16_t start_col;
    uint16_t end_col;
} HowlVtRenderStateRowSelection;

typedef struct {
    size_t size;
    uint8_t tag;
    uint8_t reserved0;
    uint16_t index;
    uint16_t start_col;
    uint16_t end_col;
} HowlVtRenderStateRowHighlight;

typedef struct {
    size_t size;
    HowlVtRgb8 background;
    HowlVtRgb8 foreground;
    HowlVtRgb8 cursor;
    uint8_t cursor_has_value;
    uint8_t reserved0;
    uint16_t reserved1;
    HowlVtRgb8 palette[256];
} HowlVtRenderStateColors;

enum {
    HOWL_VT_CURSOR_SHAPE_BLOCK = 0,
    HOWL_VT_CURSOR_SHAPE_UNDERLINE = 1,
    HOWL_VT_CURSOR_SHAPE_BEAM = 2,
    HOWL_VT_CURSOR_SHAPE_NONE = 3,
};

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
    int32_t status;
    uint64_t written;
    uint64_t needed;
} HowlVtBytesResult;

typedef struct {
    uint32_t rows;
    uint32_t cols;
    uint64_t history_count;
    uint64_t scrollback_offset;
    uint8_t is_alternate_screen;
    uint8_t reserved0;
    uint16_t reserved1;
    uint64_t snapshot_seq;
    uint64_t dirty_generation;
} HowlVtVisibleInfo;

typedef struct {
    int32_t status;
    uint32_t reserved0;
    HowlVtVisibleInfo info;
} HowlVtVisibleInfoResult;

typedef enum {
    HOWL_VT_SCROLL_VIEWPORT_TOP = 0,
    HOWL_VT_SCROLL_VIEWPORT_BOTTOM = 1,
    HOWL_VT_SCROLL_VIEWPORT_DELTA = 2,
    HOWL_VT_SCROLL_VIEWPORT_ABSOLUTE = 3,
} HowlVtScrollViewportKind;

typedef struct {
    int32_t status;
    uint8_t changed;
    uint8_t reserved0;
    uint16_t reserved1;
} HowlVtScrollViewportResult;

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

HowlVtCallStatus howl_vt_render_state_init(HowlVtRenderStateHandle *out_state);
void howl_vt_render_state_deinit(HowlVtRenderStateHandle state);
HowlVtCallStatus howl_vt_render_state_update(
    HowlVtRenderStateHandle state,
    HowlVtHandle terminal
);
HowlVtCallStatus howl_vt_render_state_ack(HowlVtRenderStateHandle state, HowlVtHandle terminal);
HowlVtCallStatus howl_vt_render_state_update_highlights_for_hyperlink(
    HowlVtRenderStateHandle state,
    uint8_t tag,
    uint16_t row,
    uint16_t col,
    uint8_t underline_style
);
HowlVtCallStatus howl_vt_render_state_get(
    HowlVtRenderStateHandle state,
    HowlVtRenderStateData data,
    void *out
);
HowlVtCallStatus howl_vt_render_state_get_multi(
    HowlVtRenderStateHandle state,
    size_t count,
    const HowlVtRenderStateData *keys,
    void **values,
    size_t *out_written
);
HowlVtCallStatus howl_vt_render_state_set(
    HowlVtRenderStateHandle state,
    HowlVtRenderStateOption option,
    const void *value
);
HowlVtCallStatus howl_vt_render_state_colors_get(
    HowlVtRenderStateHandle state,
    HowlVtRenderStateColors *out_colors
);
HowlVtCallStatus howl_vt_render_state_row_iterator_init(
    HowlVtRenderStateRowIteratorHandle *out_iterator
);
void howl_vt_render_state_row_iterator_deinit(HowlVtRenderStateRowIteratorHandle iterator);
uint8_t howl_vt_render_state_row_iterator_next(HowlVtRenderStateRowIteratorHandle iterator);
HowlVtCallStatus howl_vt_render_state_row_get(
    HowlVtRenderStateRowIteratorHandle iterator,
    HowlVtRenderStateRowData data,
    void *out
);
HowlVtCallStatus howl_vt_render_state_row_get_multi(
    HowlVtRenderStateRowIteratorHandle iterator,
    size_t count,
    const HowlVtRenderStateRowData *keys,
    void **values,
    size_t *out_written
);
HowlVtCallStatus howl_vt_render_state_row_set(
    HowlVtRenderStateRowIteratorHandle iterator,
    HowlVtRenderStateRowOption option,
    const void *value
);
HowlVtCallStatus howl_vt_render_state_row_cells_init(HowlVtRenderStateRowCellsHandle *out_cells);
void howl_vt_render_state_row_cells_deinit(HowlVtRenderStateRowCellsHandle cells);
uint8_t howl_vt_render_state_row_cells_next(HowlVtRenderStateRowCellsHandle cells);
HowlVtCallStatus howl_vt_render_state_row_cells_select(HowlVtRenderStateRowCellsHandle cells, uint16_t col);
HowlVtCallStatus howl_vt_render_state_row_cells_get(
    HowlVtRenderStateRowCellsHandle cells,
    HowlVtRenderStateRowCellsData data,
    void *out
);
HowlVtCallStatus howl_vt_render_state_row_cells_get_multi(
    HowlVtRenderStateRowCellsHandle cells,
    size_t count,
    const HowlVtRenderStateRowCellsData *keys,
    void **values,
    size_t *out_written
);

HowlVtHandle howl_vt_terminal_init(
    uint16_t rows,
    uint16_t cols,
    uint16_t history_capacity
);
HowlVtHandle howl_vt_terminal_init_with_options(
    uint16_t rows,
    uint16_t cols,
    uint16_t history_capacity,
    HowlVtTerminalInitOptions options
);
void howl_vt_terminal_deinit(HowlVtHandle handle);
int32_t howl_vt_terminal_resize(HowlVtHandle handle, uint16_t rows, uint16_t cols);
int32_t howl_vt_terminal_set_cell_pixel_size(
    HowlVtHandle handle,
    uint32_t width,
    uint32_t height
);
int32_t howl_vt_terminal_start_selection(
    HowlVtHandle handle,
    int32_t row,
    uint16_t col
);
int32_t howl_vt_terminal_update_selection(
    HowlVtHandle handle,
    int32_t row,
    uint16_t col
);
int32_t howl_vt_terminal_finish_selection(HowlVtHandle handle);
int32_t howl_vt_terminal_clear_selection(HowlVtHandle handle);
HowlVtFeedResult howl_vt_terminal_feed(
    HowlVtHandle handle,
    const uint8_t *ptr,
    size_t len
);
HowlVtRuntimeProgressResult howl_vt_terminal_progress_runtime(
    HowlVtHandle handle,
    uint64_t now_ns
);
HowlVtVisibleInfoResult howl_vt_terminal_query_visible_info(HowlVtHandle handle);
HowlVtScrollViewportResult howl_vt_terminal_scroll_viewport(
    HowlVtHandle handle,
    uint8_t kind,
    int64_t value
);
HowlVtSelectionResult howl_vt_terminal_query_selection(HowlVtHandle handle);
HowlVtBytesResult howl_vt_terminal_copy_visible_hyperlink(
    HowlVtHandle handle,
    uint16_t row,
    uint16_t col,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_copy_selection(
    HowlVtHandle handle,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_copy_title(
    HowlVtHandle handle,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_copy_pending_output(
    HowlVtHandle handle,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_drain_pending_clipboard(
    HowlVtHandle handle,
    uint8_t *ptr,
    size_t cap
);
HowlVtRuntimeObligationResult howl_vt_terminal_query_runtime_obligation(
    HowlVtHandle handle,
    uint64_t now_ns
);
HowlVtBytesResult howl_vt_terminal_encode_key(
    HowlVtHandle handle,
    uint32_t key,
    uint8_t mods,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_encode_focus(
    HowlVtHandle handle,
    uint8_t focused,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_encode_paste_start(
    HowlVtHandle handle,
    uint8_t *ptr,
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_encode_paste_end(
    HowlVtHandle handle,
    uint8_t *ptr,
    size_t cap
);
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
    size_t cap
);
HowlVtBytesResult howl_vt_terminal_encode_paste(
    HowlVtHandle handle,
    const uint8_t *text_ptr,
    size_t text_len,
    uint8_t *ptr,
    size_t cap
);
void howl_vt_terminal_clear_pending_output(HowlVtHandle handle);

#ifdef __cplusplus
}
#endif

#endif
