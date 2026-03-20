package glow


IndexAllocator :: struct {
	max:  u32,
	used: map[u32]bool,
}

alloc_index :: proc(ia: ^IndexAllocator) -> (index: u32, success: bool) {
	for i in 0 ..< ia.max {
		if !ia.used[i] {
			ia.used[i] = true
			return i, true
		}
	}
	return 0, false
}

free_index :: proc(ia: ^IndexAllocator, index: u32) {
	if index < ia.max {
		ia.used[index] = false
	}
}
