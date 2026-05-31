package glow

import "core:log"
import "core:math"
import "core:sync"
import "core:thread"
import "core:time"

import "../gwin"
import "../gwin/wl"
import "../rend"
import vk "vendor:vulkan"

CAMERA_SPEED_MIN :: f32(0.25)
CAMERA_SPEED_MAX :: f32(64.0)

GlowWindow :: struct {
	glow:             ^Glow,
	path:             string,
	native:           ^gwin.WaylandWindow,
	ren:              rend.Renderer,
	pbuf:             ProgramBuffer,
	index:            uint,
	render_thread:    ^thread.Thread,
	render_signal:    sync.Auto_Reset_Event,
	running:          bool,
	visible:          bool,
	active:           bool,
	frame_index:      int,
	timer:            time.Stopwatch,
	mouse_x:          f32,
	mouse_y:          f32,
	input:            [4]u32,
	is_camera_active: bool,
	camera_pos:       [3]f32,
	yaw:              f32,
	pitch:            f32,
	camera_speed:     f32,
	camera_movement:  [3]f32,
	last_update_time: f32,
}

create_window :: proc(glow: ^Glow, path: string, win: ^GlowWindow) {
	win.glow = glow
	win.path = path
	index, index_success := alloc_index(&glow.window_indexes)
	if !index_success {
		log.panicf("Failed to allocate window index for %u", path)
	}
	win.index = index

	native, wl_success := gwin.create_window(
		&g_wayland,
		"glow",
		"glow",
		640,
		360,
		f32(g_options.width),
		f32(g_options.height),
		win,
	)
	if !wl_success {
		log.panic("Failed to create Wayland window")
	}
	win.native = native

	surface, ok := create_vulkan_surface(native, glow.instance)
	if !ok {
		log.panic("Failed to create Vulkan surface")
	}
	glow_ensure_context(glow, surface)
	win.ren = rend.create_renderer(
		&glow.vkc,
		&glow.res,
		surface,
		g_options.width,
		g_options.height,
	)
	win.visible = true
	win.active = true
	win.camera_speed = 4.0
	win.running = true
	time.stopwatch_start(&win.timer)
	win.render_thread = thread.create_and_start_with_data(win, window_renderer, context)
}

destroy_window :: proc(win: ^GlowWindow) {
	sync.atomic_store(&win.running, false)
	sync.auto_reset_event_signal(&win.render_signal)
	thread.destroy(win.render_thread)

	rend.wait_renderer(&win.ren)
	rend.destroy_renderer(&win.ren)
	free_index(&win.glow.window_indexes, win.index)
	gwin.destroy_window(win.native)
}

create_vulkan_surface :: proc(
	win: ^gwin.WaylandWindow,
	instance: vk.Instance,
) -> (
	vk.SurfaceKHR,
	bool,
) {
	wl_surface_info := vk.WaylandSurfaceCreateInfoKHR {
		sType   = .WAYLAND_SURFACE_CREATE_INFO_KHR,
		display = auto_cast win.ctx.display,
		surface = auto_cast win.surface,
	}
	vk_surface: vk.SurfaceKHR
	result := vk.CreateWaylandSurfaceKHR(instance, &wl_surface_info, nil, &vk_surface)
	if result != .SUCCESS {
		log.errorf("Failed to create Vulkan surface: %v", result)
		return {}, false
	}
	return vk_surface, true
}

request_next_frame :: proc "c" (win: ^GlowWindow) {
	callback := wl.surface_frame(win.native.surface)
	wl.callback_add_listener(callback, &frame_listener, win)
	wl.surface_commit(win.native.surface)
}

on_frame_done :: proc "c" (data: rawptr, callback: ^wl.callback, time: uint) {
	wl.callback_destroy(callback)
	win := cast(^GlowWindow)data
	sync.auto_reset_event_signal(&win.render_signal)
}

frame_listener := wl.callback_listener {
	done = on_frame_done,
}

wakeup_window :: proc(win: ^GlowWindow) {
	sync.auto_reset_event_signal(&win.render_signal)
}

render_window :: proc(win: ^GlowWindow) {
	pbuf_render_done(&win.pbuf)
	prog := &win.pbuf.prog
	if !prog.allocated {
		log.panic("Attempted to render with unallocated program")
	}
	width := f32(win.native.width) * win.native.scale
	height := f32(win.native.height) * win.native.scale
	current_time := f32(time.duration_seconds(time.stopwatch_duration(win.timer)))
	tick_window_input(win, current_time)

	constants := get_window_constants(win, current_time)
	render_info := rend.RenderInfo {
		dst_width  = u32(width),
		dst_height = u32(height),
		constants  = constants,
	}
	if rend.render(&win.ren, &render_info, prog) {
		win.frame_index += 1
	}
}

should_render :: proc(win: ^GlowWindow) -> bool {
	return(
		sync.atomic_load(&win.visible) &&
		sync.atomic_load(&win.active) &&
		sync.atomic_load(&win.pbuf.ready) \
	)
}

