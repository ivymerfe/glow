package glow

import "base:runtime"
import "core:log"
import "core:time"

import slang "odin_slang"
import "vendor:sdl3"
import vk "vendor:vulkan"

g_win: GlowWindow

launch_time: time.Time

app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
	context = g_ctx.app
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

	win_start := time.now()
	create_window(&g_win)
	win_init_time := time.duration_milliseconds(time.diff(win_start, time.now()))
	log.infof("Window and Vulkan initialized in %.2f ms", win_init_time)

	return .CONTINUE
}

app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	context = g_ctx.app
	return .CONTINUE
}

app_event :: proc "c" (userdata: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
	context = g_ctx.app

	#partial switch event.type {
	case .QUIT:
		return .SUCCESS
	case .KEY_DOWN:
		if event.key.key == sdl3.K_Q {
			return .SUCCESS
		}
		if event.key.key == sdl3.K_F {
			flags := sdl3.GetWindowFlags(g_win.h)
			if .FULLSCREEN in flags {
				sdl3.SetWindowFullscreen(g_win.h, false)
			} else {
				sdl3.SetWindowFullscreen(g_win.h, true)
			}
		}
	case .WINDOW_PIXEL_SIZE_CHANGED:
		g_win.width = int(event.window.data1)
		g_win.height = int(event.window.data2)
	}
	return .CONTINUE
}

app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
	context = g_ctx.app

	// Destroy threads
	exit_window_threads(&g_win)

	vk.DeviceWaitIdle(g_ctx.vkc.device)
	// Destroy windows
	destroy_window(&g_win)

	destroy_vulkan_context(&g_ctx.vkc)
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
