package glow

MessageType :: enum u8 {
	WINDOW_CLOSED  = 0,
	WINDOW_VISIBLE = 1,
}

MSG_MAX :: 512

Message :: struct {
	buf: [MSG_MAX]u8,
	len: int,
}

msg_window_destroyed :: proc(msg: ^Message, window_id: u32) {
	msg_write_u8(msg, u8(MessageType.WINDOW_CLOSED))
	msg_write_u32(msg, window_id)
	msg_finish(msg)
}

msg_window_visible :: proc(msg: ^Message, window_id: u32, visible: bool) {
	msg_write_u8(msg, u8(MessageType.WINDOW_VISIBLE))
	msg_write_u32(msg, window_id)
	msg_write_u8(msg, u8(visible))
	msg_finish(msg)
}

@(private)
msg_write_u8 :: proc(b: ^Message, v: u8) {
	ensure(b.len + 1 + 4 <= MSG_MAX, "MsgBuilder overflow")
	b.buf[4 + b.len] = v
	b.len += 1
}

@(private)
msg_write_u32 :: proc(msg: ^Message, v: u32) {
	ensure(msg.len + 4 + 4 <= MSG_MAX, "MsgBuilder overflow")
	off := 4 + msg.len
	msg.buf[off + 0] = u8(v & 0xff)
	msg.buf[off + 1] = u8((v >> 8) & 0xff)
	msg.buf[off + 2] = u8((v >> 16) & 0xff)
	msg.buf[off + 3] = u8((v >> 24) & 0xff)
	msg.len += 4
}

@(private)
msg_finish :: proc(msg: ^Message) {
	sz := u32(msg.len)
	msg.buf[0] = u8(sz & 0xff)
	msg.buf[1] = u8((sz >> 8) & 0xff)
	msg.buf[2] = u8((sz >> 16) & 0xff)
	msg.buf[3] = u8((sz >> 24) & 0xff)
}

