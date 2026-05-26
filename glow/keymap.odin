package glow

import "../gwin/xkb"

KEY_MOUSE_LEFT :: 0
KEY_MOUSE_RIGHT :: 1
KEY_MOUSE_MIDDLE :: 2
KEY_MOUSE_4 :: 3
KEY_MOUSE_5 :: 4

KEY_A :: 5
KEY_B :: 6
KEY_C :: 7
KEY_D :: 8
KEY_E :: 9
KEY_F :: 10
KEY_G :: 11
KEY_H :: 12
KEY_I :: 13
KEY_J :: 14
KEY_K :: 15
KEY_L :: 16
KEY_M :: 17
KEY_N :: 18
KEY_O :: 19
KEY_P :: 20
KEY_Q :: 21
KEY_R :: 22
KEY_S :: 23
KEY_T :: 24
KEY_U :: 25
KEY_V :: 26
KEY_W :: 27
KEY_X :: 28
KEY_Y :: 29
KEY_Z :: 30

KEY_1 :: 31
KEY_2 :: 32
KEY_3 :: 33
KEY_4 :: 34
KEY_5 :: 35
KEY_6 :: 36
KEY_7 :: 37
KEY_8 :: 38
KEY_9 :: 39
KEY_0 :: 40

KEY_ENTER :: 41
KEY_ESCAPE :: 42
KEY_BACKSPACE :: 43
KEY_TAB :: 44
KEY_SPACE :: 45
KEY_MINUS :: 46
KEY_EQUAL :: 47
KEY_LEFT_BRACKET :: 48
KEY_RIGHT_BRACKET :: 49
KEY_BACKSLASH :: 50
KEY_SEMICOLON :: 51
KEY_APOSTROPHE :: 52
KEY_GRAVE :: 53
KEY_COMMA :: 54
KEY_PERIOD :: 55
KEY_SLASH :: 56

KEY_F1 :: 57
KEY_F2 :: 58
KEY_F3 :: 59
KEY_F4 :: 60
KEY_F5 :: 61
KEY_F6 :: 62
KEY_F7 :: 63
KEY_F8 :: 64
KEY_F9 :: 65
KEY_F10 :: 66
KEY_F11 :: 67

KEY_PAUSE :: 68
KEY_INSERT :: 69
KEY_HOME :: 70
KEY_PAGE_UP :: 71
KEY_DELETE :: 72
KEY_END :: 73
KEY_PAGE_DOWN :: 74
KEY_RIGHT :: 75
KEY_LEFT :: 76
KEY_DOWN :: 77
KEY_UP :: 78

KEY_KP_DIVIDE :: 79
KEY_KP_MULTIPLY :: 80
KEY_KP_SUBTRACT :: 81
KEY_KP_ADD :: 82
KEY_KP_ENTER :: 83
KEY_KP_1 :: 84
KEY_KP_2 :: 85
KEY_KP_3 :: 86
KEY_KP_4 :: 87
KEY_KP_5 :: 88
KEY_KP_6 :: 89
KEY_KP_7 :: 90
KEY_KP_8 :: 91
KEY_KP_9 :: 92
KEY_KP_0 :: 93
KEY_KP_DECIMAL :: 94
KEY_MENU :: 95

KEY_LEFT_CTRL :: 96
KEY_LEFT_SHIFT :: 97
KEY_LEFT_ALT :: 98
KEY_LEFT_SUPER :: 99
KEY_RIGHT_CTRL :: 100
KEY_RIGHT_SHIFT :: 101
KEY_RIGHT_ALT :: 102
KEY_RIGHT_SUPER :: 103
KEY_COUNT :: 104

WAYLAND_BTN_LEFT :: 272
WAYLAND_BTN_RIGHT :: 273
WAYLAND_BTN_MIDDLE :: 274
WAYLAND_BTN_4 :: 275
WAYLAND_BTN_5 :: 276

KeyMapEntry :: struct {
	src: u32,
	dst: u32,
}

