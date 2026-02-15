package glow

import "core:log"
import "core:sync"
import "core:time"

import "gwin"
import vk "vendor:vulkan"

GlowWindow :: struct {
	id:              u32,
	native:          ^gwin.WaylandWindow,
	ren:             GlowRenderer,
	glow:            GlowContext,
	timer:           time.Stopwatch,
	suspended:       bool,
	compiler_worker: CompilerWorker,
	vk_surface:      vk.SurfaceKHR,
}

create_window :: proc(ctx: ^gwin.WaylandContext, window_id: u32, win: ^GlowWindow) {
	win.id = window_id
	native, success := gwin.create_window(ctx, window_id, "glow", 640, 360)
	if !success {
		log.panic("Failed to create Wayland window")
	}
	win.native = native

	surface, ok := gwin.create_vulkan_surface(native, g_ctx.instance)
	if !ok {
		log.panic("Failed to create Vulkan surface")
	}
	win.vk_surface = surface
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

	gwin.destroy_window(win.native)
}

window_toggle_suspended :: proc(win_ptr: ^GlowWindow) {
	suspended := sync.atomic_load(&win_ptr.suspended)
	if suspended {
		sync.atomic_store(&win_ptr.suspended, false)
		time.stopwatch_start(&win_ptr.timer)
	} else {
		sync.atomic_store(&win_ptr.suspended, true)
		time.stopwatch_stop(&win_ptr.timer)
	}
}

