#ifndef HOWL_VT_H
#define HOWL_VT_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef uintptr_t HowlVtHandle;

typedef enum {
  HOWL_VT_CALL_OK = 0,
  HOWL_VT_CALL_MISSING_HANDLE = -1,
  HOWL_VT_CALL_INVALID_ARGUMENT = -2,
  HOWL_VT_CALL_FAILED = -3,
  HOWL_VT_CALL_SHORT_BUFFER = -4,
} HowlVtCallStatus;

typedef struct {
  uint8_t r;
  uint8_t g;
  uint8_t b;
  uint8_t a;
} HowlVtColor;

typedef struct {
  uint32_t codepoint;
  HowlVtColor fg;
  HowlVtColor bg;
  HowlVtColor underline_color;
  uint32_t link_id;
  uint8_t continuation;
  uint8_t bold;
  uint8_t blink;
  uint8_t blink_fast;
  uint8_t reverse;
  uint8_t underline;
  uint8_t underline_style;
  uint8_t reserved0;
} HowlVtCell;

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

uint32_t howl_vt_mod_none(void);
uint32_t howl_vt_mod_shift(void);
uint32_t howl_vt_mod_alt(void);
uint32_t howl_vt_mod_ctrl(void);
uint8_t howl_vt_mod_is_valid(uint32_t mods);

uint32_t howl_vt_key_enter(void);
uint32_t howl_vt_key_tab(void);
uint32_t howl_vt_key_backspace(void);
uint32_t howl_vt_key_escape(void);
uint32_t howl_vt_key_up(void);
uint32_t howl_vt_key_down(void);
uint32_t howl_vt_key_left(void);
uint32_t howl_vt_key_right(void);
uint32_t howl_vt_key_insert(void);
uint32_t howl_vt_key_delete(void);
uint32_t howl_vt_key_home(void);
uint32_t howl_vt_key_end(void);
uint32_t howl_vt_key_pageup(void);
uint32_t howl_vt_key_pagedown(void);
uint32_t howl_vt_key_f1(void);
uint32_t howl_vt_key_f2(void);
uint32_t howl_vt_key_f3(void);
uint32_t howl_vt_key_f4(void);
uint32_t howl_vt_key_f5(void);
uint32_t howl_vt_key_f6(void);
uint32_t howl_vt_key_f7(void);
uint32_t howl_vt_key_f8(void);
uint32_t howl_vt_key_f9(void);
uint32_t howl_vt_key_f10(void);
uint32_t howl_vt_key_f11(void);
uint32_t howl_vt_key_f12(void);
uint8_t howl_vt_key_is_valid(uint32_t key);

uint8_t howl_vt_mouse_button_none(void);
uint8_t howl_vt_mouse_button_left(void);
uint8_t howl_vt_mouse_button_middle(void);
uint8_t howl_vt_mouse_button_right(void);
uint8_t howl_vt_mouse_button_wheel_up(void);
uint8_t howl_vt_mouse_button_wheel_down(void);
uint8_t howl_vt_mouse_button_is_valid(uint8_t button);
uint8_t howl_vt_mouse_press(void);
uint8_t howl_vt_mouse_release(void);
uint8_t howl_vt_mouse_move(void);
uint8_t howl_vt_mouse_wheel(void);
uint8_t howl_vt_mouse_event_kind_is_valid(uint8_t kind);

HowlVtHandle howl_vt_terminal_init(uint16_t rows, uint16_t cols, uint16_t history_capacity);
void howl_vt_terminal_deinit(HowlVtHandle handle);
int32_t howl_vt_terminal_feed(HowlVtHandle handle, const uint8_t *ptr, size_t len);
uint64_t howl_vt_terminal_queued_event_count(HowlVtHandle handle);
HowlVtApplyResult howl_vt_terminal_apply(HowlVtHandle handle, size_t max_events, uint8_t *title_ptr, size_t title_cap);
int32_t howl_vt_terminal_resize(HowlVtHandle handle, uint16_t rows, uint16_t cols);
uint64_t howl_vt_terminal_history_count(HowlVtHandle handle);
uint8_t howl_vt_terminal_is_alternate_screen(HowlVtHandle handle);
void howl_vt_terminal_clear_dirty_rows(HowlVtHandle handle);
HowlVtVisibleView howl_vt_terminal_copy_visible(HowlVtHandle handle, size_t scrollback_offset, HowlVtCell *cells_ptr, size_t cells_cap);
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
