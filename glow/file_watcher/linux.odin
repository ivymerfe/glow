package file_watcher

import "core:sys/linux"

WatchDescriptor :: linux.Wd
Err :: linux.Errno
WatchEvent :: linux.Inotify_Event

File_Change_Callback :: proc(event: ^WatchEvent)

LinuxFileWatcher :: struct {
	cb:          File_Change_Callback,
	inotify_fd:  linux.Fd,
	epoll_fd:    linux.Fd,
	shutdown_fd: linux.Fd,
}

create_watcher :: proc(cb: File_Change_Callback) -> (LinuxFileWatcher, Err) {
	fw: LinuxFileWatcher
	fw.cb = cb

	inotify_fd: linux.Fd
	err: Err
	inotify_fd, err = linux.inotify_init1({.NONBLOCK})
	if err != .NONE {
		return fw, err
	}
	epoll_fd: linux.Fd
	epoll_fd, err = linux.epoll_create1({})
	if err != .NONE {
		linux.close(inotify_fd)
		return fw, err
	}
	shutdown_n := linux.syscall(linux.SYS_eventfd, 0, 11) // EFD_NONBLOCK = 11
	if shutdown_n < 0 {
		linux.close(inotify_fd)
		linux.close(epoll_fd)
		return fw, Err(-shutdown_n)
	}
	shutdown_fd: linux.Fd = cast(linux.Fd)shutdown_n

	ev := linux.EPoll_Event {
		events = {.IN},
		data = linux.EPoll_Data{fd = inotify_fd},
	}
	if err = linux.epoll_ctl(epoll_fd, .ADD, inotify_fd, &ev); err != .NONE {
		linux.close(inotify_fd)
		linux.close(epoll_fd)
		linux.close(shutdown_fd)
		return fw, err
	}
	ev = linux.EPoll_Event {
		events = {.IN},
		data = linux.EPoll_Data{fd = shutdown_fd},
	}
	if err = linux.epoll_ctl(epoll_fd, .ADD, shutdown_fd, &ev); err != .NONE {
		linux.close(inotify_fd)
		linux.close(epoll_fd)
		linux.close(shutdown_fd)
		return fw, err
	}
	fw.inotify_fd = inotify_fd
	fw.epoll_fd = epoll_fd
	fw.shutdown_fd = shutdown_fd
	return fw, .NONE
}

destroy_watcher :: proc(fw: ^LinuxFileWatcher) {
	linux.write(fw.shutdown_fd, {0, 0, 0, 0, 0, 0, 0, 1})
	linux.close(fw.epoll_fd)
	linux.close(fw.inotify_fd)
	linux.close(fw.shutdown_fd)
}

add_file_watch :: proc(fw: ^LinuxFileWatcher, filepath: cstring) -> (WatchDescriptor, Err) {
	return linux.inotify_add_watch(
		fw.inotify_fd,
		filepath,
		{.MODIFY, .CLOSE_WRITE, .ATTRIB, .DELETE_SELF, .MOVE_SELF},
	)
}

remove_file_watch :: proc(fw: ^LinuxFileWatcher, wd: WatchDescriptor) -> Err {
	return linux.inotify_rm_watch(fw.inotify_fd, wd)
}

wait_for_events :: proc(fw: ^LinuxFileWatcher) -> (bool, Err) {
	event: linux.EPoll_Event
	_, err := linux.epoll_wait(fw.epoll_fd, &event, 1, -1)
	if err != .NONE {
		return true, err
	}
	if event.data.fd == fw.shutdown_fd {
		return true, .NONE
	}
	return false, .NONE
}

dispatch_events :: proc(fw: ^LinuxFileWatcher) {
	buffer := make([]u8, 4096)
	bytes_read, err := linux.read(fw.inotify_fd, buffer)
	if err != .NONE || bytes_read < 0 {
		return
	}
	i := 0
	for i < bytes_read {
		event := cast(^WatchEvent)(rawptr(&buffer[i]))
		fw.cb(event)
		i += size_of(WatchEvent) + int(event.len)
	}
	delete(buffer)
}
