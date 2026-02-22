package gwin

import "base:runtime"
import "core:c"
import "core:log"
import "core:sync"
import "core:sys/linux"

import vk "vendor:vulkan"
import wl "wayland_client"
import xdg "wayland_client/xdg"
import xkb "xkbcommon"

ModifierState :: struct {
	shift: bool,
	ctrl:  bool,
	alt:   bool,
	super: bool,
}

EventKeyDown :: struct {
	keysym: u32,
	key:    uint,
}

EventKeyUp :: struct {
	keysym: u32,
	key:    uint,
}

EventWindowClose :: struct {}

EventWindowResize :: struct {
	width:  int,
	height: int,
}

WindowEvent :: union {
	EventKeyDown,
	EventKeyUp,
	EventWindowClose,
	EventWindowResize,
}

WindowEventHandler :: proc(window: ^WaylandWindow, event: WindowEvent)

WaylandContext :: struct {
	app_context:              runtime.Context,
	display:                  ^wl.display,
	registry:                 ^wl.registry,
	compositor:               ^wl.compositor,
	wm_base:                  ^xdg.wm_base,
	seat:                     ^wl.seat,
	keyboard:                 ^wl.keyboard,
	pointer:                  ^wl.pointer,
	fractional_scale_manager: ^wl.fractional_scale_manager_v1,
	surface_to_window:        map[^wl.surface]^WaylandWindow,
	focused_window:           ^WaylandWindow,
	kb_context:               xkb.KeyboardContext,
	event_handler:            WindowEventHandler,
}

WaylandWindow :: struct {
	ctx:              ^WaylandContext,
	id:               u32,
	surface:          ^wl.surface,
	xdg_surface:      ^xdg.surface,
	toplevel:         ^xdg.toplevel,
	fractional_scale: ^wl.fractional_scale_v1,
	title:            cstring,
	width:            int,
	height:           int,
	scale:            f32,
	configured:       bool,
	fullscreen:       bool,
	visible:          bool,
}

@(private = "file")
registry_listener := wl.registry_listener {
	global        = registry_global,
	global_remove = registry_global_remove,
}

@(private = "file")
wm_base_listener := xdg.wm_base_listener {
	ping = wm_base_ping,
}

@(private = "file")
toplevel_listener := xdg.toplevel_listener {
	configure = xdg_toplevel_configure,
	close     = xdg_toplevel_close,
}

@(private = "file")
xdg_surface_listener := xdg.surface_listener {
	configure = xdg_surface_configure,
}

@(private = "file")
seat_listener := wl.seat_listener {
	capabilities = seat_capabilities,
	name         = seat_name,
}

@(private = "file")
kb_listener := wl.keyboard_listener {
	keymap      = keyboard_keymap,
	enter       = keyboard_enter,
	leave       = keyboard_leave,
	key         = keyboard_key,
	modifiers   = keyboard_modifiers,
	repeat_info = keyboard_repeat_info,
}

@(private = "file")
pointer_listener := wl.pointer_listener {
	enter         = pointer_enter,
	leave         = pointer_leave,
	motion        = pointer_motion,
	button        = pointer_button,
	axis          = pointer_axis,
	frame         = pointer_frame,
	axis_source   = pointer_axis_source,
	axis_stop     = pointer_axis_stop,
	axis_discrete = pointer_axis_discrete,
}

@(private = "file")
fractional_scale_listener := wl.fractional_scale_v1_listener {
	preferred_scale = fractional_scale_preferred_scale,
}

@(private = "file")
registry_global :: proc "c" (
	data: rawptr,
	registry: ^wl.registry,
	name: uint,
	interface: cstring,
	version: uint,
) {
	ctx := cast(^WaylandContext)data

	if interface == "wl_compositor" {
		ctx.compositor = cast(^wl.compositor)wl.registry_bind(
			registry,
			name,
			&wl.compositor_interface,
			4,
		)
	} else if interface == xdg.wm_base_interface.name {
		ctx.wm_base = cast(^xdg.wm_base)wl.registry_bind(registry, name, &xdg.wm_base_interface, 1)
	} else if interface == wl.seat_interface.name {
		ctx.seat = cast(^wl.seat)wl.registry_bind(registry, name, &wl.seat_interface, 5)
		wl.seat_add_listener(ctx.seat, &seat_listener, data)
	} else if interface == wl.fractional_scale_manager_v1_interface.name {
		ctx.fractional_scale_manager = cast(^wl.fractional_scale_manager_v1)wl.registry_bind(
			registry,
			name,
			&wl.fractional_scale_manager_v1_interface,
			1,
		)
	}
}

@(private = "file")
registry_global_remove :: proc "c" (data: rawptr, registry: ^wl.registry, name: uint) {}

