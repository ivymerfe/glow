package glow

import "core:os"
import "core:sys/windows"

GlowCommandType :: enum u8 {
	WINDOW_CREATE,
	WINDOW_DESTROY,
	WINDOW_VISIBLE,
	WINDOW_FULLSCREEN,
	WINDOW_SUSPEND,
	WINDOW_PROGRAM,
}

// Decoded commands (safe to work with in-memory).
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

// Wire format for PROGRAM payload:
// u32 window_id
// u32 path_len
// u32 source_len
// [path_len]u8 path_bytes
// [source_len]u8 source_bytes
//
// Note: slices below point into the internal input buffer; if you need
// them after the callback returns, copy them.
CmdWindowProgram :: struct {
	window_id: u32,
	path:      []u8,
	source:    []u8,
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

stdin_has_data :: proc() -> bool {
	when ODIN_OS == .Windows {
		res := windows.WaitForSingleObject(windows.GetStdHandle(windows.STD_INPUT_HANDLE), 0)
		return res == windows.WAIT_OBJECT_0
	}
	return true
}

read_more_into_buffer :: proc() -> bool {
	if !stdin_has_data() {
		return false
	}
	need_len := g_in_used + READ_CHUNK
	if len(g_in) < need_len {
		resize(&g_in, need_len)
	}

	n, err := os.read(os.stdin, g_in[g_in_used:g_in_used + READ_CHUNK])
	if err == os.EAGAIN {
		return false
	}
	ensure(err == nil, "Failed to read from stdin")

	if n <= 0 {
		return false
	}
	g_in_used += n
	return true
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
		full_u8 := read_u8(payload, &c)
		ensure(c == len(payload), "Extra bytes in WINDOW_FULLSCREEN payload")
		return CmdWindowFullscreen{window_id = window_id, fullscreen = full_u8 != 0}

	case .WINDOW_SUSPEND:
		window_id := read_u32_le_cursor(payload, &c)
		suspend_u8 := read_u8(payload, &c)
		ensure(c == len(payload), "Extra bytes in WINDOW_SUSPEND payload")
		return CmdWindowSuspend{window_id = window_id, suspend = suspend_u8 != 0}

	case .WINDOW_PROGRAM:
		window_id := read_u32_le_cursor(payload, &c)
		path_len := int(read_u32_le_cursor(payload, &c))
		src_len := int(read_u32_le_cursor(payload, &c))

		path_bytes := read_bytes(payload, &c, path_len)
		src_bytes := read_bytes(payload, &c, src_len)

		ensure(c == len(payload), "Extra bytes in WINDOW_PROGRAM payload")
		return CmdWindowProgram{window_id = window_id, path = path_bytes, source = src_bytes}
	}

	// Unknown type: treat as protocol error for now.
	ensure(false, "Unknown command type")
	return CmdWindowDestroy{} // unreachable
}

process_buffer :: proc(cb: Command_Callback) {
	consume := 0

	for {
		available := g_in_used - consume
		if available < HEADER_SIZE {
			break
		}

		typ := GlowCommandType(g_in[consume])
		payload_size := int(parse_u32_le(g_in[consume + 1:consume + 5]))
		ensure(payload_size >= 0 && payload_size <= MAX_FRAME_SIZE, "Invalid payload size")

		total := HEADER_SIZE + payload_size
		if available < total {
			break
		}

		payload := g_in[consume + HEADER_SIZE:consume + total]
		cmd := decode_command(typ, payload)
		cb(cmd)

		consume += total
	}

	if consume > 0 {
		remaining := g_in_used - consume
		if remaining > 0 {
			copy(g_in[0:remaining], g_in[consume:g_in_used])
		}
		g_in_used = remaining
	}
}

poll_commands :: proc(cb: Command_Callback) {
	for read_more_into_buffer() {}

	process_buffer(cb)
}
