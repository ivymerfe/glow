package xkbcommon

XKB_KEY_BackSpace :: 0xff08 /* U+0008 BACKSPACE */
XKB_KEY_Tab :: 0xff09 /* U+0009 CHARACTER TABULATION */
XKB_KEY_Linefeed :: 0xff0a /* U+000A LINE FEED */
XKB_KEY_Clear :: 0xff0b /* U+000B LINE TABULATION */
XKB_KEY_Return :: 0xff0d /* U+000D CARRIAGE RETURN */
XKB_KEY_Pause :: 0xff13 /* Pause, hold */
XKB_KEY_Scroll_Lock :: 0xff14
XKB_KEY_Sys_Req :: 0xff15
XKB_KEY_Escape :: 0xff1b /* U+001B ESCAPE */
XKB_KEY_Delete :: 0xffff /* U+007F DELETE */

XKB_KEY_Home :: 0xff50
XKB_KEY_Left :: 0xff51 /* Move left, left arrow */
XKB_KEY_Up :: 0xff52 /* Move up, up arrow */
XKB_KEY_Right :: 0xff53 /* Move right, right arrow */
XKB_KEY_Down :: 0xff54 /* Move down, down arrow */
XKB_KEY_Prior :: 0xff55 /* Prior, previous */
XKB_KEY_Page_Up :: 0xff55 /* deprecated alias for Prior */
XKB_KEY_Next :: 0xff56 /* Next */
XKB_KEY_Page_Down :: 0xff56 /* deprecated alias for Next */
XKB_KEY_End :: 0xff57 /* EOL */
XKB_KEY_Begin :: 0xff58 /* BOL */


/* Misc functions */

XKB_KEY_Select :: 0xff60 /* Select, mark */
XKB_KEY_Print :: 0xff61
XKB_KEY_Execute :: 0xff62 /* Execute, run, do */
XKB_KEY_Insert :: 0xff63 /* Insert, insert here */
XKB_KEY_Undo :: 0xff65
XKB_KEY_Redo :: 0xff66 /* Redo, again */
XKB_KEY_Menu :: 0xff67
XKB_KEY_Find :: 0xff68 /* Find, search */
XKB_KEY_Cancel :: 0xff69 /* Cancel, stop, abort, exit */
XKB_KEY_Help :: 0xff6a /* Help */
XKB_KEY_Break :: 0xff6b
XKB_KEY_Mode_switch :: 0xff7e /* Character set switch */
XKB_KEY_script_switch :: 0xff7e /* non-deprecated alias for Mode_switch */
XKB_KEY_Num_Lock :: 0xff7f

/* Keypad functions, keypad numbers cleverly chosen to map to ASCII */

XKB_KEY_KP_Space :: 0xff80 /*<U+0020 SPACE>*/
XKB_KEY_KP_Tab :: 0xff89 /*<U+0009 CHARACTER TABULATION>*/
XKB_KEY_KP_Enter :: 0xff8d /*<U+000D CARRIAGE RETURN>*/
XKB_KEY_KP_F1 :: 0xff91 /* PF1, KP_A, ... */
XKB_KEY_KP_F2 :: 0xff92
XKB_KEY_KP_F3 :: 0xff93
XKB_KEY_KP_F4 :: 0xff94
XKB_KEY_KP_Home :: 0xff95
XKB_KEY_KP_Left :: 0xff96
XKB_KEY_KP_Up :: 0xff97
XKB_KEY_KP_Right :: 0xff98
XKB_KEY_KP_Down :: 0xff99
XKB_KEY_KP_Prior :: 0xff9a
XKB_KEY_KP_Page_Up :: 0xff9a /* deprecated alias for KP_Prior */
XKB_KEY_KP_Next :: 0xff9b
XKB_KEY_KP_Page_Down :: 0xff9b /* deprecated alias for KP_Next */
XKB_KEY_KP_End :: 0xff9c
XKB_KEY_KP_Begin :: 0xff9d
XKB_KEY_KP_Insert :: 0xff9e
XKB_KEY_KP_Delete :: 0xff9f
XKB_KEY_KP_Equal :: 0xffbd /*<U+003D EQUALS SIGN>*/
XKB_KEY_KP_Multiply :: 0xffaa /*<U+002A ASTERISK>*/
XKB_KEY_KP_Add :: 0xffab /*<U+002B PLUS SIGN>*/
XKB_KEY_KP_Separator :: 0xffac /*<U+002C COMMA>*/
XKB_KEY_KP_Subtract :: 0xffad /*<U+002D HYPHEN-MINUS>*/
XKB_KEY_KP_Decimal :: 0xffae /*<U+002E FULL STOP>*/
XKB_KEY_KP_Divide :: 0xffaf /*<U+002F SOLIDUS>*/

