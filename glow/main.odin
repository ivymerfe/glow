package glow

import "core:os"
import "base:runtime"
import "core:log"
import "core:time"

import "core:sync"
import "core:thread"

import "gwin"
import xkb "gwin/xkbcommon"
import slang "odin_slang"
import vk "vendor:vulkan"

g_wayland: gwin.WaylandContext
g_windows: map[u32]^GlowWindow
g_windowFences: [dynamic]vk.Fence

g_window_mtx: sync.Mutex
g_should_exit: bool

render_thread: ^thread.Thread

main :: proc() {
	context.logger = log.create_file_logger(os.stderr)

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

	render_thread = thread.create_and_start(render_proc, context)
	for gwin.dispatch_events(&g_wayland) {
		poll_commands(command_handler)
		time.sleep(time.Millisecond * 1)
	}
	shutdown()
}

create_app_window :: proc(window_id: u32) {
	_, ok := g_windows[window_id]
	if ok {
		return
	}
	win := new(GlowWindow)

	create_window(&g_wayland, window_id, win)
	g_windows[window_id] = win

	append(&g_windowFences, win.ren.render_fence)
}

destroy_app_window :: proc(window_id: u32) {
	sync.lock(&g_window_mtx)
	defer sync.unlock(&g_window_mtx)

	win := g_windows[window_id]
	if win == nil {
		return
	}

	window_fence := win.ren.render_fence
	fence_index := -1
	for fence, i in g_windowFences {
		if fence == window_fence {
			fence_index = i
			break
		}
	}
	if fence_index != -1 {
		unordered_remove(&g_windowFences, fence_index)
	}

	destroy_window(win)
	delete_key(&g_windows, window_id)
	free(win)

	msg_window_destroyed(window_id)
	send_messages()
}

event_handler :: proc(native: ^gwin.WaylandWindow, event_union: gwin.WindowEvent) {
	#partial switch event in event_union {
	case gwin.EventKeyDown:
		switch event.keysym {
		case xkb.XKB_KEY_q:
			destroy_app_window(native.id)
		case xkb.XKB_KEY_f:
			gwin.set_window_fullscreen(native, !native.fullscreen)
		case xkb.XKB_KEY_s:
			win := g_windows[native.id]
			if win != nil {
				window_toggle_suspended(win)
			}
		case xkb.XKB_KEY_v:
			win := g_windows[native.id]
			if win != nil {
				win.suspended = native.visible
				gwin.set_window_visible(native, !native.visible)
			}
		}

	}
}

command_handler :: proc(cmd_union: GlowCommand) {
	switch cmd in cmd_union {
	case CmdWindowCreate:
		create_app_window(cmd.window_id)
	case CmdWindowDestroy:
		destroy_app_window(cmd.window_id)
	case CmdWindowVisible:
		win := g_windows[cmd.window_id]
		if win != nil {
			sync.lock(&g_window_mtx)
			gwin.set_window_visible(win.native, cmd.visible)
			sync.unlock(&g_window_mtx)
			sync.atomic_store(&win.suspended, !cmd.visible)
		}
	case CmdWindowToggleFullscreen:
		win := g_windows[cmd.window_id]
		if win != nil {
			gwin.set_window_fullscreen(win.native, !win.native.fullscreen)
		}
	case CmdWindowToggleSuspend:
		win := g_windows[cmd.window_id]
		if win != nil {
			window_toggle_suspended(win)
		}
	case CmdWindowProgram:
		win := g_windows[cmd.window_id]
		if win != nil {
			program_info := ProgramInfo {
				path   = transmute(string)cmd.path,
				source = transmute(string)cmd.source,
			}
			compiler_worker_submit(&win.compiler_worker, program_info)
		}
	}
}

wait_for_window :: proc() {
	if len(g_ctx.fences) > 0 {
		vk_try(
			vk.WaitForFences(
				g_ctx.vkc.device,
				u32(len(g_ctx.fences)),
				raw_data(g_ctx.fences),
				false,
				max(u64),
			),
		)
	}
}

render_proc :: proc() {
	push: PushConstants
	for !sync.atomic_load(&g_should_exit) {
		sync.lock(&g_window_mtx)
		wait_for_window()
		rendered := false
		for _, win in g_windows {
			if sync.atomic_load(&win.suspended) {
				continue
			}
			if !win.native.configured {
				continue
			}
			width := f32(win.native.width) * win.native.scale
			height := f32(win.native.height) * win.native.scale
			push.time = f32(time.duration_seconds(time.stopwatch_duration(win.timer)))
			push.aspect_ratio = f32(width) / f32(height)
			render_info := RenderInfo {
				width     = u32(min(TARGET_WIDTH, width)),
				height    = u32(min(TARGET_HEIGHT, height)),
				constants = push,
			}
			rendered |= render(&win.ren, &win.glow, &render_info)
		}
		sync.unlock(&g_window_mtx)

		if !rendered {
			time.sleep(time.Millisecond * 1)
		}
	}
}

shutdown :: proc() {
	sync.atomic_store(&g_should_exit, true)
	thread.join(render_thread)

	if g_ctx.vkc.device != {} {
		vk.DeviceWaitIdle(g_ctx.vkc.device)

		for _, glow_win in g_windows {
			destroy_window(glow_win)
		}
		destroy_vulkan_context(&g_ctx.vkc)
	}
	if g_ctx.instance != {} {
		vk.DestroyInstance(g_ctx.instance, nil)
	}
	if g_ctx.slang != nil {
		g_ctx.slang->release()
	}
	gwin.destroy_wayland_context(&g_wayland)

	delete(g_windows)
	delete(g_windowFences)

	log.info("Goodbye")
}

