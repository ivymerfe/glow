package xkbcommon

import "core:c"

KeyboardContext :: struct {
	xkb_context: rawptr,
	xkb_keymap:  rawptr,
	xkb_state:   rawptr,
}

keyboard_context_create :: proc() -> KeyboardContext {
	ctx := KeyboardContext {
		xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS),
	}
	return ctx
}

keyboard_context_destroy :: proc(ctx: ^KeyboardContext) {
	if ctx.xkb_state != nil {
		xkb_state_unref(ctx.xkb_state)
		ctx.xkb_state = nil
	}
	if ctx.xkb_keymap != nil {
		xkb_keymap_unref(ctx.xkb_keymap)
		ctx.xkb_keymap = nil
	}
	if ctx.xkb_context != nil {
		xkb_context_unref(ctx.xkb_context)
		ctx.xkb_context = nil
	}
}

keyboard_context_set_keymap :: proc(
	ctx: ^KeyboardContext,
	keymap: cstring,
	size: c.size_t,
) -> bool {
	if ctx.xkb_state != nil {
		xkb_state_unref(ctx.xkb_state)
	}
	if ctx.xkb_keymap != nil {
		xkb_keymap_unref(ctx.xkb_keymap)
	}
	ctx.xkb_keymap = xkb_keymap_new_from_buffer(
		ctx.xkb_context,
		keymap,
		size,
		XKB_KEYMAP_FORMAT_TEXT_V1,
		0,
	)
	if ctx.xkb_keymap == nil {
		return false
	}
	ctx.xkb_state = xkb_state_new(ctx.xkb_keymap)
	return ctx.xkb_state != nil
}

keyboard_context_get_utf8 :: proc(ctx: ^KeyboardContext, key: u32, buf: []u8) -> i32 {
	if ctx.xkb_state == nil {
		return 0
	}
	return xkb_state_key_get_utf8(ctx.xkb_state, key, cast(cstring)raw_data(buf[:]), len(buf))
}

keyboard_context_get_keysym :: proc(ctx: ^KeyboardContext, key: u32) -> u32 {
	if ctx.xkb_state == nil {
		return 0
	}
	return xkb_state_key_get_one_sym(ctx.xkb_state, key)
}

keyboard_context_update_key :: proc(ctx: ^KeyboardContext, key: u32, pressed: bool) {
	if ctx.xkb_state == nil {
		return
	}
	direction := XKB_KEY_DOWN if pressed else XKB_KEY_UP
	xkb_state_update_key(ctx.xkb_state, key, i32(direction))
}

keyboard_context_update_modifiers :: proc(
	ctx: ^KeyboardContext,
	depressed_mods: u32,
	latched_mods: u32,
	locked_mods: u32,
	depressed_layout: u32 = 0,
	latched_layout: u32 = 0,
	locked_layout: u32 = 0,
) {
	if ctx.xkb_state == nil {
		return
	}
	xkb_state_update_mask(
		ctx.xkb_state,
		depressed_mods,
		latched_mods,
		locked_mods,
		depressed_layout,
		latched_layout,
		locked_layout,
	)
}
