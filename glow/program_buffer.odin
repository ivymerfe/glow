package glow

import "../rend"
import "core:sync"

ProgramBuffer :: struct {
	prog:            rend.Program,
	next:            rend.Program,
	should_swap:     bool,
	ready:           bool,
	mtx:             sync.Mutex,
	source:          string,
	path:            string,
	source_version:  int,
	program_version: int,
	source_mtx:      sync.Mutex,
}

pbuf_render_done :: proc(pb: ^ProgramBuffer) {
	if sync.atomic_load(&pb.should_swap) {
		sync.lock(&pb.mtx)
		rend.inherit_program_state(&pb.next, &pb.prog)
		rend.destroy_program(&pb.prog)
		pb.prog = pb.next
		pb.next = {}
		sync.atomic_store(&pb.should_swap, false)
		sync.unlock(&pb.mtx)
	}
}

pbuf_compile_done :: proc(pb: ^ProgramBuffer, success: bool, prog: rend.Program, version: int) {
	if success {
		sync.lock(&pb.mtx)
		rend.destroy_program(&pb.next)
		pb.next = prog
		sync.atomic_store(&pb.should_swap, true)
		sync.atomic_store(&pb.ready, true)
		sync.unlock(&pb.mtx)
	}
	sync.atomic_store(&pb.program_version, version)
}

pbuf_should_recompile :: proc(pb: ^ProgramBuffer) -> bool {
	return sync.atomic_load(&pb.source_version) != sync.atomic_load(&pb.program_version)
}

pbuf_get_source :: proc(pb: ^ProgramBuffer) -> (path: string, source: string, version: int) {
	sync.lock(&pb.source_mtx)
	defer sync.unlock(&pb.source_mtx)
	return pb.path, pb.source, sync.atomic_load(&pb.source_version)
}

pbuf_update_source :: proc(pb: ^ProgramBuffer, path: string, source: string) {
	sync.lock(&pb.source_mtx)
	pb.path = path
	pb.source = source
	sync.atomic_add(&pb.source_version, 1)
	sync.unlock(&pb.source_mtx)
}

