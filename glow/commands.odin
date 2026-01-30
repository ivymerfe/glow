package glow

import "core:os"
import "core:sys/windows"

g_input_buffer: [2048]u8

CmdWindowCreate :: struct {}

CmdWindowDestroy :: struct {
	window_id: u64,
}

CmdWindowVisible :: struct {
	window_id: u64,
	visible:   bool,
}

CmdWindowFullscreen :: struct {
	window_id:  u64,
	fullscreen: bool,
}

CmdWindowSuspend :: struct {
	window_id: u64,
	suspend:   bool,
}

CmdWindowProgram :: struct {
	window_id:   u64,
	module_path: cstring,
	source:      cstring,
}

GlowCommandType :: enum {
	WINDOW_CREATE,
	WINDOW_DESTROY,
	WINDOW_VISIBLE,
	WINDOW_FULLSCREEN,
	WINDOW_SUSPEND,
	WINDOW_PROGRAM,
}

GlowCommand :: union {
	CmdWindowCreate,
	CmdWindowDestroy,
	CmdWindowVisible,
	CmdWindowFullscreen,
	CmdWindowSuspend,
	CmdWindowProgram,
}

init_input :: proc() {
	when ODIN_OS == .Linux {
		flags, err := os.fcntl(0, os.F_GETFL, 0)
		ensure(err == nil, "Failed to get stdin flags")
		os.fcntl(0, os.F_SETFL, flags | os.O_NONBLOCK)
	}
}

read_command :: proc() -> (cmd: GlowCommand, success: bool) {
	when ODIN_OS == .Windows {
		res := windows.WaitForSingleObject(windows.GetStdHandle(windows.STD_INPUT_HANDLE), 0)
		if res != windows.WAIT_OBJECT_0 {
			return
		}
	}
	n, err := os.read(os.stdin, g_input_buffer[:])
	if err == os.EAGAIN {
		return
	}
	ensure(err == nil, "Failed to read from stdin")

	success = true
	return
}
