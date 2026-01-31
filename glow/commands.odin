package glow

import "core:os"
import "core:sys/windows"

CmdWindowCreate :: struct {
	window_id: u32,
}

CmdWindowDestroy :: struct {
	window_id: u32,
}

CmdWindowVisible :: struct {
	window_id: u32,
	visible:   bool,
}

CmdWindowFullscreen :: struct {
	window_id:  u32,
	fullscreen: bool,
}

CmdWindowSuspend :: struct {
	window_id: u32,
	suspend:   bool,
}

CmdWindowProgram :: struct {
	window_id:     u32,
	path_length:   u32,
	source_length: u32,
	data:          []u8,
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

Command_Callback :: proc(cmd: GlowCommand)

init_input :: proc() {
	when ODIN_OS == .Linux {
		flags, err := os.fcntl(0, os.F_GETFL, 0)
		ensure(err == nil, "Failed to get stdin flags")
		os.fcntl(0, os.F_SETFL, flags | os.O_NONBLOCK)
	}
}

g_frame: [dynamic]u8
g_frame_size: int
g_frame_offset: int
g_cmd_type: GlowCommandType

read_input_buffer :: proc() -> bool {
	when ODIN_OS == .Windows {
		res := windows.WaitForSingleObject(windows.GetStdHandle(windows.STD_INPUT_HANDLE), 0)
		if res != windows.WAIT_OBJECT_0 {
			return false
		}
	}
	n, err := os.read(os.stdin, g_frame[g_frame_offset:])
	if err == os.EAGAIN {
		return false
	}
	ensure(err == nil, "Failed to read from stdin")
	g_frame_offset += n
	return true
}

parse_u32_le :: proc(data: []u8) -> u32 {
	ensure(len(data) >= 4, "Data too small to parse u32")
	return u32(data[0]) | (u32(data[1]) << 8) | (u32(data[2]) << 16) | (u32(data[3]) << 24)
}

read_command :: proc(cb: Command_Callback) {
	if g_frame_offset < g_frame_size {
		read_input_buffer()
		if g_frame_offset < g_frame_size {
			return
		}
		switch g_cmd_type {
		case .WINDOW_CREATE:
			cmd := cast(^CmdWindowCreate)(&g_frame[0])
			cb(cmd^)
		case .WINDOW_DESTROY:
			cmd := cast(^CmdWindowDestroy)(&g_frame[0])
			cb(cmd^)
		case .WINDOW_VISIBLE:
			cmd := cast(^CmdWindowVisible)(&g_frame[0])
			cb(cmd^)
		case .WINDOW_FULLSCREEN:
			cmd := cast(^CmdWindowFullscreen)(&g_frame[0])
			cb(cmd^)
		case .WINDOW_SUSPEND:
			cmd := cast(^CmdWindowSuspend)(&g_frame[0])
			cb(cmd^)
		case .WINDOW_PROGRAM:
			cmd := cast(^CmdWindowProgram)(&g_frame[0])
			cb(cmd^)
		}
		return
	}
	header: [5]u8
	n, err := os.read(os.stdin, header[:])
	if err == os.EAGAIN {
		return
	}
	ensure(err == nil, "Failed to read from stdin")
	ensure(n == 5, "Failed to read full command header")
	g_cmd_type = GlowCommandType(header[0])
}
