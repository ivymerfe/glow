package glow


IndexAllocator :: struct {
	max:  uint,
	used: map[uint]bool,
}

alloc_index :: proc(ia: ^IndexAllocator) -> (index: uint, success: bool) {
	for i in 0 ..< ia.max {
		if !ia.used[i] {
			ia.used[i] = true
			return i, true
		}
	}
	return 0, false
}

free_index :: proc(ia: ^IndexAllocator, index: uint) {
	if index < ia.max {
		ia.used[index] = false
	}
}
