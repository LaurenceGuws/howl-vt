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
} HowlVtCallStatus;

typedef struct {
  uint8_t continuation;
  uint8_t reserved0;
  uint8_t reserved1;
  uint8_t reserved2;
} HowlVtCellFlags;

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
} HowlVtCellAttrs;

typedef struct {
  uint32_t codepoint;
  HowlVtCellFlags flags;
  HowlVtColor fg_color;
  HowlVtColor bg_color;
  HowlVtColor underline_color;
  uint8_t underline_style;
  uint8_t reserved0;
  uint8_t reserved1;
  uint8_t reserved2;
  HowlVtCellAttrs attrs;
  uint32_t link_id;
} HowlVtCell;

typedef struct {
  const HowlVtCell *ptr;
  size_t len;
} HowlVtCellSpan;

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
  HowlVtCellSpan cells;
  uint16_t cols;
  uint16_t rows;
  uint64_t scroll_row;
  uint8_t is_alternate_screen;
  uint8_t full_damage;
  uint16_t scroll_up_rows;
  HowlVtByteSpan dirty_rows;
  HowlVtU16Span dirty_cols_start;
  HowlVtU16Span dirty_cols_end;
  HowlVtCursor cursor;
} HowlVtSurfaceSource;

typedef struct {
  int32_t status;
  uint64_t written;
  uint64_t needed;
} HowlVtBytesResult;

typedef struct {
  int32_t status;
  uint64_t applied;
  uint64_t remaining_events;
  uint8_t state_changed;
  uint8_t reserved0;
  uint16_t reserved1;
  uint64_t title_written;
  uint64_t title_needed;
} HowlVtApplyResult;

typedef struct {
  int32_t status;
  uint16_t rows;
  uint16_t cols;
  uint16_t cursor_row;
  uint16_t cursor_col;
  uint8_t cursor_visible;
  uint8_t cursor_shape;
  uint8_t is_alternate_screen;
  uint8_t reserved0;
  uint64_t history_count;
  uint64_t scrollback_offset;
  uint64_t start;
  uint64_t cell_count;
} HowlVtVisibleView;

typedef struct {
  int32_t status;
  uint16_t start_row;
  uint16_t end_row;
  uint64_t needed;
} HowlVtDirtyView;

typedef struct {
  int32_t status;
  uint16_t rows;
  uint16_t cols;
  uint16_t cursor_row;
  uint16_t cursor_col;
  uint8_t cursor_visible;
  uint8_t cursor_shape;
  uint8_t is_alternate_screen;
  uint8_t reserved0;
  uint64_t history_count;
  uint64_t scrollback_offset;
  uint64_t start;
  uint64_t cell_count;
  uint16_t dirty_start_row;
  uint16_t dirty_end_row;
  uint32_t reserved1;
  uint64_t dirty_needed;
} HowlVtSurfaceView;

typedef struct {
  int32_t status;
  uint64_t history_count;
  uint64_t scrollback_offset;
  uint64_t dirty_needed;
  HowlVtSurfaceSource source;
} HowlVtSurfaceSourceResult;

HowlVtHandle howl_vt_terminal_init(uint16_t rows, uint16_t cols, uint16_t history_capacity);
void howl_vt_terminal_deinit(HowlVtHandle handle);
int32_t howl_vt_terminal_feed(HowlVtHandle handle, const uint8_t *ptr, size_t len);
HowlVtApplyResult howl_vt_terminal_apply(HowlVtHandle handle, size_t max_events, uint8_t *title_ptr, size_t title_cap);
int32_t howl_vt_terminal_resize(HowlVtHandle handle, uint16_t rows, uint16_t cols);
void howl_vt_terminal_clear_dirty_rows(HowlVtHandle handle);
HowlVtSurfaceView howl_vt_terminal_copy_surface(HowlVtHandle handle, size_t scrollback_offset, HowlVtCell *cells_ptr, size_t cells_cap, uint16_t *cols_start_ptr, size_t cols_start_cap, uint16_t *cols_end_ptr, size_t cols_end_cap);
HowlVtSurfaceSourceResult howl_vt_terminal_copy_surface_source(HowlVtHandle handle, size_t scrollback_offset, HowlVtCell *cells_ptr, size_t cells_cap, uint8_t *dirty_rows_ptr, size_t dirty_rows_cap, uint16_t *cols_start_ptr, size_t cols_start_cap, uint16_t *cols_end_ptr, size_t cols_end_cap, uint8_t full_damage, uint16_t scroll_up_rows);
HowlVtVisibleView howl_vt_terminal_copy_visible(HowlVtHandle handle, size_t scrollback_offset, HowlVtCell *cells_ptr, size_t cells_cap);
HowlVtDirtyView howl_vt_terminal_copy_dirty(HowlVtHandle handle, uint16_t *cols_start_ptr, size_t cols_start_cap, uint16_t *cols_end_ptr, size_t cols_end_cap);
HowlVtBytesResult howl_vt_terminal_copy_pending_output(HowlVtHandle handle, uint8_t *ptr, size_t cap);
void howl_vt_terminal_clear_pending_output(HowlVtHandle handle);
HowlVtBytesResult howl_vt_terminal_drain_pending_clipboard(HowlVtHandle handle, uint8_t *ptr, size_t cap);
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
