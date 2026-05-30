package glow

import "core:log"

CmdShaderSource :: struct {
	path:   string,
	source: string,
}

CmdToggleFullscreen :: struct {
	path: string,
}

CmdRemoveShader :: struct {
	path: string,
}

CmdCompileShader :: struct {
	target:   CompilationTarget,
	path:     string,
	source:   string,
	dst_path: string,
}

GlowCommandType :: enum u8 {
	SHADER_SOURCE,
	TOGGLE_FULLSCREEN,
	REMOVE_SHADER,
	COMPILE_SHADER,
}

GlowCommand :: union {
	CmdShaderSource,
	CmdToggleFullscreen,
	CmdRemoveShader,
	CmdCompileShader,
}

Command_Callback :: proc(cmd: GlowCommand)

Message :: struct {
	buf: [MESSAGE_MAX_SIZE]u8,
	len: int,
}

MessageType :: enum u8 {
	SHADER_REMOVED = 0,
}

COMMAND_MAX_SIZE :: 10 * 1024 * 1024
MESSAGE_MAX_SIZE :: 512

decode_command :: proc(payload: []u8) -> (cmd: GlowCommand, success: bool) {
	if len(payload) == 0 {
		return GlowCommand{}, false
	}
	typ := GlowCommandType(payload[0])
	offset := 1
	switch typ {
	case .SHADER_SOURCE:
		path := read_string(payload, &offset)
		source := read_string(payload, &offset)
		return CmdShaderSource{path = path, source = source}, true

	case .TOGGLE_FULLSCREEN:
		path := read_string(payload, &offset)
		return CmdToggleFullscreen{path = path}, true

	case .REMOVE_SHADER:
		path := read_string(payload, &offset)
		return CmdRemoveShader{path = path}, true

	case .COMPILE_SHADER:
		target := CompilationTarget(payload[0])
		offset += 1
		path := read_string(payload, &offset)
		source := read_string(payload, &offset)
		dst_path := read_string(payload, &offset)
		return CmdCompileShader {
				target = target,
				path = path,
				source = source,
				dst_path = dst_path,
			},
			true

	case:
		return GlowCommand{}, false
	}
}

msg_shader_removed :: proc(msg: ^Message, shader: string) {
	msg_u8(msg, u8(MessageType.SHADER_REMOVED))
	msg_string(msg, shader)
	msg_finish(msg)
}

read_u32 :: proc(data: []u8) -> u32 {
	ensure(len(data) >= 4, "Data too small to parse u32")
	num := u32(data[0]) | (u32(data[1]) << 8) | (u32(data[2]) << 16) | (u32(data[3]) << 24)
	return num
}

read_u32_cursor :: proc(data: []u8, cursor: ^int) -> u32 {
	num := read_u32(data[cursor^:])
	cursor^ += 4
	return num
}

read_string :: proc(data: []u8, cursor: ^int) -> string {
	length := int(read_u32_cursor(data, cursor))
	s := transmute(string)data[cursor^:cursor^ + length]
	cursor^ += length
	return s
}

@(private)
msg_u8 :: proc(b: ^Message, v: u8) {
	ensure(b.len + 1 + 4 <= MESSAGE_MAX_SIZE, "Message overflow")
	b.buf[b.len + 4] = v
	b.len += 1
}

@(private)
msg_u32 :: proc(msg: ^Message, v: u32) {
	ensure(msg.len + 4 + 4 <= MESSAGE_MAX_SIZE, "Message overflow")
	off := msg.len + 4
	msg.buf[off + 0] = u8(v & 0xff)
	msg.buf[off + 1] = u8((v >> 8) & 0xff)
	msg.buf[off + 2] = u8((v >> 16) & 0xff)
	msg.buf[off + 3] = u8((v >> 24) & 0xff)
	msg.len += 4
}

@(private)
msg_string :: proc(msg: ^Message, s: string) {
	bytes := transmute([]u8)s
	ensure(msg.len + 4 + len(bytes) + 4 <= MESSAGE_MAX_SIZE, "Message overflow")
	msg_u32(msg, u32(len(bytes)))
	copy(msg.buf[msg.len + 4:], bytes)
	msg.len += len(bytes)
}

@(private)
msg_finish :: proc(msg: ^Message) {
	msg_len := u32(msg.len)
	msg.buf[0] = u8(msg_len & 0xff)
	msg.buf[1] = u8((msg_len >> 8) & 0xff)
	msg.buf[2] = u8((msg_len >> 16) & 0xff)
	msg.buf[3] = u8((msg_len >> 24) & 0xff)
}

