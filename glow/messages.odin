package glow

import "core:os"

MessageType :: enum {
	WINDOW_CLOSED,
}

msg_window_destroyed :: proc(window_id: u32) {
	msg_data_u32(5) // 5 bytes
	msg_data_u8(u8(MessageType.WINDOW_CLOSED))
	msg_data_u32(window_id)
}

g_out: [dynamic]u8
g_out_offset: int

ensure_out_bytes :: proc(num_bytes: int) {
	needed_len := g_out_offset + num_bytes
	if len(g_out) < needed_len {
		resize(&g_out, needed_len)
	}
}

send_messages :: proc() {
	os.write(os.stdout, g_out[:g_out_offset])
	g_out_offset = 0
}

msg_data_u8 :: proc(value: u8) {
	ensure_out_bytes(1)
	g_out[g_out_offset] = value
	g_out_offset += 1
}

msg_data_u32 :: proc(value: u32) {
	ensure_out_bytes(4)
	g_out[g_out_offset + 0] = u8(value & 0xff)
	g_out[g_out_offset + 1] = u8((value >> 8) & 0xff)
	g_out[g_out_offset + 2] = u8((value >> 16) & 0xff)
	g_out[g_out_offset + 3] = u8((value >> 24) & 0xff)
	g_out_offset += 4
}

