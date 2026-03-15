package glow

import "core:log"
import "core:sync"
import "core:time"

import "glowr"
import "gwin"
import vk "vendor:vulkan"

GlowWindow :: struct {
	id:        u32,
	native:    ^gwin.WaylandWindow,
	ren:       glowr.Renderer,
	visible:   bool,
	active:    bool,
	timer:     time.Stopwatch,
	frame_idx: u32,
}

create_window :: proc(ctx: ^gwin.WaylandContext, window_id: u32, win: ^GlowWindow) {
	win.id = window_id
	native, success := gwin.create_window(
		ctx,
		window_id,
		"glow",
		640,
		360,
		SWAPCHAIN_WIDTH,
		SWAPCHAIN_HEIGHT,
	)
	if !success {
		log.panic("Failed to create Wayland window")
	}
	win.native = native

	surface, ok := gwin.create_vulkan_surface(native, g_ctx.instance)
	if !ok {
		log.panic("Failed to create Vulkan surface")
	}
	if g_ctx.vkc == {} {
		g_ctx.vkc = glowr.create_vulkan_context(g_ctx.instance, surface)
		glowr.create_resource_manager(&g_ctx.res, g_ctx.vkc, TARGET_WIDTH, TARGET_HEIGHT)
	}
	win.ren = glowr.create_renderer(g_ctx.vkc, surface, SWAPCHAIN_WIDTH, SWAPCHAIN_HEIGHT)
	win.visible = true
	win.active = true
	time.stopwatch_start(&win.timer)
}

destroy_window :: proc(win: ^GlowWindow) {
	glowr.wait_renderer(&win.ren)
	glowr.destroy_renderer(&win.ren)

	gwin.destroy_window(win.native)
}

set_window_active :: proc(win: ^GlowWindow, active: bool) {
	sync.atomic_store(&win.active, active)
	if active {
		time.stopwatch_start(&win.timer)
	} else {
		time.stopwatch_stop(&win.timer)
	}
}

should_render :: proc(win: ^GlowWindow) -> bool {
	return(
		sync.atomic_load(&win.visible) &&
		sync.atomic_load(&win.active) &&
		sync.atomic_load(&win.ren.program_buf.ready) \
	)
}
