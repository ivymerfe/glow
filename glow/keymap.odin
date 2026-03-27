package glow

import xkb "gwin/xkbcommon"

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

XKB_KEYMAP_ENTRIES :: []KeyMapEntry {
	{xkb.XKB_KEY_a, KEY_A},
	{xkb.XKB_KEY_A, KEY_A},
	{xkb.XKB_KEY_b, KEY_B},
	{xkb.XKB_KEY_B, KEY_B},
	{xkb.XKB_KEY_c, KEY_C},
	{xkb.XKB_KEY_C, KEY_C},
	{xkb.XKB_KEY_d, KEY_D},
	{xkb.XKB_KEY_D, KEY_D},
	{xkb.XKB_KEY_e, KEY_E},
	{xkb.XKB_KEY_E, KEY_E},
	{xkb.XKB_KEY_f, KEY_F},
	{xkb.XKB_KEY_F, KEY_F},
	{xkb.XKB_KEY_g, KEY_G},
	{xkb.XKB_KEY_G, KEY_G},
	{xkb.XKB_KEY_h, KEY_H},
	{xkb.XKB_KEY_H, KEY_H},
	{xkb.XKB_KEY_i, KEY_I},
	{xkb.XKB_KEY_I, KEY_I},
	{xkb.XKB_KEY_j, KEY_J},
	{xkb.XKB_KEY_J, KEY_J},
	{xkb.XKB_KEY_k, KEY_K},
	{xkb.XKB_KEY_K, KEY_K},
	{xkb.XKB_KEY_l, KEY_L},
	{xkb.XKB_KEY_L, KEY_L},
	{xkb.XKB_KEY_m, KEY_M},
	{xkb.XKB_KEY_M, KEY_M},
	{xkb.XKB_KEY_n, KEY_N},
	{xkb.XKB_KEY_N, KEY_N},
	{xkb.XKB_KEY_o, KEY_O},
	{xkb.XKB_KEY_O, KEY_O},
	{xkb.XKB_KEY_p, KEY_P},
	{xkb.XKB_KEY_P, KEY_P},
	{xkb.XKB_KEY_q, KEY_Q},
	{xkb.XKB_KEY_Q, KEY_Q},
	{xkb.XKB_KEY_r, KEY_R},
	{xkb.XKB_KEY_R, KEY_R},
	{xkb.XKB_KEY_s, KEY_S},
	{xkb.XKB_KEY_S, KEY_S},
	{xkb.XKB_KEY_t, KEY_T},
	{xkb.XKB_KEY_T, KEY_T},
	{xkb.XKB_KEY_u, KEY_U},
	{xkb.XKB_KEY_U, KEY_U},
	{xkb.XKB_KEY_v, KEY_V},
	{xkb.XKB_KEY_V, KEY_V},
	{xkb.XKB_KEY_w, KEY_W},
	{xkb.XKB_KEY_W, KEY_W},
	{xkb.XKB_KEY_x, KEY_X},
	{xkb.XKB_KEY_X, KEY_X},
	{xkb.XKB_KEY_y, KEY_Y},
	{xkb.XKB_KEY_Y, KEY_Y},
	{xkb.XKB_KEY_z, KEY_Z},
	{xkb.XKB_KEY_Z, KEY_Z},
	{xkb.XKB_KEY_1, KEY_1},
	{xkb.XKB_KEY_exclam, KEY_1},
	{xkb.XKB_KEY_2, KEY_2},
	{xkb.XKB_KEY_at, KEY_2},
	{xkb.XKB_KEY_3, KEY_3},
	{xkb.XKB_KEY_numbersign, KEY_3},
	{xkb.XKB_KEY_4, KEY_4},
	{xkb.XKB_KEY_dollar, KEY_4},
	{xkb.XKB_KEY_5, KEY_5},
	{xkb.XKB_KEY_percent, KEY_5},
	{xkb.XKB_KEY_6, KEY_6},
	{xkb.XKB_KEY_asciicircum, KEY_6},
	{xkb.XKB_KEY_7, KEY_7},
	{xkb.XKB_KEY_ampersand, KEY_7},
	{xkb.XKB_KEY_8, KEY_8},
	{xkb.XKB_KEY_asterisk, KEY_8},
	{xkb.XKB_KEY_9, KEY_9},
	{xkb.XKB_KEY_parenleft, KEY_9},
	{xkb.XKB_KEY_0, KEY_0},
	{xkb.XKB_KEY_parenright, KEY_0},
	{xkb.XKB_KEY_Return, KEY_ENTER},
	{xkb.XKB_KEY_Escape, KEY_ESCAPE},
	{xkb.XKB_KEY_BackSpace, KEY_BACKSPACE},
	{xkb.XKB_KEY_Tab, KEY_TAB},
	{xkb.XKB_KEY_space, KEY_SPACE},
	{xkb.XKB_KEY_minus, KEY_MINUS},
	{xkb.XKB_KEY_underscore, KEY_MINUS},
	{xkb.XKB_KEY_equal, KEY_EQUAL},
	{xkb.XKB_KEY_plus, KEY_EQUAL},
	{xkb.XKB_KEY_bracketleft, KEY_LEFT_BRACKET},
	{xkb.XKB_KEY_braceleft, KEY_LEFT_BRACKET},
	{xkb.XKB_KEY_bracketright, KEY_RIGHT_BRACKET},
	{xkb.XKB_KEY_braceright, KEY_RIGHT_BRACKET},
	{xkb.XKB_KEY_backslash, KEY_BACKSLASH},
	{xkb.XKB_KEY_bar, KEY_BACKSLASH},
	{xkb.XKB_KEY_semicolon, KEY_SEMICOLON},
	{xkb.XKB_KEY_colon, KEY_SEMICOLON},
	{xkb.XKB_KEY_apostrophe, KEY_APOSTROPHE},
	{xkb.XKB_KEY_quotedbl, KEY_APOSTROPHE},
	{xkb.XKB_KEY_grave, KEY_GRAVE},
	{xkb.XKB_KEY_asciitilde, KEY_GRAVE},
	{xkb.XKB_KEY_comma, KEY_COMMA},
	{xkb.XKB_KEY_less, KEY_COMMA},
	{xkb.XKB_KEY_period, KEY_PERIOD},
	{xkb.XKB_KEY_greater, KEY_PERIOD},
	{xkb.XKB_KEY_slash, KEY_SLASH},
	{xkb.XKB_KEY_question, KEY_SLASH},
	{xkb.XKB_KEY_F1, KEY_F1},
	{xkb.XKB_KEY_F2, KEY_F2},
	{xkb.XKB_KEY_F3, KEY_F3},
	{xkb.XKB_KEY_F4, KEY_F4},
	{xkb.XKB_KEY_F5, KEY_F5},
	{xkb.XKB_KEY_F6, KEY_F6},
	{xkb.XKB_KEY_F7, KEY_F7},
	{xkb.XKB_KEY_F8, KEY_F8},
	{xkb.XKB_KEY_F9, KEY_F9},
	{xkb.XKB_KEY_F10, KEY_F10},
	{xkb.XKB_KEY_F11, KEY_F11},
	{xkb.XKB_KEY_Pause, KEY_PAUSE},
	{xkb.XKB_KEY_Insert, KEY_INSERT},
	{xkb.XKB_KEY_Home, KEY_HOME},
	{xkb.XKB_KEY_Page_Up, KEY_PAGE_UP},
	{xkb.XKB_KEY_Delete, KEY_DELETE},
	{xkb.XKB_KEY_End, KEY_END},
	{xkb.XKB_KEY_Page_Down, KEY_PAGE_DOWN},
	{xkb.XKB_KEY_Right, KEY_RIGHT},
	{xkb.XKB_KEY_Left, KEY_LEFT},
	{xkb.XKB_KEY_Down, KEY_DOWN},
	{xkb.XKB_KEY_Up, KEY_UP},
	{xkb.XKB_KEY_KP_Divide, KEY_KP_DIVIDE},
	{xkb.XKB_KEY_KP_Multiply, KEY_KP_MULTIPLY},
	{xkb.XKB_KEY_KP_Subtract, KEY_KP_SUBTRACT},
	{xkb.XKB_KEY_KP_Add, KEY_KP_ADD},
	{xkb.XKB_KEY_KP_Enter, KEY_KP_ENTER},
	{xkb.XKB_KEY_KP_1, KEY_KP_1},
	{xkb.XKB_KEY_KP_2, KEY_KP_2},
	{xkb.XKB_KEY_KP_3, KEY_KP_3},
	{xkb.XKB_KEY_KP_4, KEY_KP_4},
	{xkb.XKB_KEY_KP_5, KEY_KP_5},
	{xkb.XKB_KEY_KP_6, KEY_KP_6},
	{xkb.XKB_KEY_KP_7, KEY_KP_7},
	{xkb.XKB_KEY_KP_8, KEY_KP_8},
	{xkb.XKB_KEY_KP_9, KEY_KP_9},
	{xkb.XKB_KEY_KP_0, KEY_KP_0},
	{xkb.XKB_KEY_KP_Decimal, KEY_KP_DECIMAL},
	{xkb.XKB_KEY_Menu, KEY_MENU},
	{xkb.XKB_KEY_Control_L, KEY_LEFT_CTRL},
	{xkb.XKB_KEY_Shift_L, KEY_LEFT_SHIFT},
	{xkb.XKB_KEY_Alt_L, KEY_LEFT_ALT},
	{xkb.XKB_KEY_Super_L, KEY_LEFT_SUPER},
	{xkb.XKB_KEY_Control_R, KEY_RIGHT_CTRL},
	{xkb.XKB_KEY_Shift_R, KEY_RIGHT_SHIFT},
	{xkb.XKB_KEY_Alt_R, KEY_RIGHT_ALT},
	{xkb.XKB_KEY_Super_R, KEY_RIGHT_SUPER},
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
	for entry in XKB_KEYMAP_ENTRIES {
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