XKB_KEY_KP_0 :: 0xffb0 /*<U+0030 DIGIT ZERO>*/
XKB_KEY_KP_1 :: 0xffb1 /*<U+0031 DIGIT ONE>*/
XKB_KEY_KP_2 :: 0xffb2 /*<U+0032 DIGIT TWO>*/
XKB_KEY_KP_3 :: 0xffb3 /*<U+0033 DIGIT THREE>*/
XKB_KEY_KP_4 :: 0xffb4 /*<U+0034 DIGIT FOUR>*/
XKB_KEY_KP_5 :: 0xffb5 /*<U+0035 DIGIT FIVE>*/
XKB_KEY_KP_6 :: 0xffb6 /*<U+0036 DIGIT SIX>*/
XKB_KEY_KP_7 :: 0xffb7 /*<U+0037 DIGIT SEVEN>*/
XKB_KEY_KP_8 :: 0xffb8 /*<U+0038 DIGIT EIGHT>*/
XKB_KEY_KP_9 :: 0xffb9 /*<U+0039 DIGIT NINE>*/


/*
 * Auxiliary functions; note the duplicate definitions for left and right
 * function keys;  Sun keyboards and a few other manufacturers have such
 * function key groups on the left and/or right sides of the keyboard.
 * We've not found a keyboard with more than 35 function keys total.
 */

XKB_KEY_F1 :: 0xffbe
XKB_KEY_F2 :: 0xffbf
XKB_KEY_F3 :: 0xffc0
XKB_KEY_F4 :: 0xffc1
XKB_KEY_F5 :: 0xffc2
XKB_KEY_F6 :: 0xffc3
XKB_KEY_F7 :: 0xffc4
XKB_KEY_F8 :: 0xffc5
XKB_KEY_F9 :: 0xffc6
XKB_KEY_F10 :: 0xffc7
XKB_KEY_F11 :: 0xffc8

/* Modifiers */

XKB_KEY_Shift_L :: 0xffe1 /* Left shift */
XKB_KEY_Shift_R :: 0xffe2 /* Right shift */
XKB_KEY_Control_L :: 0xffe3 /* Left control */
XKB_KEY_Control_R :: 0xffe4 /* Right control */
XKB_KEY_Caps_Lock :: 0xffe5 /* Caps lock */
XKB_KEY_Shift_Lock :: 0xffe6 /* Shift lock */

XKB_KEY_Meta_L :: 0xffe7 /* Left meta */
XKB_KEY_Meta_R :: 0xffe8 /* Right meta */
XKB_KEY_Alt_L :: 0xffe9 /* Left alt */
XKB_KEY_Alt_R :: 0xffea /* Right alt */
XKB_KEY_Super_L :: 0xffeb /* Left super */
XKB_KEY_Super_R :: 0xffec /* Right super */
XKB_KEY_Hyper_L :: 0xffed /* Left hyper */
XKB_KEY_Hyper_R :: 0xffee /* Right hyper */

/*
 * Latin 1
 * (ISO/IEC 8859-1 = Unicode U+0020..U+00FF)
 * Byte 3 = 0
 */
