package glow

import "core:log"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

import slang "odin_slang"
import "vendor:sdl3"
import vk "vendor:vulkan"

GlowWindow :: struct {
	h:               ^sdl3.Window,
	width:           int,
	height:          int,
	ren:             GlowRenderer,
	glow:            GlowContext,
	render_thread:   ^thread.Thread,
	compiler_thread: ^thread.Thread,
	mtx:             sync.Mutex,
	should_exit:     bool,
	timer:           time.Stopwatch,
	session:         ^slang.ISession,
}

create_window :: proc(win: ^GlowWindow) {
	win.h = sdl3.CreateWindow(
		"glow",
		0,
		0,
		sdl3.WINDOW_VULKAN | sdl3.WINDOW_RESIZABLE | sdl3.WINDOW_BORDERLESS,
	)
	if win.h == nil {
		log.panic("Failed to create SDL3 window: %s", sdl3.GetError())
	}
	surface: vk.SurfaceKHR
	if !sdl3.Vulkan_CreateSurface(win.h, g_ctx.instance, nil, &surface) {
		log.panic("Failed to create Vulkan surface from SDL3 window: %s", sdl3.GetError())
	}
	if g_ctx.vkc == {} {
		g_ctx.vkc = create_vulkan_context(g_ctx.instance, surface)
	}
	win.ren = create_renderer(g_ctx.vkc, surface, SWAPCHAIN_WIDTH, SWAPCHAIN_HEIGHT)
	win.glow = create_glow_context(g_ctx.vkc, TARGET_WIDTH, TARGET_HEIGHT)
	win.session = create_slang_session()
	win.render_thread = thread.create_and_start_with_data(win, render_proc, context)
	win.compiler_thread = thread.create_and_start_with_data(win, compiler_proc, context)
}

render_proc :: proc(win_raw: rawptr) {
	win := cast(^GlowWindow)win_raw

	time.stopwatch_start(&win.timer)
	push: PushConstants

	for !sync.atomic_load(&win.should_exit) {
		push.time = f32(time.duration_seconds(time.stopwatch_duration(win.timer)))
		push.aspect_ratio = f32(win.width) / f32(win.height)
		render_info := RenderInfo {
			width     = u32(min(TARGET_WIDTH, win.width)),
			height    = u32(min(TARGET_HEIGHT, win.height)),
			constants = push,
		}

		sync.lock(&win.mtx)
		if win.glow.program_loaded {
			render(&win.ren, &win.glow, &render_info)
		}
		sync.unlock(&win.mtx)
	}
}

compiler_proc :: proc(win_raw: rawptr) {
	win := cast(^GlowWindow)win_raw

	compile_start := time.now()
	shader_content, success := os.read_entire_file("shaders/test.slang")
	ensure(success, "Failed to read shader file")

	shader := compile_program(win.session, "shaders/test.slang", cstring(&shader_content[0]))
	compile_time := time.duration_milliseconds(time.diff(compile_start, time.now()))
	log.infof("Shader compiled in %.2f ms", compile_time)

	sync.lock(&win.mtx)
	load_program(&win.glow, shader)
	sync.unlock(&win.mtx)
}

exit_window_threads :: proc(win: ^GlowWindow) {
	sync.atomic_store(&win.should_exit, true)
	if win.render_thread != nil {
		thread.join(win.render_thread)
		win.render_thread = nil
	}
	if win.compiler_thread != nil {
		thread.join(win.compiler_thread)
		win.compiler_thread = nil
	}
}

destroy_window :: proc(win: ^GlowWindow) {
	win.session->release()

	destroy_glow_context(&win.glow)
	destroy_renderer(&win.ren)
	sdl3.DestroyWindow(win.h)
}
