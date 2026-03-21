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
	id:               u32,
	native:           ^gwin.WaylandWindow,
	ren:              glowr.Renderer,
	pbuf:             ProgramBuffer,
	res_index:        u32,
	visible:          bool,
	active:           bool,
	last_update_time: f32,
	is_camera_active: bool,
	camera_pos:       [4]f32,
	camera_speed:     f32,
	camera_movement:  [4]f32,
	yaw:              f32,
	pitch:            f32,
	mouse_x:          f32,
	mouse_y:          f32,
	input:            [4]u32,
	frame_index:      int,
}

create_window :: proc(ctx: ^gwin.WaylandContext, window_id: u32, win: ^GlowWindow) {
	win.id = window_id
	native, wl_success := gwin.create_window(
		ctx,
		window_id,
		"glow",
		640,
		360,
		SWAPCHAIN_WIDTH,
		SWAPCHAIN_HEIGHT,
	)
	if !wl_success {
		log.panic("Failed to create Wayland window")
	}
	win.native = native

	surface, ok := gwin.create_vulkan_surface(native, g_ctx.instance)
	if !ok {
		log.panic("Failed to create Vulkan surface")
	}
	if g_ctx.vkc == {} {
		g_ctx.vkc = glowr.create_vulkan_context(g_ctx.instance, surface)
		glowr.create_resource_manager(&g_ctx.res, g_ctx.vkc, TARGET_WIDTH, TARGET_HEIGHT)
		g_ctx.index_allocator.max = glowr.MAX_IMAGES / IMAGES_PER_WINDOW
	}
	win.ren = glowr.create_renderer(
		g_ctx.vkc,
		&g_ctx.res,
		surface,
		SWAPCHAIN_WIDTH,
		SWAPCHAIN_HEIGHT,
	)
	res_index, res_success := alloc_index(&g_ctx.index_allocator)
	if !res_success {
		log.panic("Failed to allocate resource index for window")
	}
	win.res_index = res_index
	win.visible = true
	win.active = true
	win.camera_speed = 4.0
}

destroy_window :: proc(win: ^GlowWindow) {
	glowr.wait_renderer(&win.ren)
	glowr.destroy_renderer(&win.ren)

	free_index(&g_ctx.index_allocator, win.res_index)
	gwin.destroy_window(win.native)
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

set_window_fullscreen :: proc(win: ^GlowWindow, fullscreen: bool) {
	gwin.set_window_fullscreen(win.native, fullscreen)
	prog := pbuf_get_current(&win.pbuf)
	if prog.camera_supported {
		set_camera_active(win, fullscreen)
	}
}

set_camera_active :: proc(win: ^GlowWindow, active: bool) {
	win.is_camera_active = active
	gwin.set_window_pointer_lock(win.native, win.is_camera_active)
}

on_window_input :: proc(win: ^GlowWindow, key: u32, pressed: bool) {
	if key == KEY_MOUSE_RIGHT && pressed {
		prog := pbuf_get_current(&win.pbuf)
		if prog.camera_supported {
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

	if win.is_camera_active {
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
}

on_window_leave :: proc(win: ^GlowWindow) {
	win.input = [4]u32{}
	win.camera_movement = [4]f32{}
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

	forward := [4]f32{ys * pc, ps, yc * pc, 0}
	right := [4]f32{yc, 0, -ys, 0}
	up := [4]f32{-ys * ps, pc, -yc * ps, 0}

	return glowr.PushConstants {
		camera_pos = win.camera_pos,
		camera_forward = forward,
		camera_right = right,
		camera_up = up,
		input_state = win.input,
		mouse_x = win.mouse_x,
		mouse_y = win.mouse_y,
		width = TARGET_WIDTH,
		height = TARGET_HEIGHT,
		time = time,
		frame_index = u32(win.frame_index),
	}
}

tick_window_input :: proc(win: ^GlowWindow, time: f32) {
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