XKB_KEY_space :: 0x0020 /* U+0020 SPACE */
XKB_KEY_exclam :: 0x0021 /* U+0021 EXCLAMATION MARK */
XKB_KEY_quotedbl :: 0x0022 /* U+0022 QUOTATION MARK */
XKB_KEY_numbersign :: 0x0023 /* U+0023 NUMBER SIGN */
XKB_KEY_dollar :: 0x0024 /* U+0024 DOLLAR SIGN */
XKB_KEY_percent :: 0x0025 /* U+0025 PERCENT SIGN */
XKB_KEY_ampersand :: 0x0026 /* U+0026 AMPERSAND */
XKB_KEY_apostrophe :: 0x0027 /* U+0027 APOSTROPHE */
XKB_KEY_quoteright :: 0x0027 /* deprecated */
XKB_KEY_parenleft :: 0x0028 /* U+0028 LEFT PARENTHESIS */
XKB_KEY_parenright :: 0x0029 /* U+0029 RIGHT PARENTHESIS */
XKB_KEY_asterisk :: 0x002a /* U+002A ASTERISK */
XKB_KEY_plus :: 0x002b /* U+002B PLUS SIGN */
XKB_KEY_comma :: 0x002c /* U+002C COMMA */
XKB_KEY_minus :: 0x002d /* U+002D HYPHEN-MINUS */
XKB_KEY_period :: 0x002e /* U+002E FULL STOP */
XKB_KEY_slash :: 0x002f /* U+002F SOLIDUS */
XKB_KEY_0 :: 0x0030 /* U+0030 DIGIT ZERO */
XKB_KEY_1 :: 0x0031 /* U+0031 DIGIT ONE */
XKB_KEY_2 :: 0x0032 /* U+0032 DIGIT TWO */
XKB_KEY_3 :: 0x0033 /* U+0033 DIGIT THREE */
XKB_KEY_4 :: 0x0034 /* U+0034 DIGIT FOUR */
XKB_KEY_5 :: 0x0035 /* U+0035 DIGIT FIVE */
XKB_KEY_6 :: 0x0036 /* U+0036 DIGIT SIX */
XKB_KEY_7 :: 0x0037 /* U+0037 DIGIT SEVEN */
XKB_KEY_8 :: 0x0038 /* U+0038 DIGIT EIGHT */
XKB_KEY_9 :: 0x0039 /* U+0039 DIGIT NINE */
XKB_KEY_colon :: 0x003a /* U+003A COLON */
XKB_KEY_semicolon :: 0x003b /* U+003B SEMICOLON */
XKB_KEY_less :: 0x003c /* U+003C LESS-THAN SIGN */
XKB_KEY_equal :: 0x003d /* U+003D EQUALS SIGN */
XKB_KEY_greater :: 0x003e /* U+003E GREATER-THAN SIGN */
XKB_KEY_question :: 0x003f /* U+003F QUESTION MARK */
XKB_KEY_at :: 0x0040 /* U+0040 COMMERCIAL AT */
XKB_KEY_A :: 0x0041 /* U+0041 LATIN CAPITAL LETTER A */
XKB_KEY_B :: 0x0042 /* U+0042 LATIN CAPITAL LETTER B */
XKB_KEY_C :: 0x0043 /* U+0043 LATIN CAPITAL LETTER C */
XKB_KEY_D :: 0x0044 /* U+0044 LATIN CAPITAL LETTER D */
XKB_KEY_E :: 0x0045 /* U+0045 LATIN CAPITAL LETTER E */
XKB_KEY_F :: 0x0046 /* U+0046 LATIN CAPITAL LETTER F */
XKB_KEY_G :: 0x0047 /* U+0047 LATIN CAPITAL LETTER G */
XKB_KEY_H :: 0x0048 /* U+0048 LATIN CAPITAL LETTER H */
XKB_KEY_I :: 0x0049 /* U+0049 LATIN CAPITAL LETTER I */
XKB_KEY_J :: 0x004a /* U+004A LATIN CAPITAL LETTER J */
XKB_KEY_K :: 0x004b /* U+004B LATIN CAPITAL LETTER K */
XKB_KEY_L :: 0x004c /* U+004C LATIN CAPITAL LETTER L */
XKB_KEY_M :: 0x004d /* U+004D LATIN CAPITAL LETTER M */
XKB_KEY_N :: 0x004e /* U+004E LATIN CAPITAL LETTER N */
XKB_KEY_O :: 0x004f /* U+004F LATIN CAPITAL LETTER O */
XKB_KEY_P :: 0x0050 /* U+0050 LATIN CAPITAL LETTER P */
XKB_KEY_Q :: 0x0051 /* U+0051 LATIN CAPITAL LETTER Q */
XKB_KEY_R :: 0x0052 /* U+0052 LATIN CAPITAL LETTER R */
XKB_KEY_S :: 0x0053 /* U+0053 LATIN CAPITAL LETTER S */
XKB_KEY_T :: 0x0054 /* U+0054 LATIN CAPITAL LETTER T */
XKB_KEY_U :: 0x0055 /* U+0055 LATIN CAPITAL LETTER U */
XKB_KEY_V :: 0x0056 /* U+0056 LATIN CAPITAL LETTER V */
XKB_KEY_W :: 0x0057 /* U+0057 LATIN CAPITAL LETTER W */
XKB_KEY_X :: 0x0058 /* U+0058 LATIN CAPITAL LETTER X */
XKB_KEY_Y :: 0x0059 /* U+0059 LATIN CAPITAL LETTER Y */
XKB_KEY_Z :: 0x005a /* U+005A LATIN CAPITAL LETTER Z */
XKB_KEY_bracketleft :: 0x005b /* U+005B LEFT SQUARE BRACKET */
XKB_KEY_backslash :: 0x005c /* U+005C REVERSE SOLIDUS */
XKB_KEY_bracketright :: 0x005d /* U+005D RIGHT SQUARE BRACKET */
XKB_KEY_asciicircum :: 0x005e /* U+005E CIRCUMFLEX ACCENT */
XKB_KEY_underscore :: 0x005f /* U+005F LOW LINE */
XKB_KEY_grave :: 0x0060 /* U+0060 GRAVE ACCENT */
XKB_KEY_quoteleft :: 0x0060 /* deprecated */
XKB_KEY_a :: 0x0061 /* U+0061 LATIN SMALL LETTER A */
XKB_KEY_b :: 0x0062 /* U+0062 LATIN SMALL LETTER B */
XKB_KEY_c :: 0x0063 /* U+0063 LATIN SMALL LETTER C */
XKB_KEY_d :: 0x0064 /* U+0064 LATIN SMALL LETTER D */
XKB_KEY_e :: 0x0065 /* U+0065 LATIN SMALL LETTER E */
XKB_KEY_f :: 0x0066 /* U+0066 LATIN SMALL LETTER F */
XKB_KEY_g :: 0x0067 /* U+0067 LATIN SMALL LETTER G */
XKB_KEY_h :: 0x0068 /* U+0068 LATIN SMALL LETTER H */
XKB_KEY_i :: 0x0069 /* U+0069 LATIN SMALL LETTER I */
XKB_KEY_j :: 0x006a /* U+006A LATIN SMALL LETTER J */
XKB_KEY_k :: 0x006b /* U+006B LATIN SMALL LETTER K */
XKB_KEY_l :: 0x006c /* U+006C LATIN SMALL LETTER L */
XKB_KEY_m :: 0x006d /* U+006D LATIN SMALL LETTER M */
XKB_KEY_n :: 0x006e /* U+006E LATIN SMALL LETTER N */
XKB_KEY_o :: 0x006f /* U+006F LATIN SMALL LETTER O */
XKB_KEY_p :: 0x0070 /* U+0070 LATIN SMALL LETTER P */
XKB_KEY_q :: 0x0071 /* U+0071 LATIN SMALL LETTER Q */
XKB_KEY_r :: 0x0072 /* U+0072 LATIN SMALL LETTER R */
XKB_KEY_s :: 0x0073 /* U+0073 LATIN SMALL LETTER S */
XKB_KEY_t :: 0x0074 /* U+0074 LATIN SMALL LETTER T */
XKB_KEY_u :: 0x0075 /* U+0075 LATIN SMALL LETTER U */
XKB_KEY_v :: 0x0076 /* U+0076 LATIN SMALL LETTER V */
XKB_KEY_w :: 0x0077 /* U+0077 LATIN SMALL LETTER W */
XKB_KEY_x :: 0x0078 /* U+0078 LATIN SMALL LETTER X */
XKB_KEY_y :: 0x0079 /* U+0079 LATIN SMALL LETTER Y */
XKB_KEY_z :: 0x007a /* U+007A LATIN SMALL LETTER Z */
XKB_KEY_braceleft :: 0x007b /* U+007B LEFT CURLY BRACKET */
XKB_KEY_bar :: 0x007c /* U+007C VERTICAL LINE */
XKB_KEY_braceright :: 0x007d /* U+007D RIGHT CURLY BRACKET */
XKB_KEY_asciitilde :: 0x007e /* U+007E TILDE */
