package glow

import "base:runtime"
import "core:log"
import "core:os"
import "core:sys/linux"
import "core:time"

import "core:sync"
import "core:thread"

import "gwin"
import xkb "gwin/xkbcommon"
import slang "odin_slang"
import vk "vendor:vulkan"

g_wayland: gwin.WaylandContext
g_windows: map[u32]^GlowWindow

g_compiler: CompilerThread

g_render_thread: ^thread.Thread
g_window_mtx: sync.Mutex
g_should_exit: bool
g_wakeup_renderer: sync.Auto_Reset_Event

main :: proc() {
	context.logger = log.create_file_logger(os.stderr, log.Level.Debug)

	init_input()

	launch_time := time.now()
	if !gwin.create_wayland_context(&g_wayland, event_handler) {
		log.panic("Failed to initialize window system")
	}
	wl_init_end := time.now()
	wl_init_time := time.duration_milliseconds(time.diff(launch_time, wl_init_end))
	log.infof("Wl init -> %.2f ms", wl_init_time)

	g_ctx.instance = create_vk_instance()
	vk_init_end := time.now()
	vk_init_time := time.duration_milliseconds(time.diff(wl_init_end, vk_init_end))
	log.infof("Vk init -> %.2f ms", vk_init_time)

	slang_check(slang.createGlobalSession(slang.API_VERSION, &g_ctx.slang))
	slang_init_time := time.duration_milliseconds(time.diff(vk_init_end, time.now()))
	log.infof("Slang init -> %.2f ms", slang_init_time)

	compiler_start(&g_compiler)
	g_render_thread = thread.create_and_start(render_proc, context)

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

app_create_window :: proc(window_id: u32) {
	_, ok := g_windows[window_id]
	if ok {
		return
	}
	win := new(GlowWindow)
	ctx := new(GlowContext)

	create_window(&g_wayland, window_id, win)
	sync.lock(&g_window_mtx)
	g_windows[window_id] = win
	sync.unlock(&g_window_mtx)
}

app_destroy_window :: proc(window_id: u32) {
	win := g_windows[window_id]
	if win == nil {
		return
	}
	sync.lock(&g_window_mtx)
	destroy_window(win)
	delete_key(&g_windows, window_id)
	sync.unlock(&g_window_mtx)
	free(win)

	msg_window_destroyed(window_id)
	send_messages()
}

event_handler :: proc(native: ^gwin.WaylandWindow, event_union: gwin.WindowEvent) {
	#partial switch event in event_union {
	case gwin.EventKeyDown:
		switch event.keysym {
		case xkb.XKB_KEY_q:
			app_destroy_window(native.id)
		case xkb.XKB_KEY_f:
			gwin.set_window_fullscreen(native, !native.fullscreen)
		case xkb.XKB_KEY_v:
			win := g_windows[native.id]
			if win != nil {
				sync.atomic_store(&win.visible, false)
				gwin.set_window_visible(native, false)
				msg_window_visible(native.id, false)
				send_messages()
			}
		case xkb.XKB_KEY_s:
			win := g_windows[native.id]
			if win != nil {
				active := !sync.atomic_load(&win.active)
				set_window_active(win, active)
				if active {
					sync.auto_reset_event_signal(&g_wakeup_renderer)
				}
			}
		}
	}
}

command_handler :: proc(cmd_union: GlowCommand) {
	switch cmd in cmd_union {
	case CmdWindowCreate:
		app_create_window(cmd.window_id)
	case CmdWindowDestroy:
		app_destroy_window(cmd.window_id)
	case CmdWindowVisible:
		win := g_windows[cmd.window_id]
		if win != nil {
			gwin.set_window_visible(win.native, cmd.visible)
			sync.atomic_store(&win.visible, cmd.visible)
			if cmd.visible {
				sync.auto_reset_event_signal(&g_wakeup_renderer)
			}
		}
	case CmdWindowToggleFullscreen:
		win := g_windows[cmd.window_id]
		if win != nil {
			gwin.set_window_fullscreen(win.native, !win.native.fullscreen)
		}
	case CmdWindowToggleSuspend:
		win := g_windows[cmd.window_id]
		if win != nil {
			active := !sync.atomic_load(&win.active)
			set_window_active(win, active)
			if active {
				sync.auto_reset_event_signal(&g_wakeup_renderer)
			}
		}
	case CmdWindowProgram:
		win := g_windows[cmd.window_id]
		if win != nil {
			req := CompileRequest {
				ren    = &win.ren,
				path   = transmute(string)cmd.path,
				source = transmute(string)cmd.source,
			}
			compiler_submit(&g_compiler, req)
		}
	}
}

render_proc :: proc() {
	push: PushConstants
	fences := make([dynamic]vk.Fence)
	for !sync.atomic_load(&g_should_exit) {
		clear(&fences)
		sync.lock(&g_window_mtx)
		for _, win in g_windows {
			if should_render(win) {
				append(&fences, win.ren.render_fence)
			}
		}
		sync.unlock(&g_window_mtx)

		rendered := false
		if len(fences) > 0 {
			vk_try(
				vk.WaitForFences(
					g_ctx.vkc.device,
					u32(len(fences)),
					raw_data(fences),
					false,
					max(u64),
				),
			)
			sync.lock(&g_window_mtx)
			for _, win in g_windows {
				if should_render(win) {
					width := f32(win.native.width) * win.native.scale
					height := f32(win.native.height) * win.native.scale
					push.time = f32(time.duration_seconds(time.stopwatch_duration(win.timer)))
					push.aspect_ratio = f32(width) / f32(height)
					render_info := RenderInfo {
						width     = u32(min(TARGET_WIDTH, width)),
						height    = u32(min(TARGET_HEIGHT, height)),
						constants = push,
					}
					rendered |= render(&win.ren, &render_info)
				}
			}
			sync.unlock(&g_window_mtx)
		}
		if !rendered {
			sync.auto_reset_event_wait(&g_wakeup_renderer)
		}
	}
}

shutdown :: proc() {
	compiler_stop(&g_compiler)
	sync.atomic_store(&g_should_exit, true)
	sync.auto_reset_event_signal(&g_wakeup_renderer)
	thread.join(g_render_thread)

	if g_ctx.vkc.device != {} {
		vk.DeviceWaitIdle(g_ctx.vkc.device)
		for _, glow_win in g_windows {
			destroy_window(glow_win)
		}
		destroy_resource_manager(&g_ctx.res)
		destroy_vulkan_context(&g_ctx.vkc)
	}
	if g_ctx.instance != {} {
		vk.DestroyInstance(g_ctx.instance, nil)
	}
	if g_ctx.slang != nil {
		g_ctx.slang->release()
	}
	gwin.destroy_wayland_context(&g_wayland)
	log.info("Goodbye")
}
