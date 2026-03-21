package glow

import "base:runtime"
import "core:log"
import "core:os"
import "core:sync"
import "core:sys/linux"
import "core:time"

import "glowr"
import "gwin"
import "slang"
import vk "vendor:vulkan"


main :: proc() {
	context.logger = log.create_file_logger(os.stderr, log.Level.Info)

	init_input()
	init_keymap()

	launch_time := time.now()
	if !gwin.create_wayland_context(&g_ctx.wayland, event_handler) {
		log.panic("Failed to initialize window system")
	}
	wl_init_end := time.now()
	wl_init_time := time.duration_milliseconds(time.diff(launch_time, wl_init_end))
	log.infof("Wl init -> %.2f ms", wl_init_time)

	g_ctx.instance = glowr.create_vk_instance()
	vk_init_end := time.now()
	vk_init_time := time.duration_milliseconds(time.diff(wl_init_end, vk_init_end))
	log.infof("Vk init -> %.2f ms", vk_init_time)

	glowr.slang_check(slang.createGlobalSession(slang.API_VERSION, &g_ctx.slang))
	slang_init_time := time.duration_milliseconds(time.diff(vk_init_end, time.now()))
	log.infof("Slang init -> %.2f ms", slang_init_time)

	renderer_start(&g_ctx.renderer)

	wayland_fd := gwin.get_display_fd(&g_ctx.wayland)
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
			gwin.dispatch_events(&g_ctx.wayland)
		}
		if fds[1].revents & {.IN} != {} {
			poll_commands(command_handler)
		}
	}
	shutdown()
}

event_handler :: proc(native: ^gwin.WaylandWindow, event_union: gwin.WindowEvent) {
	win := renderer_get_window(&g_ctx.renderer, native.id)
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
			renderer_destroy_window(&g_ctx.renderer, native.id)
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
				renderer_wakeup(&g_ctx.renderer)
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
		renderer_new_window(&g_ctx.renderer, cmd.window_id)
	case CmdWindowDestroy:
		renderer_destroy_window(&g_ctx.renderer, cmd.window_id)
	case CmdWindowVisible:
		win := renderer_get_window(&g_ctx.renderer, cmd.window_id)
		if win != nil {
			set_window_visible(win, cmd.visible)
		}
	case CmdWindowToggleFullscreen:
		win := renderer_get_window(&g_ctx.renderer, cmd.window_id)
		if win != nil {
			gwin.set_window_fullscreen(win.native, !win.native.fullscreen)
		}
	case CmdWindowProgram:
		win := renderer_get_window(&g_ctx.renderer, cmd.window_id)
		if win != nil {
			path := transmute(string)cmd.path
			source := transmute(string)cmd.source
			pbuf_update_source(&win.pbuf, path, source)
			compiler_wakeup(&g_ctx.renderer)
		}
	}
}

shutdown :: proc() {
	renderer_stop(&g_ctx.renderer)

	if g_ctx.vkc.device != {} {
		vk.DeviceWaitIdle(g_ctx.vkc.device)
		renderer_destroy_all_windows(&g_ctx.renderer)
		glowr.destroy_resource_manager(&g_ctx.res)
		glowr.destroy_vulkan_context(&g_ctx.vkc)
	}
	if g_ctx.instance != {} {
		vk.DestroyInstance(g_ctx.instance, nil)
	}
	if g_ctx.slang != nil {
		g_ctx.slang->release()
	}
	gwin.destroy_wayland_context(&g_ctx.wayland)
	log.info("Goodbye")
}
