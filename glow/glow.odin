package glow

import "../gwin"
import "../rend"
import "core:log"
import "core:sync"
import "core:thread"
import "core:time"
import vk "vendor:vulkan"

GlowRenderer :: struct {
	instance:        vk.Instance,
	vkc:             rend.VulkanContext,
	res:             rend.ResourceManager,
	window_indexes:  IndexAllocator,
	windows:         map[string]^GlowWindow,
	timer:           time.Stopwatch,
	render_thread:   ^thread.Thread,
	mtx:             sync.RW_Mutex,
	render_signal:   sync.Auto_Reset_Event,
	compiler_thread: ^thread.Thread,
	compiler_signal: sync.Auto_Reset_Event,
	running:         bool,
}

create_glow :: proc(r: ^GlowRenderer) {
	r.instance = rend.create_vk_instance(g_options.debug)
	r.window_indexes.max = g_options.max_windows

	r.running = true
	r.render_thread = thread.create_and_start_with_data(r, render_proc, context)
	r.compiler_thread = thread.create_and_start_with_data(r, window_program_compiler_proc, context)
	time.stopwatch_start(&r.timer)
}

destroy_glow :: proc(r: ^GlowRenderer) {
	sync.atomic_store(&r.running, false)
	renderer_wakeup(r)
	compiler_wakeup(r)
	thread.destroy(r.render_thread)
	thread.destroy(r.compiler_thread)
	if r.vkc != {} {
		vk.DeviceWaitIdle(r.vkc.device)
		for _, win in r.windows {
			destroy_window(win)
		}
		rend.destroy_resource_manager(&r.res)
		rend.destroy_vulkan_context(&r.vkc)
	}
	if r.instance != {} {
		vk.DestroyInstance(r.instance, nil)
	}
}

glow_ensure_context :: proc(r: ^GlowRenderer, surface: vk.SurfaceKHR) {
	if r.vkc == {} {
		r.vkc = rend.create_vulkan_context(r.instance, surface)
		rend.create_resource_manager(
			&r.res,
			r.vkc,
			g_options.width,
			g_options.height,
			g_options.max_images * g_options.max_windows,
		)
	}
}

renderer_wakeup :: proc(r: ^GlowRenderer) {
	sync.auto_reset_event_signal(&r.render_signal)
}

compiler_wakeup :: proc(r: ^GlowRenderer) {
	sync.auto_reset_event_signal(&r.compiler_signal)
}

glow_new_window :: proc(r: ^GlowRenderer, path: string) -> ^GlowWindow {
	win, ok := r.windows[path]
	if ok {
		return win
	}
	win = new(GlowWindow)
	create_window(r, path, win)

	sync.lock(&r.mtx)
	r.windows[path] = win
	sync.unlock(&r.mtx)
	return win
}

glow_destroy_window :: proc(r: ^GlowRenderer, win: ^GlowWindow) {
	sync.lock(&r.mtx)
	destroy_window(win)
	delete_key(&r.windows, win.path)
	sync.unlock(&r.mtx)
	free(win)
}

render_window :: proc(r: ^GlowRenderer, win: ^GlowWindow) -> bool {
	pbuf_render_done(&win.pbuf)
	prog := &win.pbuf.prog
	if !prog.allocated {
		log.panic("Attempted to render with unallocated program")
	}
	width := f32(win.native.width) * win.native.scale
	height := f32(win.native.height) * win.native.scale
	current_time := f32(time.duration_seconds(time.stopwatch_duration(r.timer)))
	tick_window_input(win, current_time)

	constants := get_window_constants(win, current_time)
	render_info := rend.RenderInfo {
		dst_width  = u32(width),
		dst_height = u32(height),
		constants  = constants,
	}
	if rend.render(&win.ren, &render_info, prog) {
		win.frame_index += 1
		return true
	}
	return false
}

should_render :: proc(win: ^GlowWindow) -> bool {
	return(
		sync.atomic_load(&win.visible) &&
		sync.atomic_load(&win.active) &&
		sync.atomic_load(&win.pbuf.ready) \
	)
}

render_proc :: proc(raw: rawptr) {
	r := cast(^GlowRenderer)raw

	push: rend.PushConstants
	fences := make([dynamic]vk.Fence)
	for sync.atomic_load(&r.running) {
		clear(&fences)
		sync.shared_lock(&r.mtx)
		for _, win in r.windows {
			if should_render(win) {
				append(&fences, win.ren.render_fence)
			}
		}
		sync.shared_unlock(&r.mtx)

		rendered := false
		if len(fences) > 0 {
			rend.vk_try(
				vk.WaitForFences(
					r.vkc.device,
					u32(len(fences)),
					raw_data(fences),
					false,
					max(u64),
				),
			)
			sync.shared_lock(&r.mtx)
			rend.prepare_resources(&r.res)
			for _, win in r.windows {
				if should_render(win) && rend.is_renderer_ready(&win.ren) {
					rendered |= render_window(r, win)
				}
			}
			sync.shared_unlock(&r.mtx)
		}
		if !rendered {
			sync.auto_reset_event_wait(&r.render_signal)
		}
	}
}

window_program_compiler_proc :: proc(raw: rawptr) {
	r := cast(^GlowRenderer)raw

	for {
		sync.auto_reset_event_wait(&r.compiler_signal)
		if !sync.atomic_load(&r.running) {
			break
		}
		sync.shared_lock(&r.mtx)
		for _, win in r.windows {
			if pbuf_should_recompile(&win.pbuf) {
				path, source, version := pbuf_get_source(&win.pbuf)
				prog: rend.Program
				success := rend.compile_program(
					&prog,
					&r.res,
					g_slang,
					path,
					source,
					win.index * g_options.max_images,
				)
				pbuf_compile_done(&win.pbuf, success, prog, version)
				if success {
					renderer_wakeup(r)
				}
			}
		}
		sync.shared_unlock(&r.mtx)
	}
}

