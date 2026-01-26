package glow

import "base:runtime"
import "core:log"

import "core:thread"

import "core:time"
import ren "renderer"
import "vendor:sdl3"
import vk "vendor:vulkan"

import fw "file_watcher"

app_context: runtime.Context
vk_context: ren.VulkanContext
glow: ren.GlowRenderer
test_shader_module: vk.ShaderModule
test_pass: ren.RenderPass

window: ^sdl3.Window
timer: time.Stopwatch

should_present: bool
window_width: int
window_height: int

watcher: fw.LinuxFileWatcher
shader_wd: fw.WatchDescriptor
watcher_thread: ^thread.Thread

SWAPCHAIN_WIDTH :: 1920
SWAPCHAIN_HEIGHT :: 1080

app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
	context = app_context

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

	err: fw.Err
	watcher, err = fw.create_watcher(watch_callback)
	if err != .NONE {
		log.panicf("Failed to create file watcher: %s", err)
	}
	shader_wd, err = fw.add_file_watch(&watcher, "shaders/test.slang")
	if err != .NONE {
		log.panicf("Failed to add file watch: %s", err)
	}
	watcher_thread = thread.create_and_start(watcher_proc, app_context)

	time.stopwatch_start(&timer)
	should_present = true
	return .CONTINUE
}

app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	context = app_context
	if !should_present {
		return .CONTINUE
	}
	glow.target_width = window_width
	glow.target_height = window_height
	push: ren.PushConstants
	push.time = f32(time.duration_seconds(time.stopwatch_duration(timer)))
	push.aspect_ratio = f32(window_width) / f32(window_height)
	ren.render(&glow, &push, []ren.RenderPass{test_pass})
	return .CONTINUE
}

app_event :: proc "c" (userdata: rawptr, event: ^sdl3.Event) -> sdl3.AppResult {
	context = app_context

	#partial switch event.type {
	case .QUIT:
		return .SUCCESS
	case .KEY_DOWN:
		if event.key.key == sdl3.K_Q {
			return .SUCCESS
		}
	case .WINDOW_PIXEL_SIZE_CHANGED:
		window_width = int(event.window.data1)
		window_height = int(event.window.data2)
	}
	return .CONTINUE
}

app_quit :: proc "c" (appstate: rawptr, result: sdl3.AppResult) {
	context = app_context

	fw.destroy_watcher(&watcher)
	thread.join(watcher_thread)

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

watch_callback :: proc(event: ^fw.WatchEvent) {
	if .MODIFY in event.mask {
		log.info("Shader modified")
	}
}

watcher_proc :: proc() {
	log.info("Waiting for file changes")
	for {
		should_close, err := fw.wait_for_events(&watcher)
		if err != .NONE {
			log.infof("Error waiting for file events: %s", err)
			break
		}
		if should_close {
			break
		}
		fw.dispatch_events(&watcher)
	}
}

main :: proc() {
	context.logger = log.create_console_logger()
	app_context = context

	argv := cstring("")
	sdl3.EnterAppMainCallbacks(0, &argv, app_init, app_iter, app_event, app_quit)
}