@(private = "file")
wm_base_ping :: proc "c" (data: rawptr, wm: ^xdg.wm_base, serial: uint) {
	xdg.wm_base_pong(wm, serial)
}

@(private = "file")
xdg_surface_configure :: proc "c" (data: rawptr, surface: ^xdg.surface, serial: uint) {
	xdg.surface_ack_configure(surface, serial)
	win := cast(^WaylandWindow)data
	if win != nil {
		context = win.ctx.app_context
		sync.atomic_store(&win.configured, true)
	}
}

@(private = "file")
xdg_toplevel_configure :: proc "c" (
	data: rawptr,
	toplevel: ^xdg.toplevel,
	width: int,
	height: int,
	states: ^wl.array,
) {
	win := cast(^WaylandWindow)data
	if win == nil {
		return
	}
	context = win.ctx.app_context
	if width > 0 && height > 0 && (win.width != width || win.height != height) {
		if width < win.width || height < win.height {
			win.fullscreen = false
		}
		win.width = width
		win.height = height
		win.ctx.event_handler(win, EventWindowResize{width = width, height = height})
	}
	win.fullscreen = false
	state_bytes := cast([^]u8)states.data
	for i: i64 = 0; i < states.size; i += 1 {
		state := xdg.toplevel_state(state_bytes[i])
		if state == .fullscreen {
			win.fullscreen = true
		}
	}
}

@(private = "file")
xdg_toplevel_close :: proc "c" (data: rawptr, toplevel: ^xdg.toplevel) {
	win := cast(^WaylandWindow)data
	if win == nil {
		return
	}
	context = win.ctx.app_context
	win.ctx.event_handler(win, EventWindowClose{})
}

@(private = "file")
seat_capabilities :: proc "c" (data: rawptr, seat_ptr: ^wl.seat, caps: wl.seat_capability) {
	ctx := cast(^WaylandContext)data
	if ctx == nil {
		return
	}
	if (caps & .keyboard == .keyboard) {
		if ctx.keyboard == nil {
			ctx.keyboard = wl.seat_get_keyboard(seat_ptr)
			wl.keyboard_add_listener(ctx.keyboard, &kb_listener, data)
		}
	}
	if (caps & .pointer == .pointer) {
		if ctx.pointer == nil {
			ctx.pointer = wl.seat_get_pointer(seat_ptr)
			wl.pointer_add_listener(ctx.pointer, &pointer_listener, data)
		}
	}
}

@(private = "file")
seat_name :: proc "c" (data: rawptr, seat_ptr: ^wl.seat, name: cstring) {}

@(private = "file")
keyboard_keymap :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	format: wl.keyboard_keymap_format,
	fd: int,
	size: uint,
) {
	ctx := cast(^WaylandContext)data
	if ctx == nil {
		return
	}
	context = ctx.app_context
	ptr, err := linux.mmap({}, size, {.READ}, {.SHARED}, linux.Fd(fd), 0)
	if err != .NONE {
		log.errorf("Failed to mmap keymap file descriptor: %v", err)
		return
	}
	success := xkb.keyboard_context_set_keymap(
		&ctx.kb_context,
		cast(cstring)ptr,
		cast(c.size_t)size,
	)
	if !success {
		log.error("Failed to set keyboard keymap")
	}
	linux.munmap(ptr, size)
	linux.close(linux.Fd(fd))
}

@(private = "file")
keyboard_enter :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	serial: uint,
	surface: ^wl.surface,
	keys: wl.array,
) {
	ctx := cast(^WaylandContext)data
	if ctx == nil {
		return
	}
	ctx.focused_window = ctx.surface_to_window[surface]
}

@(private = "file")
keyboard_leave :: proc "c" (data: rawptr, kb: ^wl.keyboard, serial: uint, surface: ^wl.surface) {
	ctx := cast(^WaylandContext)data
	if ctx == nil {
		return
	}
	win := ctx.surface_to_window[surface]
	if win == ctx.focused_window {
		ctx.focused_window = nil
	}
}

@(private = "file")
keyboard_key :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	serial: uint,
	time: uint,
	key: uint,
	state: wl.keyboard_key_state,
) {
	ctx := cast(^WaylandContext)data
	if ctx == nil {
		return
	}
	context = ctx.app_context
	key_code := u32(key + 8)
	pressed := state == .pressed
	xkb.keyboard_context_update_key(&ctx.kb_context, key_code, pressed)

	keysym := xkb.keyboard_context_get_keysym(&ctx.kb_context, key_code)
	if pressed {
		ctx.event_handler(ctx.focused_window, EventKeyDown{key = key, keysym = keysym})
	} else {
		ctx.event_handler(ctx.focused_window, EventKeyUp{key = key, keysym = keysym})
	}
}

