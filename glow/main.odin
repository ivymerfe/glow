package glow

import "base:runtime"
import "core:log"
import "core:os"
import "core:sync"
import "core:sys/linux"
import "core:time"

import "glowr"
import "gwin"
import xkb "gwin/xkbcommon"
import "slang"
import vk "vendor:vulkan"


main :: proc() {
	context.logger = log.create_file_logger(os.stderr, log.Level.Debug)

	init_input()

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

	compiler_start(&g_ctx.compiler)
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
	#partial switch event in event_union {
	case gwin.EventKeyDown:
		switch event.keysym {
		case xkb.XKB_KEY_q:
			renderer_destroy_window(&g_ctx.renderer, native.id)
			msg_window_destroyed(native.id)
			send_messages()
		case xkb.XKB_KEY_f:
			gwin.set_window_fullscreen(native, !native.fullscreen)
		case xkb.XKB_KEY_v:
			win := renderer_get_window(&g_ctx.renderer, native.id)
			if win != nil {
				sync.atomic_store(&win.visible, false)
				gwin.set_window_visible(native, false)
				msg_window_visible(native.id, false)
				send_messages()
			}
		case xkb.XKB_KEY_s:
			win := renderer_get_window(&g_ctx.renderer, native.id)
			if win != nil {
				active := !sync.atomic_load(&win.active)
				set_window_active(win, active)
				if active {
					renderer_wakeup(&g_ctx.renderer)
				}
			}
		}
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
			gwin.set_window_visible(win.native, cmd.visible)
			sync.atomic_store(&win.visible, cmd.visible)
			if cmd.visible {
				renderer_wakeup(&g_ctx.renderer)
			}
		}
	case CmdWindowToggleFullscreen:
		win := renderer_get_window(&g_ctx.renderer, cmd.window_id)
		if win != nil {
			gwin.set_window_fullscreen(win.native, !win.native.fullscreen)
		}
	case CmdWindowToggleSuspend:
		win := renderer_get_window(&g_ctx.renderer, cmd.window_id)
		if win != nil {
			active := !sync.atomic_load(&win.active)
			set_window_active(win, active)
			if active {
				renderer_wakeup(&g_ctx.renderer)
			}
		}
	case CmdWindowProgram:
		win := renderer_get_window(&g_ctx.renderer, cmd.window_id)
		if win != nil {
			req := CompileRequest {
				buf    = &win.ren.context_buffer,
				path   = transmute(string)cmd.path,
				source = transmute(string)cmd.source,
			}
			compiler_submit(&g_ctx.compiler, req)
		}
	}
}

shutdown :: proc() {
	compiler_stop(&g_ctx.compiler)
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
