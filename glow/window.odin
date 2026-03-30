package glow

import "core:log"
import "core:math"
import "core:sync"

import "glowr"
import "gwin"
import vk "vendor:vulkan"

CAMERA_SPEED_MIN :: f32(0.25)
CAMERA_SPEED_MAX :: f32(64.0)

GlowWindow :: struct {
	glow:             ^GlowRenderer,
	id:               u32,
	native:           ^gwin.WaylandWindow,
	ren:              glowr.Renderer,
	pbuf:             ProgramBuffer,
	index:            uint,
	visible:          bool,
	active:           bool,
	frame_index:      int,
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

create_window :: proc(glow: ^GlowRenderer, window_id: u32, win: ^GlowWindow) {
	win.glow = glow
	win.id = window_id
	index, index_success := alloc_index(&glow.window_indexes)
	if !index_success {
		log.panicf("Failed to allocate window index for %u", window_id)
	}
	win.index = index

	native, wl_success := gwin.create_window(
		&g_wayland,
		window_id,
		"glow",
		640,
		360,
		f32(g_options.width),
		f32(g_options.height),
	)
	if !wl_success {
		log.panic("Failed to create Wayland window")
	}
	win.native = native

	surface, ok := gwin.create_vulkan_surface(native, glow.instance)
	if !ok {
		log.panic("Failed to create Vulkan surface")
	}
	glow_ensure_context(glow, surface)
	win.ren = glowr.create_renderer(
		glow.vkc,
		&glow.res,
		surface,
		g_options.width,
		g_options.height,
	)
	win.visible = true
	win.active = true
	win.camera_speed = 4.0
}

destroy_window :: proc(win: ^GlowWindow) {
	glowr.wait_renderer(&win.ren)
	glowr.destroy_renderer(&win.ren)
	free_index(&win.glow.window_indexes, win.index)
	gwin.destroy_window(win.native)
}

set_window_visible :: proc(win: ^GlowWindow, visible: bool) {
	gwin.set_window_visible(win.native, visible)
	sync.atomic_store(&win.visible, visible)
	if visible {
		renderer_wakeup(win.glow)
	}
}

set_window_active :: proc(win: ^GlowWindow, active: bool) {
	sync.atomic_store(&win.active, active)
}

set_window_fullscreen :: proc(win: ^GlowWindow, fullscreen: bool) {
	gwin.set_window_fullscreen(win.native, fullscreen)
	if !fullscreen {
		set_camera_active(win, false)
	}
}

set_camera_active :: proc(win: ^GlowWindow, active: bool) {
	win.is_camera_active = active
	gwin.set_window_pointer_lock(win.native, win.is_camera_active)
}

on_window_input :: proc(win: ^GlowWindow, key: u32, pressed: bool) {
	if key == KEY_MOUSE_RIGHT && pressed {
		if win.pbuf.prog.camera_supported {
			set_camera_active(win, !win.is_camera_active)
			return
		}
	}
	idx := key >> 5
	mask := u32(1) << (key & 31)
	if pressed {
		win.input[idx] |= mask
	} else {
		win.input[idx] &= ~mask
	}

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

on_window_keyboard_leave :: proc(win: ^GlowWindow) {
	win.input = [4]u32{}
	win.camera_movement = [3]f32{}
}

on_window_pointer_enter :: proc(win: ^GlowWindow, x: f32, y: f32) {
	win.mouse_x = x / f32(win.native.width)
	win.mouse_y = y / f32(win.native.height)
	if win.native.fullscreen && win.pbuf.prog.camera_supported {
		set_camera_active(win, true)
	}
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

get_window_constants :: proc(win: ^GlowWindow, time: f32) -> glowr.PushConstants {
	ys := math.sin(win.yaw)
	yc := math.cos(win.yaw)
	ps := math.sin(win.pitch)
	pc := math.cos(win.pitch)

	forward := [3]f32{ys * pc, ps, yc * pc}
	right := [3]f32{yc, 0, -ys}
	up := [3]f32{-ys * ps, pc, -yc * ps}

	return glowr.PushConstants {
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
