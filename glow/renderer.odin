package glow

import "core:sync"
import "core:thread"
import "core:time"
import "glowr"
import vk "vendor:vulkan"

RenderThread :: struct {
	thread:  ^thread.Thread,
	mtx:     sync.Mutex,
	evt:     sync.Auto_Reset_Event,
	windows: map[u32]^GlowWindow,
	stop:    bool,
}

renderer_start :: proc(r: ^RenderThread) {
	r.stop = false
	r.thread = thread.create_and_start_with_data(r, render_proc, context)
}

renderer_stop :: proc(r: ^RenderThread) {
	if r.thread == nil {
		return
	}
	sync.atomic_store(&r.stop, true)
	renderer_wakeup(r)
	thread.join(r.thread)
	thread.destroy(r.thread)
	r.thread = nil
}

renderer_wakeup :: proc(r: ^RenderThread) {
	sync.auto_reset_event_signal(&r.evt)
}

renderer_lock :: proc(r: ^RenderThread) {
	sync.lock(&r.mtx)
}

renderer_unlock :: proc(r: ^RenderThread) {
	sync.unlock(&r.mtx)
}

renderer_new_window :: proc(r: ^RenderThread, window_id: u32) {
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

renderer_destroy_window :: proc(r: ^RenderThread, window_id: u32) {
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

renderer_get_window :: proc(r: ^RenderThread, window_id: u32) -> ^GlowWindow {
	return r.windows[window_id]
}

renderer_destroy_all_windows :: proc(r: ^RenderThread) {
	renderer_lock(r)
	for _, win in r.windows {
		destroy_window(win)
	}
	clear(&r.windows)
	renderer_unlock(r)
}

render_proc :: proc(raw: rawptr) {
	r := cast(^RenderThread)raw

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
			for _, win in r.windows {
				if should_render(win) {
					width := f32(win.native.width) * win.native.scale
					height := f32(win.native.height) * win.native.scale
					push.time = f32(time.duration_seconds(time.stopwatch_duration(win.timer)))
					push.aspect_ratio = f32(width) / f32(height)
					push.frame_idx = win.frame_idx
					win.frame_idx += 1

					render_info := glowr.RenderInfo {
						width      = u32(TARGET_WIDTH),
						height     = u32(TARGET_HEIGHT),
						dst_width  = u32(width),
						dst_height = u32(height),
						constants  = push,
					}
					rendered |= glowr.render(&win.ren, &render_info)
				}
			}
			renderer_unlock(r)
		}
		if !rendered {
			sync.auto_reset_event_wait(&r.evt)
		}
	}
}
