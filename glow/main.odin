package glow

import "base:runtime"
import "core:log"
import "core:time"

import "core:os"
import "core:sync"
import "core:thread"

import slang "odin_slang"
import "vendor:sdl3"
import vk "vendor:vulkan"

g_windows: map[u32]^GlowWindow
g_windowIdMap: map[sdl3.WindowID]u32
g_windowFences: [dynamic]vk.Fence

g_window_mtx: sync.Mutex
g_should_exit: bool
g_render_thread: ^thread.Thread

launch_time: time.Time

app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
	context = g_ctx.app

	init_input()

	launch_time = time.now()

	sdl3.SetHint(sdl3.HINT_APP_ID, "glow")
	sdl_res := sdl3.Init(sdl3.INIT_VIDEO)
	if !sdl_res {
		log.panic("Failed to initialize SDL3: %s", sdl3.GetError())
	}
	sdl_init_time := time.duration_milliseconds(time.diff(launch_time, time.now()))
	log.infof("SDL3 initialized in %.2f ms", sdl_init_time)

	vk_init_start := time.now()

	g_ctx.instance = create_vk_instance()

	slang_init_start := time.now()
	slang_check(slang.createGlobalSession(slang.API_VERSION, &g_ctx.slang))
	slang_init_time := time.duration_milliseconds(time.diff(slang_init_start, time.now()))
	log.infof("Slang initialized in %.2f ms", slang_init_time)

	g_render_thread = thread.create_and_start(render_proc, context)

	return .CONTINUE
}

create_app_window :: proc(window_id: u32) {
	sync.lock(&g_window_mtx)
	defer sync.unlock(&g_window_mtx)

	_, ok := g_windows[window_id]
	if ok {
		return
	}

	win := new(GlowWindow)

	create_window(window_id, win)
	g_windows[window_id] = win
	g_windowIdMap[win.sdl_id] = window_id

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
	delete_key(&g_windowIdMap, win.sdl_id)
	delete_key(&g_windows, window_id)
	free(win)
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
			if cmd.visible {
				sdl3.ShowWindow(win.h)
			} else {
				sdl3.HideWindow(win.h)
			}
			sync.atomic_store(&win.suspended, !cmd.visible)
		}
	case CmdWindowFullscreen:
		win := g_windows[cmd.window_id]
		if win != nil {
			sdl3.SetWindowFullscreen(win.h, cmd.fullscreen)
		}
	case CmdWindowSuspend:
		win := g_windows[cmd.window_id]
		if win != nil {
			sync.atomic_store(&win.suspended, cmd.suspend)
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

app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	context = g_ctx.app
	poll_commands(command_handler)

	time.sleep(time.Millisecond * 1)
	return .CONTINUE
}

app_event :: proc "c" (userdata: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
	context = g_ctx.app

	#partial switch event.type {
	case .QUIT:
		return .SUCCESS
	case .KEY_DOWN:
		window_id := g_windowIdMap[event.window.windowID]
		win := g_windows[window_id]
		if win == nil {
			break
		}
		if event.key.key == sdl3.K_Q {
			destroy_app_window(window_id)
		}
		if event.key.key == sdl3.K_F {
			flags := sdl3.GetWindowFlags(win.h)
			if .FULLSCREEN in flags {
				sdl3.SetWindowFullscreen(win.h, false)
			} else {
				sdl3.SetWindowFullscreen(win.h, true)
			}
		}
	case .WINDOW_PIXEL_SIZE_CHANGED:
		window_id := g_windowIdMap[event.window.windowID]
		win := g_windows[window_id]
		if win != nil {
			win.width = int(event.window.data1)
			win.height = int(event.window.data2)
		}
	}
	return .CONTINUE
}

wait_for_some_window :: proc() {
	if len(g_ctx.fences) == 0 {
		return
	}
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

render_proc :: proc() {
	push: PushConstants

	for !sync.atomic_load(&g_should_exit) {
		sync.lock(&g_window_mtx)

		wait_for_some_window()

		rendered := false
		for _, win in g_windows {
			if sync.atomic_load(&win.suspended) {
				continue
			}
			push.time = f32(time.duration_seconds(time.stopwatch_duration(win.timer)))
			push.aspect_ratio = f32(win.width) / f32(win.height)
			render_info := RenderInfo {
				width     = u32(min(TARGET_WIDTH, win.width)),
				height    = u32(min(TARGET_HEIGHT, win.height)),
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

app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
	context = g_ctx.app

	sync.atomic_store(&g_should_exit, true)
	thread.destroy(g_render_thread)

	if g_ctx.vkc.device != {} {
		vk.DeviceWaitIdle(g_ctx.vkc.device)

		for _, win in g_windows {
			destroy_window(win)
		}

		destroy_vulkan_context(&g_ctx.vkc)
	}
	vk.DestroyInstance(g_ctx.instance, nil)

	g_ctx.slang->release()

	sdl3.Quit()
	log.info("Goodbye")
}

main :: proc() {
	context.logger = log.create_console_logger()
	g_ctx.app = context

	argv := cstring("")
	sdl3.EnterAppMainCallbacks(0, &argv, app_init, app_iter, app_event, app_quit)
}
