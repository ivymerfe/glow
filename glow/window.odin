package glow

import "core:log"

import "glowr"
import "gwin"
import vk "vendor:vulkan"

GlowWindow :: struct {
	id:          u32,
	native:      ^gwin.WaylandWindow,
	ren:         glowr.Renderer,
	pbuf:        ProgramBuffer,
	res_index:   u32,
	visible:     bool,
	active:      bool,
	frame_index: int,
}

create_window :: proc(ctx: ^gwin.WaylandContext, window_id: u32, win: ^GlowWindow) {
	win.id = window_id
	native, wl_success := gwin.create_window(
		ctx,
		window_id,
		"glow",
		640,
		360,
		SWAPCHAIN_WIDTH,
		SWAPCHAIN_HEIGHT,
	)
	if !wl_success {
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
		g_ctx.index_allocator.max = glowr.MAX_IMAGES / IMAGES_PER_WINDOW
	}
	win.ren = glowr.create_renderer(
		g_ctx.vkc,
		&g_ctx.res,
		surface,
		SWAPCHAIN_WIDTH,
		SWAPCHAIN_HEIGHT,
	)
	res_index, res_success := alloc_index(&g_ctx.index_allocator)
	if !res_success {
		log.panic("Failed to allocate resource index for window")
	}
	win.res_index = res_index
	win.visible = true
	win.active = true
}

destroy_window :: proc(win: ^GlowWindow) {
	glowr.wait_renderer(&win.ren)
	glowr.destroy_renderer(&win.ren)

	free_index(&g_ctx.index_allocator, win.res_index)
	gwin.destroy_window(win.native)
}
