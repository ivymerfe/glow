package glow

import "core:log"
import "core:sys/linux"

EPOLL_MAX_EVENTS :: 64

EPollHandler :: proc(fd: linux.Fd, events: linux.EPoll_Event_Set, user_data: rawptr)

EPollEntry :: struct {
	handler:   EPollHandler,
	user_data: rawptr,
}

EPollController :: struct {
	epfd:    linux.Fd,
	entries: map[linux.Fd]EPollEntry,
}

epoll_init :: proc(ec: ^EPollController) {
	epfd, err := linux.epoll_create1({})
	ensure(err == .NONE, "epoll_create1 failed")
	ec.epfd = epfd
	ec.entries = make(map[linux.Fd]EPollEntry)
}

epoll_destroy :: proc(ec: ^EPollController) {
	linux.close(ec.epfd)
	delete(ec.entries)
}

epoll_add :: proc(
	ec: ^EPollController,
	fd: linux.Fd,
	events: linux.EPoll_Event_Set,
	handler: EPollHandler,
	user_data: rawptr = nil,
) {
	ev := linux.EPoll_Event {
		events = events,
		data = {fd = fd},
	}
	err := linux.epoll_ctl(ec.epfd, .ADD, fd, &ev)
	ensure(err == .NONE, "epoll_ctl ADD failed")
	ec.entries[fd] = EPollEntry {
		handler   = handler,
		user_data = user_data,
	}
}

epoll_remove :: proc(ec: ^EPollController, fd: linux.Fd) {
	linux.epoll_ctl(ec.epfd, .DEL, fd, nil)
	delete_key(&ec.entries, fd)
}

epoll_modify :: proc(ec: ^EPollController, fd: linux.Fd, events: linux.EPoll_Event_Set) {
	ev := linux.EPoll_Event {
		events = events,
		data = {fd = fd},
	}
	err := linux.epoll_ctl(ec.epfd, .MOD, fd, &ev)
	ensure(err == .NONE, "epoll_ctl MOD failed")
}

epoll_poll :: proc(ec: ^EPollController, timeout_ms: i32 = -1) -> bool {
	events: [EPOLL_MAX_EVENTS]linux.EPoll_Event
	n, err := linux.epoll_wait(ec.epfd, &events[0], len(events), timeout_ms)
	if err == .EINTR {
		return true
	}
	if err != .NONE {
		log.errorf("epoll_wait error: %v", err)
		return false
	}
	for i in 0 ..< n {
		fd := events[i].data.fd
		if entry, ok := ec.entries[fd]; ok {
			entry.handler(fd, events[i].events, entry.user_data)
		}
	}
	return true
}

