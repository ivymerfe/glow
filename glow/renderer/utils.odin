package renderer

import "core:strings"

bytes_to_string :: proc "contextless" (arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}
