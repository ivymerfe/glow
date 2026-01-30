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

g_win: GlowWindow
g_render_mtx: sync.Mutex
g_destroy_mtx: sync.Mutex
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

	win_start := time.now()
	create_window(&g_win)
	win_init_time := time.duration_milliseconds(time.diff(win_start, time.now()))
	log.infof("Window and Vulkan initialized in %.2f ms", win_init_time)

	g_render_thread = thread.create_and_start(render_proc, context)
	thread.create_and_start(compiler_proc, context)

	return .CONTINUE
}


app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	context = g_ctx.app

	cmd, success := read_command()
	if success {

	}

	time.sleep(time.Millisecond * 1)
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
	time.stopwatch_start(&g_win.timer)
	push: PushConstants

	for !sync.atomic_load(&g_should_exit) {
		sync.lock(&g_destroy_mtx)
		wait_for_some_window()

		push.time = f32(time.duration_seconds(time.stopwatch_duration(g_win.timer)))
		push.aspect_ratio = f32(g_win.width) / f32(g_win.height)
		render_info := RenderInfo {
			width     = u32(min(TARGET_WIDTH, g_win.width)),
			height    = u32(min(TARGET_HEIGHT, g_win.height)),
			constants = push,
		}
		rendered := false

		sync.lock(&g_render_mtx)
		if g_win.glow.program_loaded {
			rendered |= render(&g_win.ren, &g_win.glow, &render_info)
		}
		sync.unlock(&g_render_mtx)

		sync.unlock(&g_destroy_mtx)

		if !rendered {
			time.sleep(time.Millisecond * 1)
		}
	}
}

compiler_proc :: proc() {
	compile_start := time.now()
	shader_content, success := os.read_entire_file("shaders/test.slang")
	ensure(success, "Failed to read shader file")

	shader := compile_program(g_win.session, "shaders/test.slang", cstring(&shader_content[0]))
	compile_time := time.duration_milliseconds(time.diff(compile_start, time.now()))
	log.infof("Shader compiled in %.2f ms", compile_time)

	sync.lock(&g_render_mtx)
	load_program(&g_win.glow, shader)
	sync.unlock(&g_render_mtx)
}

app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
	context = g_ctx.app

	// Destroy threads
	sync.atomic_store(&g_should_exit, true)
	thread.join(g_render_thread)

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
