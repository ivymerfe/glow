package glowr

import "core:strings"

bytes_to_string :: proc "contextless" (arr: []byte) -> string {
	return strings.truncate_to_byte(string(arr), 0)
}