KEYMAP_ENTRIES :: []KeyMapEntry {
	{xkb.KEY_a, KEY_A},
	{xkb.KEY_A, KEY_A},
	{xkb.KEY_b, KEY_B},
	{xkb.KEY_B, KEY_B},
	{xkb.KEY_c, KEY_C},
	{xkb.KEY_C, KEY_C},
	{xkb.KEY_d, KEY_D},
	{xkb.KEY_D, KEY_D},
	{xkb.KEY_e, KEY_E},
	{xkb.KEY_E, KEY_E},
	{xkb.KEY_f, KEY_F},
	{xkb.KEY_F, KEY_F},
	{xkb.KEY_g, KEY_G},
	{xkb.KEY_G, KEY_G},
	{xkb.KEY_h, KEY_H},
	{xkb.KEY_H, KEY_H},
	{xkb.KEY_i, KEY_I},
	{xkb.KEY_I, KEY_I},
	{xkb.KEY_j, KEY_J},
	{xkb.KEY_J, KEY_J},
	{xkb.KEY_k, KEY_K},
	{xkb.KEY_K, KEY_K},
	{xkb.KEY_l, KEY_L},
	{xkb.KEY_L, KEY_L},
	{xkb.KEY_m, KEY_M},
	{xkb.KEY_M, KEY_M},
	{xkb.KEY_n, KEY_N},
	{xkb.KEY_N, KEY_N},
	{xkb.KEY_o, KEY_O},
	{xkb.KEY_O, KEY_O},
	{xkb.KEY_p, KEY_P},
	{xkb.KEY_P, KEY_P},
	{xkb.KEY_q, KEY_Q},
	{xkb.KEY_Q, KEY_Q},
	{xkb.KEY_r, KEY_R},
	{xkb.KEY_R, KEY_R},
	{xkb.KEY_s, KEY_S},
	{xkb.KEY_S, KEY_S},
	{xkb.KEY_t, KEY_T},
	{xkb.KEY_T, KEY_T},
	{xkb.KEY_u, KEY_U},
	{xkb.KEY_U, KEY_U},
	{xkb.KEY_v, KEY_V},
	{xkb.KEY_V, KEY_V},
	{xkb.KEY_w, KEY_W},
	{xkb.KEY_W, KEY_W},
	{xkb.KEY_x, KEY_X},
	{xkb.KEY_X, KEY_X},
	{xkb.KEY_y, KEY_Y},
	{xkb.KEY_Y, KEY_Y},
	{xkb.KEY_z, KEY_Z},
	{xkb.KEY_Z, KEY_Z},
	{xkb.KEY_1, KEY_1},
	{xkb.KEY_exclam, KEY_1},
	{xkb.KEY_2, KEY_2},
	{xkb.KEY_at, KEY_2},
	{xkb.KEY_3, KEY_3},
	{xkb.KEY_numbersign, KEY_3},
	{xkb.KEY_4, KEY_4},
	{xkb.KEY_dollar, KEY_4},
	{xkb.KEY_5, KEY_5},
	{xkb.KEY_percent, KEY_5},
	{xkb.KEY_6, KEY_6},
	{xkb.KEY_asciicircum, KEY_6},
	{xkb.KEY_7, KEY_7},
	{xkb.KEY_ampersand, KEY_7},
	{xkb.KEY_8, KEY_8},
	{xkb.KEY_asterisk, KEY_8},
	{xkb.KEY_9, KEY_9},
	{xkb.KEY_parenleft, KEY_9},
	{xkb.KEY_0, KEY_0},
	{xkb.KEY_parenright, KEY_0},
	{xkb.KEY_Return, KEY_ENTER},
	{xkb.KEY_Escape, KEY_ESCAPE},
	{xkb.KEY_BackSpace, KEY_BACKSPACE},
	{xkb.KEY_Tab, KEY_TAB},
	{xkb.KEY_space, KEY_SPACE},
	{xkb.KEY_minus, KEY_MINUS},
	{xkb.KEY_underscore, KEY_MINUS},
	{xkb.KEY_equal, KEY_EQUAL},
	{xkb.KEY_plus, KEY_EQUAL},
	{xkb.KEY_bracketleft, KEY_LEFT_BRACKET},
	{xkb.KEY_braceleft, KEY_LEFT_BRACKET},
	{xkb.KEY_bracketright, KEY_RIGHT_BRACKET},
	{xkb.KEY_braceright, KEY_RIGHT_BRACKET},
	{xkb.KEY_backslash, KEY_BACKSLASH},
	{xkb.KEY_bar, KEY_BACKSLASH},
	{xkb.KEY_semicolon, KEY_SEMICOLON},
	{xkb.KEY_colon, KEY_SEMICOLON},
	{xkb.KEY_apostrophe, KEY_APOSTROPHE},
	{xkb.KEY_quotedbl, KEY_APOSTROPHE},
	{xkb.KEY_grave, KEY_GRAVE},
	{xkb.KEY_asciitilde, KEY_GRAVE},
	{xkb.KEY_comma, KEY_COMMA},
	{xkb.KEY_less, KEY_COMMA},
	{xkb.KEY_period, KEY_PERIOD},
	{xkb.KEY_greater, KEY_PERIOD},
	{xkb.KEY_slash, KEY_SLASH},
	{xkb.KEY_question, KEY_SLASH},
	{xkb.KEY_F1, KEY_F1},
	{xkb.KEY_F2, KEY_F2},
	{xkb.KEY_F3, KEY_F3},
	{xkb.KEY_F4, KEY_F4},
	{xkb.KEY_F5, KEY_F5},
	{xkb.KEY_F6, KEY_F6},
	{xkb.KEY_F7, KEY_F7},
	{xkb.KEY_F8, KEY_F8},
	{xkb.KEY_F9, KEY_F9},
	{xkb.KEY_F10, KEY_F10},
	{xkb.KEY_F11, KEY_F11},
	{xkb.KEY_Pause, KEY_PAUSE},
	{xkb.KEY_Insert, KEY_INSERT},
	{xkb.KEY_Home, KEY_HOME},
	{xkb.KEY_Page_Up, KEY_PAGE_UP},
	{xkb.KEY_Delete, KEY_DELETE},
	{xkb.KEY_End, KEY_END},
	{xkb.KEY_Page_Down, KEY_PAGE_DOWN},
	{xkb.KEY_Right, KEY_RIGHT},
	{xkb.KEY_Left, KEY_LEFT},
	{xkb.KEY_Down, KEY_DOWN},
	{xkb.KEY_Up, KEY_UP},
	{xkb.KEY_KP_Divide, KEY_KP_DIVIDE},
	{xkb.KEY_KP_Multiply, KEY_KP_MULTIPLY},
	{xkb.KEY_KP_Subtract, KEY_KP_SUBTRACT},
	{xkb.KEY_KP_Add, KEY_KP_ADD},
	{xkb.KEY_KP_Enter, KEY_KP_ENTER},
	{xkb.KEY_KP_1, KEY_KP_1},
	{xkb.KEY_KP_2, KEY_KP_2},
	{xkb.KEY_KP_3, KEY_KP_3},
	{xkb.KEY_KP_4, KEY_KP_4},
	{xkb.KEY_KP_5, KEY_KP_5},
	{xkb.KEY_KP_6, KEY_KP_6},
	{xkb.KEY_KP_7, KEY_KP_7},
	{xkb.KEY_KP_8, KEY_KP_8},
	{xkb.KEY_KP_9, KEY_KP_9},
	{xkb.KEY_KP_0, KEY_KP_0},
	{xkb.KEY_KP_Decimal, KEY_KP_DECIMAL},
	{xkb.KEY_Menu, KEY_MENU},
	{xkb.KEY_Control_L, KEY_LEFT_CTRL},
	{xkb.KEY_Shift_L, KEY_LEFT_SHIFT},
	{xkb.KEY_Alt_L, KEY_LEFT_ALT},
	{xkb.KEY_Super_L, KEY_LEFT_SUPER},
	{xkb.KEY_Control_R, KEY_RIGHT_CTRL},
	{xkb.KEY_Shift_R, KEY_RIGHT_SHIFT},
	{xkb.KEY_Alt_R, KEY_RIGHT_ALT},
	{xkb.KEY_Super_R, KEY_RIGHT_SUPER},
}

MOUSE_KEYMAP_ENTRIES :: []KeyMapEntry {
	{WAYLAND_BTN_LEFT, KEY_MOUSE_LEFT},
	{WAYLAND_BTN_RIGHT, KEY_MOUSE_RIGHT},
	{WAYLAND_BTN_MIDDLE, KEY_MOUSE_MIDDLE},
	{WAYLAND_BTN_4, KEY_MOUSE_4},
	{WAYLAND_BTN_5, KEY_MOUSE_5},
}

g_keymap: map[u32]u32
g_mouse_keymap: map[u32]u32
g_keymap_ready := false

init_keymap :: proc() {
	if g_keymap_ready {
		return
	}
	for entry in KEYMAP_ENTRIES {
		g_keymap[entry.src] = entry.dst
	}
	for entry in MOUSE_KEYMAP_ENTRIES {
		g_mouse_keymap[entry.src] = entry.dst
	}
	g_keymap_ready = true
}

map_xkb_keysym :: proc(keysym: u32) -> (key: u32, ok: bool) {
	key, ok = g_keymap[keysym]
	return
}

map_wayland_mouse_button :: proc(button: u32) -> (key: u32, ok: bool) {
	key, ok = g_mouse_keymap[button]
	return
}

