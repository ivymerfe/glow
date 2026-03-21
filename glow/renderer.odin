package glow

import "core:log"
import "core:sync"
import "core:thread"
import "core:time"
import "glowr"
import "gwin"
import vk "vendor:vulkan"

GlowRenderer :: struct {
	windows:         map[u32]^GlowWindow,
	timer:           time.Stopwatch,
	render_thread:   ^thread.Thread,
	mtx:             sync.RW_Mutex,
	render_signal:   sync.Auto_Reset_Event,
	compiler_thread: ^thread.Thread,
	compiler_signal: sync.Auto_Reset_Event,
	stop:            bool,
}

renderer_start :: proc(r: ^GlowRenderer) {
	r.stop = false
	r.render_thread = thread.create_and_start_with_data(r, render_proc, context)
	r.compiler_thread = thread.create_and_start_with_data(r, compiler_proc, context)
	time.stopwatch_start(&r.timer)
}

renderer_stop :: proc(r: ^GlowRenderer) {
	sync.atomic_store(&r.stop, true)
	renderer_wakeup(r)
	compiler_wakeup(r)
	thread.destroy(r.render_thread)
	thread.destroy(r.compiler_thread)
}

renderer_wakeup :: proc(r: ^GlowRenderer) {
	sync.auto_reset_event_signal(&r.render_signal)
}

compiler_wakeup :: proc(r: ^GlowRenderer) {
	sync.auto_reset_event_signal(&r.compiler_signal)
}

renderer_new_window :: proc(r: ^GlowRenderer, window_id: u32) {
	_, ok := r.windows[window_id]
	if ok {
		return
	}
	win := new(GlowWindow)
	create_window(&g_ctx.wayland, window_id, win)

	sync.lock(&r.mtx)
	r.windows[window_id] = win
	sync.unlock(&r.mtx)
}

renderer_destroy_window :: proc(r: ^GlowRenderer, window_id: u32) {
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

renderer_get_window :: proc(r: ^GlowRenderer, window_id: u32) -> ^GlowWindow {
	return r.windows[window_id]
}

renderer_destroy_all_windows :: proc(r: ^GlowRenderer) {
	sync.lock(&r.mtx)
	for _, win in r.windows {
		destroy_window(win)
	}
	clear(&r.windows)
	sync.unlock(&r.mtx)
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
	for !sync.atomic_load(&r.stop) {
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
					g_ctx.vkc.device,
					u32(len(fences)),
					raw_data(fences),
					false,
					max(u64),
				),
			)
			sync.shared_lock(&r.mtx)
			glowr.prepare_resources(&g_ctx.res)
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

compiler_proc :: proc(raw: rawptr) {
	r := cast(^GlowRenderer)raw

	for {
		sync.auto_reset_event_wait(&r.compiler_signal)
		if sync.atomic_load(&r.stop) {
			break
		}
		sync.shared_lock(&r.mtx)
		for _, win in r.windows {
			if pbuf_should_recompile(&win.pbuf) {
				path, source, version := pbuf_get_source(&win.pbuf)
				prog: glowr.Program
				success := glowr.compile_program(
					&prog,
					&g_ctx.res,
					g_ctx.slang,
					path,
					source,
					win.res_index * IMAGES_PER_WINDOW,
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
