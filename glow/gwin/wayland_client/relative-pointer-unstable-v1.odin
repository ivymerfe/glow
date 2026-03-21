#+build linux
package wayland

@(private)
relative_pointer_types := []^interface {
	nil,
	&relative_pointer_v1_interface,
	&pointer_interface,
}

relative_pointer_manager_v1 :: struct {}

relative_pointer_manager_v1_set_user_data :: proc "contextless" (
	relative_pointer_manager_v1_: ^relative_pointer_manager_v1,
	user_data: rawptr,
) {
	proxy_set_user_data(cast(^proxy)relative_pointer_manager_v1_, user_data)
}

relative_pointer_manager_v1_get_user_data :: proc "contextless" (
	relative_pointer_manager_v1_: ^relative_pointer_manager_v1,
) -> rawptr {
	return proxy_get_user_data(cast(^proxy)relative_pointer_manager_v1_)
}

RELATIVE_POINTER_MANAGER_V1_DESTROY :: 0
relative_pointer_manager_v1_destroy :: proc "contextless" (
	relative_pointer_manager_v1_: ^relative_pointer_manager_v1,
) {
	proxy_marshal_flags(cast(^proxy)relative_pointer_manager_v1_, RELATIVE_POINTER_MANAGER_V1_DESTROY, nil, proxy_get_version(cast(^proxy)relative_pointer_manager_v1_), 1)
}

RELATIVE_POINTER_MANAGER_V1_GET_RELATIVE_POINTER :: 1
relative_pointer_manager_v1_get_relative_pointer :: proc "contextless" (
	relative_pointer_manager_v1_: ^relative_pointer_manager_v1,
	pointer_: ^pointer,
) -> ^relative_pointer_v1 {
	ret := proxy_marshal_flags(cast(^proxy)relative_pointer_manager_v1_, RELATIVE_POINTER_MANAGER_V1_GET_RELATIVE_POINTER, &relative_pointer_v1_interface, proxy_get_version(cast(^proxy)relative_pointer_manager_v1_), 0, nil, pointer_)
	return cast(^relative_pointer_v1)ret
}

@(private)
relative_pointer_manager_v1_requests := []message {
	{"destroy", "", raw_data(relative_pointer_types)[0:]},
	{"get_relative_pointer", "no", raw_data(relative_pointer_types)[1:]},
}

relative_pointer_manager_v1_interface : interface

relative_pointer_v1 :: struct {}

relative_pointer_v1_set_user_data :: proc "contextless" (
	relative_pointer_v1_: ^relative_pointer_v1,
	user_data: rawptr,
) {
	proxy_set_user_data(cast(^proxy)relative_pointer_v1_, user_data)
}

relative_pointer_v1_get_user_data :: proc "contextless" (
	relative_pointer_v1_: ^relative_pointer_v1,
) -> rawptr {
	return proxy_get_user_data(cast(^proxy)relative_pointer_v1_)
}

RELATIVE_POINTER_V1_DESTROY :: 0
relative_pointer_v1_destroy :: proc "contextless" (
	relative_pointer_v1_: ^relative_pointer_v1,
) {
	proxy_marshal_flags(cast(^proxy)relative_pointer_v1_, RELATIVE_POINTER_V1_DESTROY, nil, proxy_get_version(cast(^proxy)relative_pointer_v1_), 1)
}

relative_pointer_v1_listener :: struct {
	relative_motion: proc "c" (
		data: rawptr,
		relative_pointer_v1: ^relative_pointer_v1,
		utime_hi: uint,
		utime_lo: uint,
		dx: fixed_t,
		dy: fixed_t,
		dx_unaccel: fixed_t,
		dy_unaccel: fixed_t,
	),
}

relative_pointer_v1_add_listener :: proc "contextless" (
	relative_pointer_v1_: ^relative_pointer_v1,
	listener: ^relative_pointer_v1_listener,
	data: rawptr,
) {
	proxy_add_listener(cast(^proxy)relative_pointer_v1_, cast(^generic_c_call)listener, data)
}

@(private)
relative_pointer_v1_requests := []message {
	{"destroy", "", raw_data(relative_pointer_types)[0:]},
}

@(private)
relative_pointer_v1_events := []message {
	{"relative_motion", "uuffff", raw_data(relative_pointer_types)[0:]},
}

relative_pointer_v1_interface : interface

@(private)
@(init)
init_interfaces_relative_pointer_v1 :: proc "contextless" () {
	relative_pointer_manager_v1_interface.name = "zwp_relative_pointer_manager_v1"
	relative_pointer_manager_v1_interface.version = 1
	relative_pointer_manager_v1_interface.method_count = 2
	relative_pointer_manager_v1_interface.event_count = 0
	relative_pointer_manager_v1_interface.methods = raw_data(relative_pointer_manager_v1_requests)

	relative_pointer_v1_interface.name = "zwp_relative_pointer_v1"
	relative_pointer_v1_interface.version = 1
	relative_pointer_v1_interface.method_count = 1
	relative_pointer_v1_interface.event_count = 1
	relative_pointer_v1_interface.methods = raw_data(relative_pointer_v1_requests)
	relative_pointer_v1_interface.events = raw_data(relative_pointer_v1_events)
}
