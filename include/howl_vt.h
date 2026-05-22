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
  uint8_t bold;
  uint8_t dim;
  uint8_t italic;
  uint8_t underline;
  uint8_t underline_color_set;
  uint8_t blink;
  uint8_t inverse;
  uint8_t invisible;
  uint8_t strikethrough;
} HowlVtSurfaceCellAttrs;

typedef struct {
  uint32_t codepoint;
  HowlVtSurfaceCellFlags flags;
  HowlVtColor fg_color;
  HowlVtColor bg_color;
  HowlVtColor underline_color;
  uint8_t underline_style;
  uint8_t reserved0;
  uint8_t reserved1;
  uint8_t reserved2;
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
} HowlVtCursor;

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
  int32_t status;
  uint64_t history_count;
  uint64_t scrollback_offset;
  uint64_t snapshot_seq;
  uint64_t dirty_generation;
  HowlVtSurface source;
} HowlVtSurfaceResult;

int32_t howl_vt_terminal_resize(HowlVtHandle handle, uint16_t rows, uint16_t cols);
int32_t howl_vt_terminal_ack_surface(HowlVtHandle handle, uint64_t snapshot_seq);
HowlVtVisibleMetaResult howl_vt_terminal_query_visible_meta(HowlVtHandle handle, uint64_t scrollback_offset);
HowlVtSurfaceResult howl_vt_terminal_copy_surface(HowlVtHandle handle, uint64_t scrollback_offset, HowlVtSurfaceCell *cells_ptr, size_t cells_cap, uint8_t *dirty_rows_ptr, size_t dirty_rows_cap, uint16_t *cols_start_ptr, size_t cols_start_cap, uint16_t *cols_end_ptr, size_t cols_end_cap);

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

HowlVtHandle howl_vt_terminal_init(uint16_t rows, uint16_t cols, uint16_t history_capacity);
void howl_vt_terminal_deinit(HowlVtHandle handle);
HowlVtFeedResult howl_vt_terminal_feed(HowlVtHandle handle, const uint8_t *ptr, size_t len);
HowlVtBytesResult howl_vt_terminal_copy_title(HowlVtHandle handle, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_copy_pending_output(HowlVtHandle handle, uint8_t *ptr, size_t cap);
void howl_vt_terminal_clear_pending_output(HowlVtHandle handle);
HowlVtBytesResult howl_vt_terminal_drain_pending_clipboard(HowlVtHandle handle, uint8_t *ptr, size_t cap);

/* -------------------------------------------------------------------------- */
/* 3. Shell Input                                                              */
/* -------------------------------------------------------------------------- */

HowlVtBytesResult howl_vt_terminal_encode_key(HowlVtHandle handle, uint32_t key, uint8_t mods, uint8_t *ptr, size_t cap);
HowlVtBytesResult howl_vt_terminal_encode_focus(HowlVtHandle handle, uint8_t focused, uint8_t *ptr, size_t cap);
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
