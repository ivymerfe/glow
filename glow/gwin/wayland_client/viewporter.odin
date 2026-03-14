#+build linux
package wayland

@(private)
viewporter_types := []^interface {
	nil,
	&viewport_interface,
	&surface_interface,
}

/* The global interface exposing surface cropping and scaling controls.

   A wp_viewporter object can create wp_viewport objects that affect how a
   wl_surface consumes attached buffers by selecting a source rectangle and
   destination size. */
viewporter :: struct {}

viewporter_set_user_data :: proc "contextless" (viewporter_: ^viewporter, user_data: rawptr) {
	proxy_set_user_data(cast(^proxy)viewporter_, user_data)
}

viewporter_get_user_data :: proc "contextless" (viewporter_: ^viewporter) -> rawptr {
	return proxy_get_user_data(cast(^proxy)viewporter_)
}

/* Destroy the viewporter global object.

   This does not destroy viewport objects created from it. */
VIEWPORTER_DESTROY :: 0
viewporter_destroy :: proc "contextless" (viewporter_: ^viewporter) {
	proxy_marshal_flags(cast(^proxy)viewporter_, VIEWPORTER_DESTROY, nil, proxy_get_version(cast(^proxy)viewporter_), 1)
}

/* Create a viewport object for a wl_surface.

   The same wl_surface must not have more than one wp_viewport at a time. */
VIEWPORTER_GET_VIEWPORT :: 1
viewporter_get_viewport :: proc "contextless" (viewporter_: ^viewporter, surface_: ^surface) -> ^viewport {
	ret := proxy_marshal_flags(cast(^proxy)viewporter_, VIEWPORTER_GET_VIEWPORT, &viewport_interface, proxy_get_version(cast(^proxy)viewporter_), 0, nil, surface_)
	return cast(^viewport)ret
}

/*  */
viewporter_error :: enum {
	bad_value = 0,
	bad_surface = 1,
}

@(private)
viewporter_requests := []message {
	{"destroy", "", raw_data(viewporter_types)[0:]},
	{"get_viewport", "no", raw_data(viewporter_types)[1:]},
}

viewporter_interface : interface

/* A per-surface object that configures source and destination rectangles for
   content sampling and scaling. */
viewport :: struct {}

viewport_set_user_data :: proc "contextless" (viewport_: ^viewport, user_data: rawptr) {
	proxy_set_user_data(cast(^proxy)viewport_, user_data)
}

viewport_get_user_data :: proc "contextless" (viewport_: ^viewport) -> rawptr {
	return proxy_get_user_data(cast(^proxy)viewport_)
}

/* Remove this wp_viewport from its wl_surface. */
VIEWPORT_DESTROY :: 0
viewport_destroy :: proc "contextless" (viewport_: ^viewport) {
	proxy_marshal_flags(cast(^proxy)viewport_, VIEWPORT_DESTROY, nil, proxy_get_version(cast(^proxy)viewport_), 1)
}

/* Set the crop rectangle in surface-local coordinates using fixed-point values.

   Setting width and height to -1 unsets the source rectangle. */
VIEWPORT_SET_SOURCE :: 1
viewport_set_source :: proc "contextless" (
	viewport_: ^viewport,
	x_: fixed_t,
	y_: fixed_t,
	width_: fixed_t,
	height_: fixed_t,
) {
	proxy_marshal_flags(cast(^proxy)viewport_, VIEWPORT_SET_SOURCE, nil, proxy_get_version(cast(^proxy)viewport_), 0, x_, y_, width_, height_)
}

/* Set the destination size in surface-local coordinates.

   Setting width and height to -1 unsets the destination size. */
VIEWPORT_SET_DESTINATION :: 2
viewport_set_destination :: proc "contextless" (viewport_: ^viewport, width_: int, height_: int) {
	proxy_marshal_flags(cast(^proxy)viewport_, VIEWPORT_SET_DESTINATION, nil, proxy_get_version(cast(^proxy)viewport_), 0, width_, height_)
}

/*  */
viewport_error :: enum {
	bad_value = 0,
	bad_size = 1,
	out_of_buffer = 2,
	no_surface = 3,
}

@(private)
viewport_requests := []message {
	{"destroy", "", raw_data(viewporter_types)[0:]},
	{"set_source", "ffff", raw_data(viewporter_types)[0:]},
	{"set_destination", "ii", raw_data(viewporter_types)[0:]},
}

viewport_interface : interface

@(private)
@(init)
init_interfaces_viewporter :: proc "contextless" () {
	viewporter_interface.name = "wp_viewporter"
	viewporter_interface.version = 1
	viewporter_interface.method_count = 2
	viewporter_interface.event_count = 0
	viewporter_interface.methods = raw_data(viewporter_requests)

	viewport_interface.name = "wp_viewport"
	viewport_interface.version = 1
	viewport_interface.method_count = 3
	viewport_interface.event_count = 0
	viewport_interface.methods = raw_data(viewport_requests)
}
