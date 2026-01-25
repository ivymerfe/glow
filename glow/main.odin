package glow

import "base:runtime"
import "core:log"
import "core:thread"
import "core:time"
import ren "renderer"
import "vendor:sdl3"
import vk "vendor:vulkan"

global_context: runtime.Context
vk_context: ren.VulkanContext
glow: ren.GlowRenderer
test_shader_module: vk.ShaderModule
test_pass: ren.RenderPass

window: ^sdl3.Window
render_thread: ^thread.Thread
timer: time.Stopwatch

should_present: bool
should_exit: bool
window_width: int
window_height: int

SWAPCHAIN_WIDTH :: 1920
SWAPCHAIN_HEIGHT :: 1080

app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
	context = global_context

	start := time.now()

	sdl3.SetHint(sdl3.HINT_APP_ID, "glow")
	sdl3.SetHint(sdl3.HINT_VIDEO_WAYLAND_SCALE_TO_DISPLAY, "0")
	sdl_res := sdl3.Init(sdl3.INIT_VIDEO)
	if !sdl_res {
		log.panic("Failed to initialize SDL3: %s", sdl3.GetError())
	}

	window = sdl3.CreateWindow(
		"glow",
		0,
		0,
		sdl3.WINDOW_VULKAN | sdl3.WINDOW_RESIZABLE | sdl3.WINDOW_BORDERLESS,
	)
	if window == nil {
		log.panic("Failed to create SDL3 window: %s", sdl3.GetError())
	}

	elapsed := time.duration_milliseconds(time.diff(start, time.now()))
	log.infof("SDL3 initialized in %.2f ms", elapsed)

	init_start := time.now()

	sdl3.ShowWindow(window)
	instance := ren.create_vk_instance()

	surface: vk.SurfaceKHR
	if !sdl3.Vulkan_CreateSurface(window, instance, nil, &surface) {
		log.panic("Failed to create Vulkan surface from SDL3 window: %s", sdl3.GetError())
	}

	vk_context = ren.create_vulkan_context(instance, surface)

	glow = ren.create_renderer(vk_context, surface, SWAPCHAIN_WIDTH, SWAPCHAIN_HEIGHT)

	init_elapsed := time.duration_milliseconds(time.diff(init_start, time.now()))
	log.infof("Vulkan initialized in %.2f ms", init_elapsed)

	test_module, success := ren.load_shader_module_file(&glow, "shaders/test_shader.spv")
	ensure(success, "Failed to load test shader module.")
	test_shader_module = test_module

	ren.create_render_pass(&test_pass, &glow, test_module)

	time.stopwatch_start(&timer)

	render_thread = thread.create_and_start(render_proc, nil)
	return .CONTINUE
}

render_proc :: proc() {
	context = global_context

	for !should_exit {
		push: ren.PushConstants
		push.time = f32(time.duration_seconds(time.stopwatch_duration(timer)))
		push.aspect_ratio = f32(window_width) / f32(window_height)
		ren.render_offscreen(&glow, &push, []ren.RenderPass{test_pass})
		should_present = true
		time.sleep(time.Millisecond * 10)
	}
}

app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	context = global_context
	if !should_present {
		return .CONTINUE
	}
	ren.present(&glow)
	return .CONTINUE
}

app_event :: proc "c" (userdata: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
	context = global_context

	#partial switch event.type {
	case .QUIT:
		return .SUCCESS
	case .KEY_DOWN:
		if event.key.key == sdl3.K_ESCAPE {
			return .SUCCESS
		}
	case .WINDOW_PIXEL_SIZE_CHANGED:
		window_width = int(event.window.data1)
		window_height = int(event.window.data2)
	case:

	}
	return .CONTINUE
}

app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
	context = global_context
	should_exit = true
	thread.join(render_thread)

	vk.DeviceWaitIdle(glow.device)

	ren.destroy_render_pass(&test_pass)
	vk.DestroyShaderModule(glow.device, test_shader_module, nil)
	ren.destroy_renderer(&glow)
	ren.destroy_vulkan_context(&vk_context)
	vk.DestroyInstance(vk_context.instance, nil)

	sdl3.DestroyWindow(window)
	sdl3.Quit()
	log.info("Goodbye")
}

main :: proc() {
	context.logger = log.create_console_logger()
	global_context = context


	argv := cstring("")
	sdl3.EnterAppMainCallbacks(0, &argv, app_init, app_iter, app_event, app_quit)
}
