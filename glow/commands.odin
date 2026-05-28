package glow

import "core:log"
import "core:os"

GlowCommandType :: enum u8 {
	WINDOW_CREATE,
	WINDOW_DESTROY,
	WINDOW_VISIBLE,
	WINDOW_FULLSCREEN,
	WINDOW_PROGRAM,
	COMPILE_PROGRAM,
}

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
CmdWindowToggleFullscreen :: struct {
	window_id: u32,
}
CmdWindowProgram :: struct {
	window_id: u32,
	path:      string,
	source:    string,
}
CmdCompileProgram :: struct {
	target:   CompilationTarget,
	path:     string,
	source:   string,
	dst_path: string,
}

GlowCommand :: union {
	CmdWindowCreate,
	CmdWindowDestroy,
	CmdWindowVisible,
	CmdWindowToggleFullscreen,
	CmdWindowProgram,
	CmdCompileProgram,
}

Command_Callback :: proc(cmd: GlowCommand)

init_input :: proc() {
	when ODIN_OS == .Linux {
		flags, err := os.fcntl(0, os.F_GETFL, 0)
		ensure(err == nil, "Failed to get stdin flags")
		_, err2 := os.fcntl(0, os.F_SETFL, flags | os.O_NONBLOCK)
		ensure(err2 == nil, "Failed to set stdin nonblocking")
	}
}

HEADER_SIZE :: 5 // u8 type + u32 payload_size_le
READ_CHUNK :: 8192
MAX_FRAME_SIZE :: 64 * 1024 * 1024

g_in: [dynamic]u8
g_in_used: int

parse_u32_le :: proc(data: []u8) -> u32 {
	ensure(len(data) >= 4, "Data too small to parse u32")
	return u32(data[0]) | (u32(data[1]) << 8) | (u32(data[2]) << 16) | (u32(data[3]) << 24)
}

read_u8 :: proc(data: []u8, cursor: ^int) -> u8 {
	ensure(cursor^ + 1 <= len(data), "Payload underrun (u8)")
	v := data[cursor^]
	cursor^ += 1
	return v
}

read_u32_le_cursor :: proc(data: []u8, cursor: ^int) -> u32 {
	ensure(cursor^ + 4 <= len(data), "Payload underrun (u32)")
	v := parse_u32_le(data[cursor^:cursor^ + 4])
	cursor^ += 4
	return v
}

read_bytes :: proc(data: []u8, cursor: ^int, n: int) -> []u8 {
	ensure(n >= 0, "Negative length")
	ensure(cursor^ + n <= len(data), "Payload underrun (bytes)")
	out := data[cursor^:cursor^ + n]
	cursor^ += n
	return out
}

read_string :: proc(data: []u8, cursor: ^int) -> string {
	length := int(read_u32_le_cursor(data, cursor))
	str := transmute(string)read_bytes(data, cursor, length)
	return str
}

decode_command :: proc(typ: GlowCommandType, payload: []u8) -> GlowCommand {
	c := 0

	switch typ {
	case .WINDOW_CREATE:
		window_id := read_u32_le_cursor(payload, &c)
		ensure(c == len(payload), "Extra bytes in WINDOW_CREATE payload")
		return CmdWindowCreate{window_id = window_id}

	case .WINDOW_DESTROY:
		window_id := read_u32_le_cursor(payload, &c)
		ensure(c == len(payload), "Extra bytes in WINDOW_DESTROY payload")
		return CmdWindowDestroy{window_id = window_id}

	case .WINDOW_VISIBLE:
		window_id := read_u32_le_cursor(payload, &c)
		visible_u8 := read_u8(payload, &c)
		ensure(c == len(payload), "Extra bytes in WINDOW_VISIBLE payload")
		return CmdWindowVisible{window_id = window_id, visible = visible_u8 != 0}

	case .WINDOW_FULLSCREEN:
		window_id := read_u32_le_cursor(payload, &c)
		ensure(c == len(payload), "Extra bytes in WINDOW_FULLSCREEN payload")
		return CmdWindowToggleFullscreen{window_id = window_id}

	case .WINDOW_PROGRAM:
		window_id := read_u32_le_cursor(payload, &c)
		path := read_string(payload, &c)
		source := read_string(payload, &c)

		ensure(c == len(payload), "Extra bytes in WINDOW_PROGRAM payload")
		return CmdWindowProgram{window_id = window_id, path = path, source = source}

	case .COMPILE_PROGRAM:
		target := cast(CompilationTarget)read_u32_le_cursor(payload, &c)
		path := read_string(payload, &c)
		source := read_string(payload, &c)
		dst_path := read_string(payload, &c)
		ensure(c == len(payload), "Extra bytes in COMPILE_MODULE payload")
		return CmdCompileProgram {
			target = target,
			path = path,
			source = source,
			dst_path = dst_path,
		}
	}
	log.panic("Unknown command type")
}

