package glow

import "../rend"
import "core:log"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import vk "vendor:vulkan"

Glow :: struct {
	instance:        vk.Instance,
	vkc:             rend.VulkanContext,
	res:             rend.ResourceManager,
	window_indexes:  IndexAllocator,
	windows:         map[string]^GlowWindow,
	mtx:             sync.RW_Mutex,
	compiler_thread: ^thread.Thread,
	compiler_signal: sync.Auto_Reset_Event,
	running:         bool,
}

create_glow :: proc(r: ^Glow) {
	r.instance = rend.create_vk_instance(g_options.debug)
	r.window_indexes.max = g_options.max_windows

	r.running = true
	r.compiler_thread = thread.create_and_start_with_data(r, glow_compiler_proc, context)
}

destroy_glow :: proc(r: ^Glow) {
	sync.atomic_store(&r.running, false)
	compiler_wakeup(r)
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

glow_ensure_context :: proc(r: ^Glow, surface: vk.SurfaceKHR) {
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

compiler_wakeup :: proc(r: ^Glow) {
	sync.auto_reset_event_signal(&r.compiler_signal)
}

glow_new_window :: proc(r: ^Glow, path: string) -> ^GlowWindow {
	win, ok := r.windows[path]
	if ok {
		return win
	}
	win = new(GlowWindow)
	saved_path := strings.clone(path)
	create_window(r, saved_path, win)

	sync.lock(&r.mtx)
	r.windows[saved_path] = win
	sync.unlock(&r.mtx)
	return win
}

glow_destroy_window :: proc(r: ^Glow, win: ^GlowWindow) {
	sync.lock(&r.mtx)
	destroy_window(win)
	delete_key(&r.windows, win.path)
	sync.unlock(&r.mtx)
	delete(win.path)
	free(win)
}

glow_compiler_proc :: proc(raw: rawptr) {
	r := cast(^Glow)raw

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
					wakeup_window(win)
				}
			}
		}
		sync.shared_unlock(&r.mtx)
	}
}

