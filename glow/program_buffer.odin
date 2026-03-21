package glow

import "core:sync"
import "glowr"

ProgramBuffer :: struct {
	p1:            glowr.Program,
	p2:            glowr.Program,
	is_p2_current: bool,
	should_swap:   bool,
	source:        string,
	path:          string,
	recompile:     bool,
	source_mtx:    sync.Mutex,
}

pbuf_get_current :: proc(pb: ^ProgramBuffer) -> ^glowr.Program {
	if sync.atomic_load(&pb.is_p2_current) {
		return &pb.p2
	} else {
		return &pb.p1
	}
}

pbuf_get_next :: proc(pb: ^ProgramBuffer) -> ^glowr.Program {
	if sync.atomic_load(&pb.is_p2_current) {
		return &pb.p1
	} else {
		return &pb.p2
	}
}

pbuf_render_done :: proc(pb: ^ProgramBuffer) {
	if sync.atomic_load(&pb.should_swap) {
		is_p2 := !sync.atomic_load(&pb.is_p2_current)
		sync.atomic_store(&pb.is_p2_current, is_p2)
		sync.atomic_store(&pb.should_swap, false)

		if is_p2 {
			glowr.inherit_program_state(&pb.p2, &pb.p1)
		} else {
			glowr.inherit_program_state(&pb.p1, &pb.p2)
		}
	}
}

pbuf_compile_done :: proc(pb: ^ProgramBuffer, success: bool) {
	if success {
		sync.atomic_store(&pb.should_swap, true)
	}
	sync.atomic_store(&pb.recompile, false)
}

pbuf_should_recompile :: proc(pb: ^ProgramBuffer) -> bool {
	return sync.atomic_load(&pb.recompile)
}

pbuf_get_source :: proc(pb: ^ProgramBuffer) -> (path: string, source: string) {
	sync.lock(&pb.source_mtx)
	defer sync.unlock(&pb.source_mtx)
	return pb.path, pb.source
}

pbuf_update_source :: proc(pb: ^ProgramBuffer, path: string, source: string) {
	sync.lock(&pb.source_mtx)
	pb.path = path
	pb.source = source
	sync.unlock(&pb.source_mtx)
	sync.atomic_store(&pb.recompile, true)
}
