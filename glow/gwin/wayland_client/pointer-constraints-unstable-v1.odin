#+build linux
package wayland

@(private)
pointer_constraints_types := []^interface {
	nil,
	&locked_pointer_v1_interface,
	&confined_pointer_v1_interface,
	&surface_interface,
	&pointer_interface,
	&region_interface,
	&locked_pointer_v1_interface,
	&surface_interface,
	&pointer_interface,
	&region_interface,
	nil,
	&confined_pointer_v1_interface,
	&surface_interface,
	&pointer_interface,
	&region_interface,
	nil,
}

pointer_constraints_v1 :: struct {}

pointer_constraints_v1_set_user_data :: proc "contextless" (
	pointer_constraints_v1_: ^pointer_constraints_v1,
	user_data: rawptr,
) {
	proxy_set_user_data(cast(^proxy)pointer_constraints_v1_, user_data)
}

pointer_constraints_v1_get_user_data :: proc "contextless" (
	pointer_constraints_v1_: ^pointer_constraints_v1,
) -> rawptr {
	return proxy_get_user_data(cast(^proxy)pointer_constraints_v1_)
}

POINTER_CONSTRAINTS_V1_DESTROY :: 0
pointer_constraints_v1_destroy :: proc "contextless" (
	pointer_constraints_v1_: ^pointer_constraints_v1,
) {
	proxy_marshal_flags(cast(^proxy)pointer_constraints_v1_, POINTER_CONSTRAINTS_V1_DESTROY, nil, proxy_get_version(cast(^proxy)pointer_constraints_v1_), 1)
}

POINTER_CONSTRAINTS_V1_LOCK_POINTER :: 1
pointer_constraints_v1_lock_pointer :: proc "contextless" (
	pointer_constraints_v1_: ^pointer_constraints_v1,
	surface_: ^surface,
	pointer_: ^pointer,
	region_: ^region,
	lifetime: pointer_constraints_v1_lifetime,
) -> ^locked_pointer_v1 {
	ret := proxy_marshal_flags(cast(^proxy)pointer_constraints_v1_, POINTER_CONSTRAINTS_V1_LOCK_POINTER, &locked_pointer_v1_interface, proxy_get_version(cast(^proxy)pointer_constraints_v1_), 0, nil, surface_, pointer_, region_, lifetime)
	return cast(^locked_pointer_v1)ret
}

POINTER_CONSTRAINTS_V1_CONFINE_POINTER :: 2
pointer_constraints_v1_confine_pointer :: proc "contextless" (
	pointer_constraints_v1_: ^pointer_constraints_v1,
	surface_: ^surface,
	pointer_: ^pointer,
	region_: ^region,
	lifetime: pointer_constraints_v1_lifetime,
) -> ^confined_pointer_v1 {
	ret := proxy_marshal_flags(cast(^proxy)pointer_constraints_v1_, POINTER_CONSTRAINTS_V1_CONFINE_POINTER, &confined_pointer_v1_interface, proxy_get_version(cast(^proxy)pointer_constraints_v1_), 0, nil, surface_, pointer_, region_, lifetime)
	return cast(^confined_pointer_v1)ret
}

pointer_constraints_v1_error :: enum {
	already_constrained = 1,
}

pointer_constraints_v1_lifetime :: enum {
	oneshot = 1,
	persistent = 2,
}

@(private)
pointer_constraints_v1_requests := []message {
	{"destroy", "", raw_data(pointer_constraints_types)[0:]},
	{"lock_pointer", "noo?ou", raw_data(pointer_constraints_types)[6:]},
	{"confine_pointer", "noo?ou", raw_data(pointer_constraints_types)[11:]},
}

pointer_constraints_v1_interface : interface

locked_pointer_v1 :: struct {}

locked_pointer_v1_set_user_data :: proc "contextless" (
	locked_pointer_v1_: ^locked_pointer_v1,
	user_data: rawptr,
) {
	proxy_set_user_data(cast(^proxy)locked_pointer_v1_, user_data)
}

locked_pointer_v1_get_user_data :: proc "contextless" (
	locked_pointer_v1_: ^locked_pointer_v1,
) -> rawptr {
	return proxy_get_user_data(cast(^proxy)locked_pointer_v1_)
}

LOCKED_POINTER_V1_DESTROY :: 0
locked_pointer_v1_destroy :: proc "contextless" (locked_pointer_v1_: ^locked_pointer_v1) {
	proxy_marshal_flags(cast(^proxy)locked_pointer_v1_, LOCKED_POINTER_V1_DESTROY, nil, proxy_get_version(cast(^proxy)locked_pointer_v1_), 1)
}

LOCKED_POINTER_V1_SET_CURSOR_POSITION_HINT :: 1
locked_pointer_v1_set_cursor_position_hint :: proc "contextless" (
	locked_pointer_v1_: ^locked_pointer_v1,
	surface_x: fixed_t,
	surface_y: fixed_t,
) {
	proxy_marshal_flags(cast(^proxy)locked_pointer_v1_, LOCKED_POINTER_V1_SET_CURSOR_POSITION_HINT, nil, proxy_get_version(cast(^proxy)locked_pointer_v1_), 0, surface_x, surface_y)
}

