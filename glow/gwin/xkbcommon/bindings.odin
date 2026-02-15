package xkbcommon

import "core:c"
foreign import xkb "system:xkbcommon"

XKB_KEY_DOWN :: 0
XKB_KEY_UP :: 1

XKB_CONTEXT_NO_FLAGS :: 0
XKB_CONTEXT_NO_DEFAULT_INCLUDES :: 1 << 0
XKB_CONTEXT_NO_ENVIRONMENT_NAMES :: 1 << 1

XKB_KEYMAP_FORMAT_TEXT_V1 :: 1

XKB_COMPILE_NO_FLAGS :: 0

XKB_MOD_NAME_SHIFT :: "Shift"
XKB_MOD_NAME_CAPS :: "Lock"
XKB_MOD_NAME_CTRL :: "Control"
XKB_MOD_NAME_ALT :: "Mod1"
XKB_MOD_NAME_NUM :: "Mod2"
XKB_MOD_NAME_LOGO :: "Mod4"

@(default_calling_convention = "c")
foreign xkb {
	// Context management
	xkb_context_new :: proc(flags: u32) -> rawptr ---
	xkb_context_unref :: proc(xkb_context: rawptr) ---

	// Keymap management
	xkb_keymap_new_from_buffer :: proc(xkb_context: rawptr, buffer: cstring, size: c.size_t, format: u32, flags: u32) -> rawptr ---
	xkb_keymap_unref :: proc(keymap: rawptr) ---
	xkb_keymap_key_repeats :: proc(keymap: rawptr, key: u32) -> c.int ---

	// State management
	xkb_state_new :: proc(keymap: rawptr) -> rawptr ---
	xkb_state_unref :: proc(state: rawptr) ---

	// Key processing
	xkb_state_key_get_one_sym :: proc(state: rawptr, key: u32) -> u32 ---

	xkb_state_key_get_utf8 :: proc(state: rawptr, key: u32, buffer: cstring, size: c.size_t) -> c.int ---

	xkb_state_update_key :: proc(state: rawptr, key: u32, direction: c.int) -> u32 ---

	xkb_state_update_mask :: proc(state: rawptr, depressed_mods: u32, latched_mods: u32, locked_mods: u32, depressed_layout: u32, latched_layout: u32, locked_layout: u32) -> u32 ---

	// Modifier state
	xkb_state_serialize_mods :: proc(state: rawptr, components: u32) -> u32 ---
	xkb_state_mod_name_is_active :: proc(state: rawptr, name: cstring, typ: u32) -> c.int ---

	// Key symbol utilities
	xkb_keysym_get_name :: proc(keysym: u32, buffer: cstring, size: c.size_t) ---
	xkb_keysym_from_name :: proc(name: cstring, flags: u32) -> u32 ---
}
