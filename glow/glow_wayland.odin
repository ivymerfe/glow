package glow

import "base:runtime"
import "core:log"
import "core:sync"

import wl "lib/wayland_client"
import xdg "lib/wayland_client/xdg"

WaylandContext :: struct {
	display:    ^wl.display,
	registry:   ^wl.registry,
	compositor: ^wl.compositor,
	wm_base:    ^xdg.wm_base,
}

WaylandWindow :: struct {
	surface:       ^wl.surface,
	xdg_surface:   ^xdg.surface,
	toplevel:      ^xdg.toplevel,
	width:         int,
	height:        int,
	configured:    bool,
	should_resize: bool,
	should_exit:   bool,
}

global_context: runtime.Context
wayland_context: WaylandContext
window: WaylandWindow

registry_global :: proc "c" (
	data: rawptr,
	registry: ^wl.registry,
	name: uint,
	interface: cstring,
	version: uint,
) {
	if interface == "wl_compositor" {
		wayland_context.compositor = cast(^wl.compositor)wl.registry_bind(
			registry,
			name,
			&wl.compositor_interface,
			4,
		)
	} else if interface == xdg.wm_base_interface.name {
		wayland_context.wm_base = cast(^xdg.wm_base)wl.registry_bind(
			registry,
			name,
			&xdg.wm_base_interface,
			1,
		)
	} else if interface == wl.seat_interface.name {
		seat := cast(^wl.seat)wl.registry_bind(registry, name, &wl.seat_interface, 5)
		wl.seat_add_listener(seat, &seat_listener, nil)
	}
}

registry_global_remove :: proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {}

wm_base_ping :: proc "c" (data: rawptr, wm: ^xdg.wm_base, serial: uint) {
	xdg.wm_base_pong(wm, serial)
}

xdg_surface_configure :: proc "c" (data: rawptr, surface: ^xdg.surface, serial: uint) {
	xdg.surface_ack_configure(surface, serial)
	sync.atomic_store(&window.configured, true)
}

seat_capabilities :: proc "c" (data: rawptr, seat_ptr: ^wl.seat, caps: wl.seat_capability) {
	if (caps & .keyboard == .keyboard) {
		keyboard := wl.seat_get_keyboard(seat_ptr)
		wl.keyboard_add_listener(keyboard, &kb_listener, nil)
	}
}

seat_name :: proc "c" (data: rawptr, seat_ptr: ^wl.seat, name: cstring) {}

seat_listener := wl.seat_listener {
	capabilities = seat_capabilities,
	name         = seat_name,
}

keyboard_keymap :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	format: wl.keyboard_keymap_format,
	fd: int,
	size: uint,
) {

}

keyboard_enter :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	serial: uint,
	surface: ^wl.surface,
	keys: wl.array,
) {}

keyboard_leave :: proc "c" (data: rawptr, kb: ^wl.keyboard, serial: uint, surface: ^wl.surface) {}

keyboard_key :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	serial: uint,
	time: uint,
	key: uint,
	state: wl.keyboard_key_state,
) {

}

keyboard_modifiers :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	serial: uint,
	mods_depressed: uint,
	mods_latched: uint,
	mods_locked: uint,
	group: uint,
) {}

keyboard_repeat_info :: proc "c" (data: rawptr, kb: ^wl.keyboard, rate: int, delay: int) {}

kb_listener := wl.keyboard_listener {
	keymap      = keyboard_keymap,
	enter       = keyboard_enter,
	leave       = keyboard_leave,
	key         = keyboard_key,
	modifiers   = keyboard_modifiers,
	repeat_info = keyboard_repeat_info,
}

xdg_toplevel_configure :: proc "c" (
	data: rawptr,
	toplevel: ^xdg.toplevel,
	width: int,
	height: int,
	states: wl.array,
) {
	window_width := sync.atomic_load(&window.width)
	window_height := sync.atomic_load(&window.height)
	if window_width != width || window_height != height {
		sync.atomic_store(&window.should_resize, window.width > 0)
		sync.atomic_store(&window.width, width)
		sync.atomic_store(&window.height, height)
	}
}

xdg_toplevel_close :: proc "c" (data: rawptr, toplevel: ^xdg.toplevel) {
	sync.atomic_store(&window.should_exit, true)
}

toplevel_listener := xdg.toplevel_listener {
	configure = xdg_toplevel_configure,
	close     = xdg_toplevel_close,
}

registry_listener := wl.registry_listener {
	global        = registry_global,
	global_remove = registry_global_remove,
}

wm_base_listener := xdg.wm_base_listener {
	ping = wm_base_ping,
}

xdg_surface_listener := xdg.surface_listener {
	configure = xdg_surface_configure,
}

init_wayland :: proc() {
	global_context = context

	wayland_context.display = wl.display_connect(nil)
	if wayland_context.display != nil {
		log.info("Successfully connected to a wayland display.")
	} else {
		log.panic("Failed to connect to a wayland display")
	}

	wayland_context.registry = wl.display_get_registry(wayland_context.display)

	wl.registry_add_listener(wayland_context.registry, &registry_listener, nil)
	wl.display_roundtrip(wayland_context.display)

	window.surface = wl.compositor_create_surface(wayland_context.compositor)

	xdg.wm_base_add_listener(wayland_context.wm_base, &wm_base_listener, nil)

	window.xdg_surface = xdg.wm_base_get_xdg_surface(
		wayland_context.wm_base,
		window.surface,
	)
	xdg.surface_add_listener(window.xdg_surface, &xdg_surface_listener, nil)

	window.toplevel = xdg.surface_get_toplevel(window.xdg_surface)
	xdg.toplevel_add_listener(window.toplevel, &toplevel_listener, nil)

	xdg.toplevel_set_min_size(window.toplevel, 320, 180)
	xdg.toplevel_set_app_id(window.toplevel, "glow")
	xdg.toplevel_set_title(window.toplevel, "glow")

	wl.surface_commit(window.surface)
}

destroy_wayland :: proc() {
	if wayland_context.compositor != nil {
		wl.compositor_destroy(wayland_context.compositor)
	}
}

wayland_main :: proc() {
	for !window.should_exit && wl.display_dispatch(wayland_context.display) > 0 {

	}
}

should_resize :: proc() -> bool {
	return sync.atomic_load(&window.should_resize)
}

handle_resize :: proc() {
	sync.atomic_store(&window.should_resize, false)
}

should_exit :: proc() -> bool {
	return sync.atomic_load(&window.should_exit)
}

get_window_size :: proc() -> (int, int) {
	width := sync.atomic_load(&window.width)
	height := sync.atomic_load(&window.height)
	return width, height
}