window_renderer :: proc(raw: rawptr) {
	win := cast(^GlowWindow)raw
	request_next_frame(win)

	for sync.atomic_load(&win.running) {
		sync.auto_reset_event_wait(&win.render_signal)

		if should_render(win) {
			render_window(win)
			request_next_frame(win)
		}
	}
}

set_window_visible :: proc(win: ^GlowWindow, visible: bool) {
	gwin.set_window_visible(win.native, visible)
	sync.atomic_store(&win.visible, visible)
	if visible {
		wakeup_window(win)
	}
}

set_window_active :: proc(win: ^GlowWindow, active: bool) {
	sync.atomic_store(&win.active, active)
	if active {
		wakeup_window(win)
	}
}

set_window_fullscreen :: proc(win: ^GlowWindow, fullscreen: bool) {
	gwin.set_window_fullscreen(win.native, fullscreen)
}

update_key_state :: proc(win: ^GlowWindow, key: u32, pressed: bool) {
	idx := key >> 5
	mask := u32(1) << (key & 31)
	if pressed {
		win.input[idx] |= mask
	} else {
		win.input[idx] &= ~mask
	}
}

on_window_input :: proc(win: ^GlowWindow, key: u32, pressed: bool) {
	update_key_state(win, key, pressed)
	dir: f32 = pressed ? 1 : -1
	switch key {
	case KEY_W:
		win.camera_movement[0] += dir
	case KEY_S:
		win.camera_movement[0] -= dir
	case KEY_SPACE:
		win.camera_movement[1] += dir
	case KEY_LEFT_SHIFT:
		win.camera_movement[1] -= dir
	case KEY_D:
		win.camera_movement[2] += dir
	case KEY_A:
		win.camera_movement[2] -= dir
	}
}

on_window_pointer_button :: proc(
	win: ^GlowWindow,
	pointer: ^gwin.WaylandPointer,
	key: u32,
	pressed: bool,
) {
	update_key_state(win, key, pressed)
	if key == KEY_MOUSE_RIGHT && pressed {
		if win.pbuf.prog.camera.required {
			win.is_camera_active = !win.is_camera_active
			gwin.lock_pointer(pointer, win.is_camera_active, win.native)
			return
		}
	}
}

on_window_keyboard_leave :: proc(win: ^GlowWindow) {
	win.input = [4]u32{}
	win.camera_movement = [3]f32{}
}

on_window_pointer_enter :: proc(win: ^GlowWindow, pointer: ^gwin.WaylandPointer, x: f32, y: f32) {
	win.mouse_x = x / f32(win.native.width)
	win.mouse_y = y / f32(win.native.height)
}

on_window_pointer_motion :: proc(win: ^GlowWindow, x: f32, y: f32) {
	win.mouse_x = x / f32(win.native.width)
	win.mouse_y = y / f32(win.native.height)
}

on_window_pointer_relative :: proc(win: ^GlowWindow, dx: f32, dy: f32) {
	if !win.is_camera_active {
		return
	}
	sensitivity := f32(0.003)
	win.yaw += dx * sensitivity
	win.pitch -= dy * sensitivity
	if win.pitch > 1.55 {
		win.pitch = 1.55
	}
	if win.pitch < -1.55 {
		win.pitch = -1.55
	}
}

on_window_pointer_scroll :: proc(win: ^GlowWindow, dx: f32, dy: f32) {
	_ = dx
	if !win.is_camera_active || dy == 0 {
		return
	}
	scale := f32(1.0) - dy * 0.1
	if scale < 0.1 {
		scale = 0.1
	}
	win.camera_speed *= scale
	if win.camera_speed < CAMERA_SPEED_MIN {
		win.camera_speed = CAMERA_SPEED_MIN
	}
	if win.camera_speed > CAMERA_SPEED_MAX {
		win.camera_speed = CAMERA_SPEED_MAX
	}
}

get_window_constants :: proc(win: ^GlowWindow, time: f32) -> rend.PushConstants {
	ys := math.sin(win.yaw)
	yc := math.cos(win.yaw)
	ps := math.sin(win.pitch)
	pc := math.cos(win.pitch)

	forward := [3]f32{ys * pc, ps, yc * pc}
	right := [3]f32{yc, 0, -ys}
	up := [3]f32{-ys * ps, pc, -yc * ps}

	return rend.PushConstants {
		position = win.camera_pos,
		forward = forward,
		right = right,
		up = up,
		input = win.input,
		mouse_x = win.mouse_x,
		mouse_y = win.mouse_y,
		time = time,
		frame_index = u32(win.frame_index),
	}
}

tick_window_input :: proc(win: ^GlowWindow, time: f32) {
	if !win.is_camera_active {
		return
	}
	x_forward := math.sin(win.yaw)
	z_forward := math.cos(win.yaw)

	time_delta := time - win.last_update_time
	win.last_update_time = time
	delta := win.camera_speed * time_delta
	x_delta := (x_forward * win.camera_movement[0] + z_forward * win.camera_movement[2]) * delta
	y_delta := win.camera_movement[1] * delta
	z_delta := (z_forward * win.camera_movement[0] - x_forward * win.camera_movement[2]) * delta
	win.camera_pos[0] += x_delta
	win.camera_pos[1] += y_delta
	win.camera_pos[2] += z_delta
}

