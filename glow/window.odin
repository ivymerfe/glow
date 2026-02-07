package glow

import "core:log"
import "core:time"

import "vendor:sdl3"
import vk "vendor:vulkan"

GlowWindow :: struct {
	id:              u32,
	sdl_id:          sdl3.WindowID,
	h:               ^sdl3.Window,
	width:           int,
	height:          int,
	ren:             GlowRenderer,
	glow:            GlowContext,
	timer:           time.Stopwatch,
	suspended:       bool,
	compiler_worker: CompilerWorker,
}

create_window :: proc(window_id: u32, win: ^GlowWindow) {
	win.id = window_id
	win.h = sdl3.CreateWindow(
		"glow",
		0,
		0,
		sdl3.WINDOW_VULKAN | sdl3.WINDOW_RESIZABLE | sdl3.WINDOW_BORDERLESS,
	)
	if win.h == nil {
		log.panic("Failed to create SDL3 window: %s", sdl3.GetError())
	}
	win.sdl_id = sdl3.GetWindowID(win.h)

	surface: vk.SurfaceKHR
	if !sdl3.Vulkan_CreateSurface(win.h, g_ctx.instance, nil, &surface) {
		log.panic("Failed to create Vulkan surface from SDL3 window: %s", sdl3.GetError())
	}
	if g_ctx.vkc == {} {
		g_ctx.vkc = create_vulkan_context(g_ctx.instance, surface)
	}
	win.ren = create_renderer(g_ctx.vkc, surface, SWAPCHAIN_WIDTH, SWAPCHAIN_HEIGHT)
	win.glow = create_glow_context(g_ctx.vkc, TARGET_WIDTH, TARGET_HEIGHT)
	compiler_worker_start(&win.compiler_worker, &win.glow)
	time.stopwatch_start(&win.timer)
}

destroy_window :: proc(win: ^GlowWindow) {
	compiler_worker_stop(&win.compiler_worker)
	
	wait_renderer(&win.ren)
	destroy_glow_context(&win.glow)
	destroy_renderer(&win.ren)

	sdl3.DestroyWindow(win.h)
}
