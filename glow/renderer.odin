package glow

import "core:strings"
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
	render_mtx:      sync.Mutex,
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

renderer_lock :: proc(r: ^GlowRenderer) {
	sync.lock(&r.render_mtx)
}

renderer_unlock :: proc(r: ^GlowRenderer) {
	sync.unlock(&r.render_mtx)
}

renderer_new_window :: proc(r: ^GlowRenderer, window_id: u32) {
	_, ok := r.windows[window_id]
	if ok {
		return
	}
	win := new(GlowWindow)
	create_window(&g_ctx.wayland, window_id, win)

	renderer_lock(r)
	r.windows[window_id] = win
	renderer_unlock(r)
}

renderer_destroy_window :: proc(r: ^GlowRenderer, window_id: u32) {
	win := r.windows[window_id]
	if win == nil {
		return
	}
	renderer_lock(r)
	destroy_window(win)
	delete_key(&r.windows, window_id)
	renderer_unlock(r)
	free(win)
}

renderer_get_window :: proc(r: ^GlowRenderer, window_id: u32) -> ^GlowWindow {
	return r.windows[window_id]
}

renderer_destroy_all_windows :: proc(r: ^GlowRenderer) {
	renderer_lock(r)
	for _, win in r.windows {
		destroy_window(win)
	}
	clear(&r.windows)
	renderer_unlock(r)
}

set_window_visible :: proc(win: ^GlowWindow, visible: bool) {
	gwin.set_window_visible(win.native, visible)
	sync.atomic_store(&win.visible, visible)
	if visible {
		renderer_wakeup(&g_ctx.renderer)
	}
}

set_window_active :: proc(win: ^GlowWindow, active: bool) {
	sync.atomic_store(&win.active, active)
}

should_render :: proc(win: ^GlowWindow) -> bool {
	return sync.atomic_load(&win.visible) && sync.atomic_load(&win.active)
}

render_window :: proc(r: ^GlowRenderer, win: ^GlowWindow) -> bool {
	pbuf_render_done(&win.pbuf)
	prog := pbuf_get_current(&win.pbuf)
	if should_render(win) && prog.allocated {
		width := f32(win.native.width) * win.native.scale
		height := f32(win.native.height) * win.native.scale
		render_info := glowr.RenderInfo {
			width = u32(TARGET_WIDTH),
			height = u32(TARGET_HEIGHT),
			dst_width = u32(width),
			dst_height = u32(height),
			constants = glowr.PushConstants {
				time = f32(time.duration_seconds(time.stopwatch_duration(r.timer))),
				width = width,
				height = height,
				frame_index = u32(win.frame_index),
			},
		}
		if glowr.render(&win.ren, &render_info, prog) {
			win.frame_index += 1
			return true
		}
	}
	return false
}

render_proc :: proc(raw: rawptr) {
	r := cast(^GlowRenderer)raw

	push: glowr.PushConstants
	fences := make([dynamic]vk.Fence)
	for !sync.atomic_load(&r.stop) {
		clear(&fences)
		renderer_lock(r)
		for _, win in r.windows {
			if should_render(win) {
				append(&fences, win.ren.render_fence)
			}
		}
		renderer_unlock(r)

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
			renderer_lock(r)
			glowr.prepare_resources(&g_ctx.res)
			for _, win in r.windows {
				rendered |= render_window(r, win)
			}
			renderer_unlock(r)
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
		for _, win in r.windows {
			if pbuf_should_recompile(&win.pbuf) {
				path, source := pbuf_get_source(&win.pbuf)
				path_c := strings.clone_to_cstring(path)
				source_c := strings.clone_to_cstring(source)
				defer delete_cstring(path_c)
				defer delete_cstring(source_c)

				next := pbuf_get_next(&win.pbuf)
				glowr.destroy_program(next)
				success := glowr.compile_program(
					next,
					&g_ctx.res,
					g_ctx.slang,
					path_c,
					source_c,
					win.res_index * IMAGES_PER_WINDOW,
				)
				pbuf_compile_done(&win.pbuf, success)
				if success {
					renderer_wakeup(r)
				}
			}
		}
	}
}