@(private = "file")
keyboard_modifiers :: proc "c" (
	data: rawptr,
	kb: ^wl.keyboard,
	serial: uint,
	mods_depressed: uint,
	mods_latched: uint,
	mods_locked: uint,
	group: uint,
) {
	ctx := cast(^WaylandContext)data
	if ctx == nil {
		return
	}
	context = ctx.app_context
	xkb.keyboard_context_update_modifiers(
		&ctx.kb_context,
		u32(mods_depressed),
		u32(mods_latched),
		u32(mods_locked),
	)
}

@(private = "file")
keyboard_repeat_info :: proc "c" (data: rawptr, kb: ^wl.keyboard, rate: int, delay: int) {}

@(private = "file")
pointer_enter :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	serial: uint,
	surface: ^wl.surface,
	sx: i32,
	sy: i32,
) {}

@(private = "file")
pointer_leave :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	serial: uint,
	surface: ^wl.surface,
) {}

@(private = "file")
pointer_motion :: proc "c" (data: rawptr, pointer: ^wl.pointer, time: uint, sx: i32, sy: i32) {}

@(private = "file")
pointer_button :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	serial: uint,
	time: uint,
	button: uint,
	state: wl.pointer_button_state,
) {}

@(private = "file")
pointer_axis :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	time: uint,
	axis: wl.pointer_axis,
	value: i32,
) {}

@(private = "file")
pointer_frame :: proc "c" (data: rawptr, pointer: ^wl.pointer) {}

@(private = "file")
pointer_axis_source :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	axis_source: wl.pointer_axis_source,
) {}

@(private = "file")
pointer_axis_stop :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	time: uint,
	axis: wl.pointer_axis,
) {}

@(private = "file")
pointer_axis_discrete :: proc "c" (
	data: rawptr,
	pointer: ^wl.pointer,
	axis: wl.pointer_axis,
	discrete: int,
) {}

@(private = "file")
fractional_scale_preferred_scale :: proc "c" (
	data: rawptr,
	fractional_scale: ^wl.fractional_scale_v1,
	scale_120: u32,
) {
	win := cast(^WaylandWindow)data
	if win == nil {
		return
	}
	context = win.ctx.app_context
	// Scale is encoded as 120ths (e.g., 120 = 1.0, 240 = 2.0, 180 = 1.5)
	win.scale = f32(scale_120) / 120.0
	log.infof("Window %d scale changed to %.2f", win.id, win.scale)
}

create_wayland_context :: proc(ctx: ^WaylandContext, event_handler: WindowEventHandler) -> bool {
	ctx.app_context = context
	ctx.event_handler = event_handler

	ctx.display = wl.display_connect(nil)
	if ctx.display == nil {
		log.error("Failed to connect to Wayland display")
		return false
	}

	ctx.registry = wl.display_get_registry(ctx.display)
	if ctx.registry == nil {
		log.error("Failed to get Wayland registry")
		return false
	}
	wl.registry_add_listener(ctx.registry, &registry_listener, ctx)
	wl.display_roundtrip(ctx.display)

	if ctx.compositor == nil || ctx.wm_base == nil {
		log.error("Failed to bind required Wayland interfaces")
		return false
	}
	xdg.wm_base_add_listener(ctx.wm_base, &wm_base_listener, ctx)

	ctx.kb_context = xkb.keyboard_context_create()
	ctx.surface_to_window = make(map[^wl.surface]^WaylandWindow)
	return true
}

destroy_wayland_context :: proc(ctx: ^WaylandContext) {
	for surf, win in ctx.surface_to_window {
		destroy_window(win)
	}
	if ctx.keyboard != nil {
		wl.keyboard_destroy(ctx.keyboard)
	}
	if ctx.pointer != nil {
		wl.pointer_destroy(ctx.pointer)
	}
	if ctx.seat != nil {
		wl.seat_destroy(ctx.seat)
	}
	if ctx.fractional_scale_manager != nil {
		wl.fractional_scale_manager_v1_destroy(ctx.fractional_scale_manager)
	}
	if ctx.wm_base != nil {
		xdg.wm_base_destroy(ctx.wm_base)
	}
	if ctx.compositor != nil {
		wl.compositor_destroy(ctx.compositor)
	}
	if ctx.registry != nil {
		wl.registry_destroy(ctx.registry)
	}
	if ctx.display != nil {
		wl.display_disconnect(ctx.display)
	}
	xkb.keyboard_context_destroy(&ctx.kb_context)
	delete(ctx.surface_to_window)
}

create_window :: proc(
	ctx: ^WaylandContext,
	id: u32,
	title: cstring,
	width: int,
	height: int,
) -> (
	window: ^WaylandWindow,
	success: bool,
) {
	if ctx.compositor == nil || ctx.wm_base == nil {
		log.error("Window system not initialized")
		return
	}

	surface := wl.compositor_create_surface(ctx.compositor)
	if surface == nil {
		log.error("Failed to create Wayland surface")
		return
	}
	window = new(WaylandWindow)
	window.id = id
	window.ctx = ctx
	window.surface = surface
	window.title = title
	window.width = width
	window.height = height
	window.scale = 1.0
	window.visible = false

	ctx.surface_to_window[surface] = window

	show_window(window)
	success = true
	return
}

