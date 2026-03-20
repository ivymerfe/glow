package glow

import "core:sync"
import "glowr"

ProgramBuffer :: struct {
	curr:       glowr.Program,
	next:       glowr.Program,
	is_swap:    bool,
	source:     string,
	path:       string,
	recompile:  bool,
	source_mtx: sync.Mutex,
}

pbuf_get_current :: proc(pb: ^ProgramBuffer) -> ^glowr.Program {
	if sync.atomic_load(&pb.is_swap) {
		return &pb.next
	} else {
		return &pb.curr
	}
}

pbuf_get_next :: proc(pb: ^ProgramBuffer) -> ^glowr.Program {
	if sync.atomic_load(&pb.is_swap) {
		return &pb.curr
	} else {
		return &pb.next
	}
}

pbuf_swap :: proc(pb: ^ProgramBuffer) {
	is_swap := sync.atomic_load(&pb.is_swap)
	sync.atomic_store(&pb.is_swap, !is_swap)
}

pbuf_update_source :: proc(pb: ^ProgramBuffer, path: string, source: string) {
	sync.lock(&pb.source_mtx)
	pb.path = path
	pb.source = source
	sync.atomic_store(&pb.recompile, true)
	sync.unlock(&pb.source_mtx)
}

pbuf_should_recompile :: proc(pb: ^ProgramBuffer) -> bool {
	return sync.atomic_load(&pb.recompile)
}

pbuf_get_source :: proc(pb: ^ProgramBuffer) -> (path: string, source: string) {
	sync.lock(&pb.source_mtx)
	defer sync.unlock(&pb.source_mtx)
	return pb.path, pb.source
}
