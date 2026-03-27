package glow

import "core:log"
import "core:sync"
import "core:thread"
import "core:time"
import "glowr"
import "gwin"
import vk "vendor:vulkan"

GlowRenderer :: struct {
	instance:         vk.Instance,
	vkc:              glowr.VulkanContext,
	res:              glowr.ResourceManager,
	resource_indexes: IndexAllocator,
	windows:          map[u32]^GlowWindow,
	timer:            time.Stopwatch,
	render_thread:    ^thread.Thread,
	mtx:              sync.RW_Mutex,
	render_signal:    sync.Auto_Reset_Event,
	compiler_thread:  ^thread.Thread,
	compiler_signal:  sync.Auto_Reset_Event,
	running:          bool,
}

create_glow :: proc(r: ^GlowRenderer) {
	r.instance = glowr.create_vk_instance()
	r.resource_indexes.max = glowr.MAX_IMAGES / IMAGES_PER_WINDOW

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
		glowr.destroy_resource_manager(&r.res)
		glowr.destroy_vulkan_context(&r.vkc)
	}
	if r.instance != {} {
		vk.DestroyInstance(r.instance, nil)
	}
}

glow_ensure_context :: proc(r: ^GlowRenderer, surface: vk.SurfaceKHR) {
	if r.vkc == {} {
		r.vkc = glowr.create_vulkan_context(r.instance, surface)
		glowr.create_resource_manager(&r.res, r.vkc, TARGET_WIDTH, TARGET_HEIGHT)
	}
}

renderer_wakeup :: proc(r: ^GlowRenderer) {
	sync.auto_reset_event_signal(&r.render_signal)
}

compiler_wakeup :: proc(r: ^GlowRenderer) {
	sync.auto_reset_event_signal(&r.compiler_signal)
}

glow_new_window :: proc(r: ^GlowRenderer, window_id: u32) {
	_, ok := r.windows[window_id]
	if ok {
		return
	}
	win := new(GlowWindow)
	create_window(r, window_id, win)

	sync.lock(&r.mtx)
	r.windows[window_id] = win
	sync.unlock(&r.mtx)
}

glow_destroy_window :: proc(r: ^GlowRenderer, window_id: u32) {
	win := r.windows[window_id]
	if win == nil {
		return
	}
	sync.lock(&r.mtx)
	destroy_window(win)
	delete_key(&r.windows, window_id)
	sync.unlock(&r.mtx)
	free(win)
}

glow_get_window :: proc(r: ^GlowRenderer, window_id: u32) -> ^GlowWindow {
	return r.windows[window_id]
}

render_window :: proc(r: ^GlowRenderer, win: ^GlowWindow) -> bool {
	pbuf_render_done(&win.pbuf)
	prog := &win.pbuf.prog
	if !prog.allocated {
		log.panic("Attempted to render with unallocated program")
	}
	current_time := f32(time.duration_seconds(time.stopwatch_duration(r.timer)))
	tick_window_input(win, current_time)
	constants := get_window_constants(win, current_time)
	width := f32(win.native.width) * win.native.scale
	height := f32(win.native.height) * win.native.scale
	render_info := glowr.RenderInfo {
		width      = u32(TARGET_WIDTH),
		height     = u32(TARGET_HEIGHT),
		dst_width  = u32(width),
		dst_height = u32(height),
		constants  = constants,
	}
	if glowr.render(&win.ren, &render_info, prog) {
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

	push: glowr.PushConstants
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
			glowr.vk_try(
				vk.WaitForFences(
					r.vkc.device,
					u32(len(fences)),
					raw_data(fences),
					false,
					max(u64),
				),
			)
			sync.shared_lock(&r.mtx)
			glowr.prepare_resources(&r.res)
			for _, win in r.windows {
				if should_render(win) && glowr.is_renderer_ready(&win.ren) {
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
				prog: glowr.Program
				success := glowr.compile_program(
					&prog,
					&r.res,
					g_slang,
					path,
					source,
					win.resource_index * IMAGES_PER_WINDOW,
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