@(private = "file")
show_window :: proc(win: ^WaylandWindow) {
	if win.visible {
		return
	}
	win.configured = false

	xdg_surface := xdg.wm_base_get_xdg_surface(win.ctx.wm_base, win.surface)
	if xdg_surface == nil {
		log.error("Failed to create XDG surface")
		wl.surface_destroy(win.surface)
		return
	}

	toplevel := xdg.surface_get_toplevel(xdg_surface)
	if toplevel == nil {
		log.error("Failed to create XDG toplevel")
		xdg.surface_destroy(xdg_surface)
		wl.surface_destroy(win.surface)
		return
	}
	win.xdg_surface = xdg_surface
	win.toplevel = toplevel

	xdg.surface_add_listener(xdg_surface, &xdg_surface_listener, win)
	xdg.toplevel_add_listener(toplevel, &toplevel_listener, win)

	xdg.toplevel_set_min_size(toplevel, 320, 180)
	xdg.toplevel_set_app_id(toplevel, "glow")
	xdg.toplevel_set_title(toplevel, win.title)

	// Set up fractional scaling if available
	if win.ctx.fractional_scale_manager != nil {
		win.fractional_scale = wl.fractional_scale_manager_v1_get_fractional_scale(
			win.ctx.fractional_scale_manager,
			win.surface,
		)
		if win.fractional_scale != nil {
			wl.fractional_scale_v1_add_listener(
				win.fractional_scale,
				&fractional_scale_listener,
				win,
			)
		}
	}

	wl.surface_commit(win.surface)

	wl.display_roundtrip(win.ctx.display)

	win.visible = true
	log.infof("Window %d shown", win.id)
}

@(private = "file")
hide_window :: proc(win: ^WaylandWindow) {
	if !win.visible {
		return
	}
	wl.surface_attach(win.surface, nil, 0, 0)
	wl.surface_commit(win.surface)

	if win.fractional_scale != nil {
		wl.fractional_scale_v1_destroy(win.fractional_scale)
		win.fractional_scale = nil
	}

	xdg.toplevel_destroy(win.toplevel)
	xdg.surface_destroy(win.xdg_surface)

	win.toplevel = nil
	win.xdg_surface = nil
	win.visible = false
	win.configured = false
	log.infof("Window %d hidden", win.id)
}

destroy_window :: proc(win: ^WaylandWindow) {
	if win == nil {
		return
	}
	if win.fractional_scale != nil {
		wl.fractional_scale_v1_destroy(win.fractional_scale)
	}
	if win.toplevel != nil {
		xdg.toplevel_destroy(win.toplevel)
	}
	if win.xdg_surface != nil {
		xdg.surface_destroy(win.xdg_surface)
	}
	if win.surface != nil {
		wl.surface_destroy(win.surface)
	}
	delete_key(&win.ctx.surface_to_window, win.surface)
	free(win)
}

get_display_fd :: proc(ctx: ^WaylandContext) -> int {
	return wl.display_get_fd(ctx.display)
}

dispatch_events :: proc(ctx: ^WaylandContext) -> bool {
	return wl.display_dispatch(ctx.display) > 0
}

create_vulkan_surface :: proc(
	win: ^WaylandWindow,
	instance: vk.Instance,
) -> (
	vk.SurfaceKHR,
	bool,
) {
	wl_surface_info := vk.WaylandSurfaceCreateInfoKHR {
		sType   = .WAYLAND_SURFACE_CREATE_INFO_KHR,
		display = auto_cast win.ctx.display,
		surface = auto_cast win.surface,
	}
	vk_surface: vk.SurfaceKHR
	result := vk.CreateWaylandSurfaceKHR(instance, &wl_surface_info, nil, &vk_surface)
	if result != .SUCCESS {
		log.errorf("Failed to create Vulkan surface: %v", result)
		return {}, false
	}
	return vk_surface, true
}

set_window_visible :: proc(win: ^WaylandWindow, visible: bool) {
	if win == nil {
		return
	}
	if visible && !win.visible {
		show_window(win)
	} else if !visible && win.visible {
		hide_window(win)
	}
}

set_window_fullscreen :: proc(win: ^WaylandWindow, fullscreen: bool) {
	if win == nil {
		return
	}
	if fullscreen {
		xdg.toplevel_set_fullscreen(win.toplevel, nil)
	} else {
		xdg.toplevel_unset_fullscreen(win.toplevel)
	}
	win.fullscreen = fullscreen
}

