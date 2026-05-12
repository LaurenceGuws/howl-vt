#ifndef HOWL_VT_H
#define HOWL_VT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

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

#ifdef __cplusplus
}
#endif

#endif
