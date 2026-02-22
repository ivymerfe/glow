package glow

import "core:strings"
import "core:sync"
import "core:thread"

import "glowr"

CompileRequest :: struct {
	buf:    ^glowr.ProgramBuffer,
	path:   string,
	source: string,
}

CompilerThread :: struct {
	thread:  ^thread.Thread,
	evt:     sync.Auto_Reset_Event,
	mtx:     sync.Mutex,
	request: CompileRequest,
	stop:    bool,
}

compiler_start :: proc(comp: ^CompilerThread) {
	comp.stop = false
	comp.thread = thread.create_and_start_with_data(comp, compiler_proc, context)
}

compiler_stop :: proc(comp: ^CompilerThread) {
	if comp.thread == nil {
		return
	}
	sync.atomic_store(&comp.stop, true)
	compiler_wakeup(comp)
	thread.join(comp.thread)
	thread.destroy(comp.thread)
	comp.thread = nil
}

compiler_wakeup :: proc(comp: ^CompilerThread) {
	sync.auto_reset_event_signal(&comp.evt)
}

compiler_submit :: proc(comp: ^CompilerThread, req: CompileRequest) {
	sync.lock(&comp.mtx)
	comp.request = req
	sync.unlock(&comp.mtx)
	compiler_wakeup(comp)
}

compiler_proc :: proc(raw: rawptr) {
	w := cast(^CompilerThread)raw
	request: CompileRequest
	for {
		sync.auto_reset_event_wait(&w.evt)
		if sync.atomic_load(&w.stop) {
			break
		}
		sync.lock(&w.mtx)
		request = w.request
		sync.unlock(&w.mtx)

		path_c := strings.clone_to_cstring(w.request.path)
		source_c := strings.clone_to_cstring(w.request.source)
		defer delete_cstring(path_c)
		defer delete_cstring(source_c)

		prog: glowr.Program
		success := glowr.compile_program(&prog, &g_ctx.res, g_ctx.slang, path_c, source_c)
		if success {
			glowr.program_buffer_set(request.buf, prog)
			renderer_wakeup(&g_ctx.renderer)
		}
	}
}
