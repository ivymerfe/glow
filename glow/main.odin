package glow

import "base:runtime"
import "core:log"
import "core:os"
import "core:sync"
import "core:thread"
import "core:time"

import "vendor:sdl3"
import vk "vendor:vulkan"

app_context: runtime.Context
vk_context: VulkanContext
renderer: GlowRenderer
glow: GlowContext

compiler: GlowCompiler
compiler_thread: ^thread.Thread
glow_mutex: sync.Mutex
glow_init: sync.One_Shot_Event

window: ^sdl3.Window

should_present: bool
window_width: int
window_height: int

launch_time: time.Time
got_first_frame: bool

timer: time.Stopwatch

SWAPCHAIN_WIDTH :: 1920
SWAPCHAIN_HEIGHT :: 1080
TARGET_WIDTH :: 1920
TARGET_HEIGHT :: 1080

app_init :: proc "c" (appstate: ^rawptr, argc: i32, argv: [^]cstring) -> sdl3.AppResult {
	context = app_context
	launch_time = time.now()

	compiler_thread = thread.create_and_start(compiler_proc, context)

	sdl3.SetHint(sdl3.HINT_APP_ID, "glow")
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

	sdl_init_time := time.duration_milliseconds(time.diff(launch_time, time.now()))
	log.infof("SDL3 initialized in %.2f ms", sdl_init_time)

	vk_init_start := time.now()

	sdl3.ShowWindow(window)
	instance := create_vk_instance()

	surface: vk.SurfaceKHR
	if !sdl3.Vulkan_CreateSurface(window, instance, nil, &surface) {
		log.panic("Failed to create Vulkan surface from SDL3 window: %s", sdl3.GetError())
	}

	vk_context = create_vulkan_context(instance, surface)

	renderer = create_renderer(vk_context, surface, SWAPCHAIN_WIDTH, SWAPCHAIN_HEIGHT)

	vk_init_time := time.duration_milliseconds(time.diff(vk_init_start, time.now()))
	log.infof("Vulkan initialized in %.2f ms", vk_init_time)

	ctx_init_start := time.now()
	glow = create_glow_context(vk_context, TARGET_WIDTH, TARGET_HEIGHT)
	ctx_init_time := time.duration_milliseconds(time.diff(ctx_init_start, time.now()))
	log.infof("Glow context initialized in %.2f ms", ctx_init_time)

	time.stopwatch_start(&timer)
	should_present = true
	sync.one_shot_event_signal(&glow_init)
	return .CONTINUE
}

compiler_proc :: proc() {
	compiler_init_start := time.now()
	compiler = create_glow_compiler()
	compiler_init_time := time.duration_milliseconds(time.diff(compiler_init_start, time.now()))
	log.infof("Compiler initialized in %.2f ms", compiler_init_time)

	compile_start := time.now()
	shader_content, success := os.read_entire_file("shaders/test.slang")
	ensure(success, "Failed to read shader file")

	shader := compile_program(&compiler, "shaders/test.slang", cstring(&shader_content[0]))
	compile_time := time.duration_milliseconds(time.diff(compile_start, time.now()))
	log.infof("Shader compiled in %.2f ms", compile_time)

	sync.one_shot_event_wait(&glow_init)

	sync.lock(&glow_mutex)
	load_program(&glow, shader)
	sync.unlock(&glow_mutex)
}

app_iter :: proc "c" (appstate: rawptr) -> sdl3.AppResult {
	context = app_context
	if !should_present {
		return .CONTINUE
	}
	push: PushConstants
	push.time = f32(time.duration_seconds(time.stopwatch_duration(timer)))
	push.aspect_ratio = f32(window_width) / f32(window_height)
	render_info := RenderInfo {
		width     = u32(min(TARGET_WIDTH, window_width)),
		height    = u32(min(TARGET_HEIGHT, window_height)),
		constants = push,
	}

	sync.lock(&glow_mutex)
	if glow.program_loaded {
		render(&renderer, &glow, &render_info)
		if !got_first_frame {
			got_first_frame = true
			elapsed := time.duration_milliseconds(time.diff(launch_time, time.now()))
			log.infof("First frame presented in %.2f ms", elapsed)
		}
	}
	sync.unlock(&glow_mutex)
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

	vk.DeviceWaitIdle(vk_context.device)
	destroy_glow_context(&glow)
	destroy_renderer(&renderer)
	destroy_vulkan_context(&vk_context)
	vk.DestroyInstance(vk_context.instance, nil)

	sdl3.DestroyWindow(window)
	sdl3.Quit()
	log.info("Goodbye")
}

main :: proc() {
	context.logger = log.create_console_logger()
	app_context = context

	argv := cstring("")
	sdl3.EnterAppMainCallbacks(0, &argv, app_init, app_iter, app_event, app_quit)
}
