#+build linux
package wayland

@(private)
cursor_shape_v1_types := []^interface {
	nil,
	&cursor_shape_device_v1_interface,
	&pointer_interface,
	&cursor_shape_device_v1_interface,
	nil,
}

cursor_shape_manager_v1 :: struct {}

cursor_shape_manager_v1_set_user_data :: proc "contextless" (manager: ^cursor_shape_manager_v1, user_data: rawptr) {
	proxy_set_user_data(cast(^proxy)manager, user_data)
}

cursor_shape_manager_v1_get_user_data :: proc "contextless" (manager: ^cursor_shape_manager_v1) -> rawptr {
	return proxy_get_user_data(cast(^proxy)manager)
}

CURSOR_SHAPE_MANAGER_V1_DESTROY :: 0
cursor_shape_manager_v1_destroy :: proc "contextless" (manager: ^cursor_shape_manager_v1) {
	proxy_marshal_flags(cast(^proxy)manager, CURSOR_SHAPE_MANAGER_V1_DESTROY, nil, proxy_get_version(cast(^proxy)manager), 1)
}

CURSOR_SHAPE_MANAGER_V1_GET_POINTER :: 1
cursor_shape_manager_v1_get_pointer :: proc "contextless" (manager: ^cursor_shape_manager_v1, pointer_: ^pointer) -> ^cursor_shape_device_v1 {
	ret := proxy_marshal_flags(cast(^proxy)manager, CURSOR_SHAPE_MANAGER_V1_GET_POINTER, &cursor_shape_device_v1_interface, proxy_get_version(cast(^proxy)manager), 0, nil, pointer_)
	return cast(^cursor_shape_device_v1)ret
}

@(private)
cursor_shape_manager_v1_requests := []message {
	{"destroy", "", raw_data(cursor_shape_v1_types)[0:]},
	{"get_pointer", "no", raw_data(cursor_shape_v1_types)[1:]},
	{"get_tablet_tool_v2", "no", raw_data(cursor_shape_v1_types)[3:]},
}

cursor_shape_manager_v1_interface : interface

cursor_shape_device_v1 :: struct {}

cursor_shape_device_v1_set_user_data :: proc "contextless" (device: ^cursor_shape_device_v1, user_data: rawptr) {
	proxy_set_user_data(cast(^proxy)device, user_data)
}

cursor_shape_device_v1_get_user_data :: proc "contextless" (device: ^cursor_shape_device_v1) -> rawptr {
	return proxy_get_user_data(cast(^proxy)device)
}

CURSOR_SHAPE_DEVICE_V1_DESTROY :: 0
cursor_shape_device_v1_destroy :: proc "contextless" (device: ^cursor_shape_device_v1) {
	proxy_marshal_flags(cast(^proxy)device, CURSOR_SHAPE_DEVICE_V1_DESTROY, nil, proxy_get_version(cast(^proxy)device), 1)
}

CURSOR_SHAPE_DEVICE_V1_SET_SHAPE :: 1
cursor_shape_device_v1_set_shape :: proc "contextless" (device: ^cursor_shape_device_v1, serial: uint, shape: u32) {
	proxy_marshal_flags(cast(^proxy)device, CURSOR_SHAPE_DEVICE_V1_SET_SHAPE, nil, proxy_get_version(cast(^proxy)device), 0, serial, shape)
}

cursor_shape_v1_shape :: enum u32 {
	default = 1,
	context_menu = 2,
	help = 3,
	pointer = 4,
	progress = 5,
	wait = 6,
	cell = 7,
	crosshair = 8,
	text = 9,
	vertical_text = 10,
	alias = 11,
	copy = 12,
	move = 13,
	no_drop = 14,
	not_allowed = 15,
	grab = 16,
	grabbing = 17,
	e_resize = 18,
	n_resize = 19,
	ne_resize = 20,
	nw_resize = 21,
	s_resize = 22,
	se_resize = 23,
	sw_resize = 24,
	w_resize = 25,
	ew_resize = 26,
	ns_resize = 27,
	nesw_resize = 28,
	nwse_resize = 29,
	col_resize = 30,
	row_resize = 31,
	all_scroll = 32,
	zoom_in = 33,
	zoom_out = 34,
}

@(private)
cursor_shape_device_v1_requests := []message {
	{"destroy", "", raw_data(cursor_shape_v1_types)[0:]},
	{"set_shape", "uu", raw_data(cursor_shape_v1_types)[0:]},
}

cursor_shape_device_v1_interface : interface

@(private)
@(init)
init_interfaces_cursor_shape_v1 :: proc "contextless" () {
	cursor_shape_manager_v1_interface.name = "wp_cursor_shape_manager_v1"
	cursor_shape_manager_v1_interface.version = 1
	cursor_shape_manager_v1_interface.method_count = 3
	cursor_shape_manager_v1_interface.methods = raw_data(cursor_shape_manager_v1_requests)

	cursor_shape_device_v1_interface.name = "wp_cursor_shape_device_v1"
	cursor_shape_device_v1_interface.version = 1
	cursor_shape_device_v1_interface.method_count = 2
	cursor_shape_device_v1_interface.methods = raw_data(cursor_shape_device_v1_requests)
}