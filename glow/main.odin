package glow

import "base:runtime"
import "core:log"
import "core:os"
import "core:sync"
import "core:sys/linux"
import "core:thread"
import "core:time"

import "glowr"
import "gwin"
import "slang"
import vk "vendor:vulkan"

g_slang: ^slang.IGlobalSession
g_wayland: gwin.WaylandContext
g_renderer: GlowRenderer
g_compiler_threads: ^thread.Thread

main :: proc() {
	context.logger = log.create_file_logger(os.stderr, log.Level.Debug)

	init_input()
	init_keymap()

	launch_time := time.now()
	if !gwin.create_wayland_context(&g_wayland, event_handler) {
		log.panic("Failed to initialize window system")
	}
	wl_init_time := time.duration_milliseconds(time.diff(launch_time, time.now()))
	log.infof("Wl init -> %.2f ms", wl_init_time)

	slang_init_start := time.now()
	glowr.slang_check(slang.createGlobalSession(slang.API_VERSION, &g_slang))
	slang_init_time := time.duration_milliseconds(time.diff(slang_init_start, time.now()))
	log.infof("Slang init -> %.2f ms", slang_init_time)

	glow_init_start := time.now()
	create_glow(&g_renderer)
	glow_init_time := time.duration_milliseconds(time.diff(glow_init_start, time.now()))
	log.infof("Glow init -> %.2fms", glow_init_time)

	wayland_fd := gwin.get_display_fd(&g_wayland)
	fds: [2]linux.Poll_Fd
	fds[0] = linux.Poll_Fd {
		fd     = linux.Fd(wayland_fd),
		events = {.IN},
	}
	fds[1] = linux.Poll_Fd {
		fd     = linux.STDIN_FILENO,
		events = {.IN},
	}
	for {
		n, err := linux.poll(fds[:], -1)
		if err != .NONE {
			log.panic("poll failed")
		}
		if fds[0].revents & {.IN} != {} {
			gwin.dispatch_events(&g_wayland)
		}
		if fds[1].revents & {.IN} != {} {
			poll_commands(command_handler)
		}
	}
	shutdown()
}

event_handler :: proc(native: ^gwin.WaylandWindow, event_union: gwin.WindowEvent) {
	win := glow_get_window(&g_renderer, native.id)
	if win == nil {
		return
	}
	#partial switch event in event_union {
	case gwin.EventKeyDown:
		key, ok := map_xkb_keysym(event.keysym)
		if !ok {
			break
		}
		switch key {
		case KEY_Q:
			glow_destroy_window(&g_renderer, native.id)
			msg_window_destroyed(native.id)
			send_messages()
		case KEY_E:
			set_window_fullscreen(win, !native.fullscreen)
		case KEY_H:
			set_window_visible(win, false)
			msg_window_visible(win.id, false)
			send_messages()
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
		key, ok := map_xkb_keysym(event.keysym)
		if ok {
			on_window_input(win, key, false)
		}
	case gwin.EventKeyboardLeave:
		on_window_keyboard_leave(win)
	case gwin.EventPointerEnter:
		on_window_pointer_enter(win, event.x, event.y)
	case gwin.EventPointerMotion:
		on_window_pointer_motion(win, event.x, event.y)
	case gwin.EventPointerRelative:
		on_window_pointer_relative(win, event.dx, event.dy)
	case gwin.EventPointerButton:
		button, ok := map_wayland_mouse_button(event.button)
		if ok {
			on_window_input(win, button, event.pressed)
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