LOCKED_POINTER_V1_SET_REGION :: 2
locked_pointer_v1_set_region :: proc "contextless" (
	locked_pointer_v1_: ^locked_pointer_v1,
	region: ^region,
) {
	proxy_marshal_flags(cast(^proxy)locked_pointer_v1_, LOCKED_POINTER_V1_SET_REGION, nil, proxy_get_version(cast(^proxy)locked_pointer_v1_), 0, region)
}

locked_pointer_v1_listener :: struct {
	locked: proc "c" (data: rawptr, locked_pointer_v1: ^locked_pointer_v1),
	unlocked: proc "c" (data: rawptr, locked_pointer_v1: ^locked_pointer_v1),
}

locked_pointer_v1_add_listener :: proc "contextless" (
	locked_pointer_v1_: ^locked_pointer_v1,
	listener: ^locked_pointer_v1_listener,
	data: rawptr,
) {
	proxy_add_listener(cast(^proxy)locked_pointer_v1_, cast(^generic_c_call)listener, data)
}

@(private)
locked_pointer_v1_requests := []message {
	{"destroy", "", raw_data(pointer_constraints_types)[0:]},
	{"set_cursor_position_hint", "ff", raw_data(pointer_constraints_types)[0:]},
	{"set_region", "?o", raw_data(pointer_constraints_types)[5:]},
}

@(private)
locked_pointer_v1_events := []message {
	{"locked", "", raw_data(pointer_constraints_types)[0:]},
	{"unlocked", "", raw_data(pointer_constraints_types)[0:]},
}

locked_pointer_v1_interface : interface

confined_pointer_v1 :: struct {}

confined_pointer_v1_set_user_data :: proc "contextless" (
	confined_pointer_v1_: ^confined_pointer_v1,
	user_data: rawptr,
) {
	proxy_set_user_data(cast(^proxy)confined_pointer_v1_, user_data)
}

confined_pointer_v1_get_user_data :: proc "contextless" (
	confined_pointer_v1_: ^confined_pointer_v1,
) -> rawptr {
	return proxy_get_user_data(cast(^proxy)confined_pointer_v1_)
}

CONFINED_POINTER_V1_DESTROY :: 0
confined_pointer_v1_destroy :: proc "contextless" (confined_pointer_v1_: ^confined_pointer_v1) {
	proxy_marshal_flags(cast(^proxy)confined_pointer_v1_, CONFINED_POINTER_V1_DESTROY, nil, proxy_get_version(cast(^proxy)confined_pointer_v1_), 1)
}

CONFINED_POINTER_V1_SET_REGION :: 1
confined_pointer_v1_set_region :: proc "contextless" (
	confined_pointer_v1_: ^confined_pointer_v1,
	region: ^region,
) {
	proxy_marshal_flags(cast(^proxy)confined_pointer_v1_, CONFINED_POINTER_V1_SET_REGION, nil, proxy_get_version(cast(^proxy)confined_pointer_v1_), 0, region)
}

confined_pointer_v1_listener :: struct {
	confined: proc "c" (data: rawptr, confined_pointer_v1: ^confined_pointer_v1),
	unconfined: proc "c" (data: rawptr, confined_pointer_v1: ^confined_pointer_v1),
}

confined_pointer_v1_add_listener :: proc "contextless" (
	confined_pointer_v1_: ^confined_pointer_v1,
	listener: ^confined_pointer_v1_listener,
	data: rawptr,
) {
	proxy_add_listener(cast(^proxy)confined_pointer_v1_, cast(^generic_c_call)listener, data)
}

@(private)
confined_pointer_v1_requests := []message {
	{"destroy", "", raw_data(pointer_constraints_types)[0:]},
	{"set_region", "?o", raw_data(pointer_constraints_types)[5:]},
}

@(private)
confined_pointer_v1_events := []message {
	{"confined", "", raw_data(pointer_constraints_types)[0:]},
	{"unconfined", "", raw_data(pointer_constraints_types)[0:]},
}

confined_pointer_v1_interface : interface

@(private)
@(init)
init_interfaces_pointer_constraints_v1 :: proc "contextless" () {
	pointer_constraints_v1_interface.name = "zwp_pointer_constraints_v1"
	pointer_constraints_v1_interface.version = 1
	pointer_constraints_v1_interface.method_count = 3
	pointer_constraints_v1_interface.event_count = 0
	pointer_constraints_v1_interface.methods = raw_data(pointer_constraints_v1_requests)

	locked_pointer_v1_interface.name = "zwp_locked_pointer_v1"
	locked_pointer_v1_interface.version = 1
	locked_pointer_v1_interface.method_count = 3
	locked_pointer_v1_interface.event_count = 2
	locked_pointer_v1_interface.methods = raw_data(locked_pointer_v1_requests)
	locked_pointer_v1_interface.events = raw_data(locked_pointer_v1_events)

	confined_pointer_v1_interface.name = "zwp_confined_pointer_v1"
	confined_pointer_v1_interface.version = 1
	confined_pointer_v1_interface.method_count = 2
	confined_pointer_v1_interface.event_count = 2
	confined_pointer_v1_interface.methods = raw_data(confined_pointer_v1_requests)
	confined_pointer_v1_interface.events = raw_data(confined_pointer_v1_events)
}
