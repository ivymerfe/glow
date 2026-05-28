package glow

import "base:runtime"
import "core:flags"
import "core:log"
import "core:os"
import "core:sync"
import "core:sys/linux"
import "core:time"

import "../gwin"
import "../rend"
import "../slang"

g_slang: ^slang.IGlobalSession
g_wayland: gwin.WaylandContext
g_renderer: GlowRenderer
g_epoll: EPollController
g_server: GlowServer

Options :: struct {
	width:       uint `usage:"Buffer width"`,
	height:      uint `usage:"Buffer height"`,
	max_images:  uint `usage:"Max images per window"`,
	max_windows: uint `usage:"Max window count"`,
	debug:       bool `usage:"Show debug messages, enable validation layers"`,
}

g_options: Options

main :: proc() {
	flags.parse_or_exit(&g_options, os.args, .Odin)
	if g_options.width == 0 {
		g_options.width = 1920
	}
	if g_options.height == 0 {
		g_options.height = 1080
	}
	if g_options.max_images == 0 {
		g_options.max_images = 32
	}
	if g_options.max_windows == 0 {
		g_options.max_windows = 8
	}

	log_level := g_options.debug ? log.Level.Debug : log.Level.Info
	context.logger = log.create_console_logger(log_level, {.Level, .Procedure})

	init_keymap()

	launch_time := time.now()
	if !gwin.create_wayland_context(&g_wayland, event_handler) {
		log.panic("Failed to initialize window system")
	}
	wl_init_time := time.duration_milliseconds(time.diff(launch_time, time.now()))
	log.infof("Wl init -> %.2f ms", wl_init_time)

	slang_init_start := time.now()
	rend.slang_check(slang.createGlobalSession(slang.API_VERSION, &g_slang))
	slang_init_time := time.duration_milliseconds(time.diff(slang_init_start, time.now()))
	log.infof("Slang init -> %.2f ms", slang_init_time)

	glow_init_start := time.now()
	create_glow(&g_renderer)
	glow_init_time := time.duration_milliseconds(time.diff(glow_init_start, time.now()))
	log.infof("Glow init -> %.2fms", glow_init_time)

	epoll_init(&g_epoll)
	server_init(&g_server, &g_epoll, command_handler)

	wayland_fd := gwin.get_display_fd(&g_wayland)
	epoll_add(
		&g_epoll,
		linux.Fd(wayland_fd),
		{.IN},
		proc(fd: linux.Fd, ev: linux.EPoll_Event_Set, data: rawptr) {
			if ev & {.IN} != {} {
				gwin.dispatch_events(&g_wayland)
			}
		},
		&g_wayland,
	)
	for {
		if !epoll_poll(&g_epoll) {
			log.panic("poll failed")
		}
	}
	shutdown()
}

broadcast_window_destroyed :: proc(window_id: u32) {
	msg: Message
	msg_window_destroyed(&msg, window_id)
	server_broadcast(&g_server, &msg)
}

broadcast_window_visible :: proc(window_id: u32, visible: bool) {
	msg: Message
	msg_window_visible(&msg, window_id, visible)
	server_broadcast(&g_server, &msg)
}

event_handler :: proc(native: ^gwin.WaylandWindow, event_union: gwin.WindowEvent) {
	win := glow_get_window(&g_renderer, native.id)
	if win == nil {
		return
	}
	#partial switch event in event_union {
	case gwin.EventKeyDown:
		key, ok := map_xkb_keysym(event.key)
		if !ok {
			break
		}
		switch key {
		case KEY_Q:
			glow_destroy_window(&g_renderer, native.id)
			broadcast_window_destroyed(native.id)
		case KEY_E:
			set_window_fullscreen(win, !native.fullscreen)
		case KEY_ESCAPE:
			set_window_fullscreen(win, false)
		case KEY_H:
			set_window_visible(win, false)
			broadcast_window_visible(win.id, false)
		case KEY_P:
			active := !sync.atomic_load(&win.active)
			set_window_active(win, active)
			if active {
				renderer_wakeup(&g_renderer)
			}
		case:
			on_window_input(win, key, true)
		}
	case gwin.EventKeyUp:
		key, ok := map_xkb_keysym(event.key)
		if ok {
			on_window_input(win, key, false)
		}
	case gwin.EventKeyboardLeave:
		on_window_keyboard_leave(win)
	case gwin.EventPointerEnter:
		on_window_pointer_enter(win, event.pointer, event.x, event.y)
	case gwin.EventPointerMotion:
		on_window_pointer_motion(win, event.x, event.y)
	case gwin.EventPointerRelative:
		on_window_pointer_relative(win, event.dx, event.dy)
	case gwin.EventPointerButton:
		button, ok := map_wayland_mouse_button(event.button)
		if ok {
			on_window_pointer_button(win, event.pointer, button, event.pressed)
		}
	case gwin.EventPointerScroll:
		on_window_pointer_scroll(win, event.dx, event.dy)
	}
}

command_handler :: proc(cmd_union: GlowCommand) {
	switch cmd in cmd_union {
	case CmdWindowCreate:
		glow_new_window(&g_renderer, cmd.window_id)
	case CmdWindowDestroy:
		glow_destroy_window(&g_renderer, cmd.window_id)
	case CmdWindowVisible:
		win := glow_get_window(&g_renderer, cmd.window_id)
		if win != nil {
			set_window_visible(win, cmd.visible)
		}
	case CmdWindowToggleFullscreen:
		win := glow_get_window(&g_renderer, cmd.window_id)
		if win != nil {
			gwin.set_window_fullscreen(win.native, !win.native.fullscreen)
		}
	case CmdWindowProgram:
		win := glow_get_window(&g_renderer, cmd.window_id)
		if win != nil {
			pbuf_update_source(&win.pbuf, cmd.path, cmd.source)
			compiler_wakeup(&g_renderer)
		}
	case CmdCompileProgram:
		run_compiler_thread(cmd.target, cmd.path, cmd.source, cmd.dst_path)
	}
}

shutdown :: proc() {
	destroy_glow(&g_renderer)

	if g_slang != nil {
		g_slang->release()
	}
	gwin.destroy_wayland_context(&g_wayland)
	log.info("Goodbye")
}

