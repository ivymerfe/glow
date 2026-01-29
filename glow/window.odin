package glow

import "core:log"
import "core:time"

import slang "odin_slang"
import "vendor:sdl3"
import vk "vendor:vulkan"

GlowWindow :: struct {
	h:           ^sdl3.Window,
	width:       int,
	height:      int,
	ren:         GlowRenderer,
	glow:        GlowContext,
	timer:       time.Stopwatch,
	session:     ^slang.ISession,
	fence_index: int,
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

	win.fence_index = len(g_ctx.fences)
	append(&g_ctx.fences, win.ren.render_fence)

	win.glow = create_glow_context(g_ctx.vkc, TARGET_WIDTH, TARGET_HEIGHT)
	win.session = create_slang_session()
}

destroy_window :: proc(win: ^GlowWindow) {
	win.session->release()

	destroy_glow_context(&win.glow)

	wait_renderer(&win.ren)
	unordered_remove(&g_ctx.fences, win.fence_index)
	destroy_renderer(&win.ren)

	sdl3.DestroyWindow(win.h)
}
