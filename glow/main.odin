package glow

import "base:runtime"
import "core:log"
import "core:thread"
import "core:time"

import wl "lib/wayland_client"
import ren "renderer"
import vk "vendor:vulkan"

vk_context: ren.VulkanContext
glow: ren.GlowRenderer

main :: proc() {
	context.logger = log.create_console_logger()

	init_wayland()
	defer destroy_wayland()

	instance := ren.create_vk_instance()
	defer vk.DestroyInstance(instance, nil)

	wl_create_surface_info := vk.WaylandSurfaceCreateInfoKHR {
		sType   = .WAYLAND_SURFACE_CREATE_INFO_KHR,
		display = auto_cast wayland_context.display,
		surface = auto_cast window.surface,
	}
	vk_surface: vk.SurfaceKHR
	ren.vk_try(vk.CreateWaylandSurfaceKHR(instance, &wl_create_surface_info, nil, &vk_surface))

	wl.display_roundtrip(wayland_context.display)

	vk_context = ren.create_vulkan_context(instance, vk_surface)
	defer ren.destroy_vulkan_context(&vk_context)

	window_width, window_height := get_window_size()
	glow = ren.create_renderer(vk_context, vk_surface, window_width, window_height)
	defer ren.destroy_renderer(&glow)

	render_thread := thread.create_and_start(render_proc, nil)

	wayland_main()

	thread.join(render_thread)
	log.info("Goodbye")
}

resize_renderer :: proc() {
	upper_bound :: proc(value: int, multiple: int) -> int {
		return (value / multiple + 1) * multiple
	}
	new_width := max(glow.swapchain_width, upper_bound(glow.window_width, 100))
	new_height := max(glow.swapchain_height, upper_bound(glow.window_height, 100))
	if glow.swapchain_width < new_width || glow.swapchain_height < new_height {
		ren.resize_swapchain(&glow, new_width, new_height)
	}
}

render_proc :: proc() {
	context = global_context

	test_module, success := ren.load_shader_module_file(&glow, "shaders/test_shader.spv")
	defer vk.DestroyShaderModule(glow.device, test_module, nil)
	ensure(success, "Failed to load test shader module.")

	test_pass: ren.RenderPass
	ren.create_render_pass(&test_pass, &glow, test_module)
	defer ren.destroy_render_pass(&test_pass)
	passes := []ren.RenderPass{test_pass}

	timer: time.Stopwatch
	time.stopwatch_start(&timer)

	for !should_exit() {
		width, height := get_window_size()
		glow.window_width = width
		glow.window_height = height
		if should_resize() {
			resize_renderer()
			handle_resize()
		}
		push: ren.PushConstants
		push.time = f32(time.duration_seconds(time.stopwatch_duration(timer)))
		push.aspect_ratio = f32(glow.window_width) / f32(glow.window_height)
		push.frame_index += 1
		ren.render(&glow, &push, passes)
	}
	vk.DeviceWaitIdle(glow.device)
}
