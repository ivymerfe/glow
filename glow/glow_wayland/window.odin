package glow_wayland

import "core:log"
import "core:sync"
import "core:time"

import glow "../glow_base"
import "gwin"
import vk "vendor:vulkan"

GlowWindow :: struct {
	id:      u32,
	native:  ^gwin.WaylandWindow,
	ren:     glow.GlowRenderer,
	visible: bool,
	active:  bool,
	timer:   time.Stopwatch,
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
	if g_ctx.vkc == {} {
		g_ctx.vkc = glow.create_vulkan_context(g_ctx.instance, surface)
		glow.create_resource_manager(&g_ctx.res, g_ctx.vkc, TARGET_WIDTH, TARGET_HEIGHT)
	}
	win.ren = glow.create_renderer(g_ctx.vkc, surface, SWAPCHAIN_WIDTH, SWAPCHAIN_HEIGHT)
	win.visible = true
	win.active = true
	time.stopwatch_start(&win.timer)
}

destroy_window :: proc(win: ^GlowWindow) {
	glow.wait_renderer(&win.ren)
	glow.destroy_renderer(&win.ren)

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
		sync.atomic_load(&win.ren.context_buffer.ready) \
	)
}
