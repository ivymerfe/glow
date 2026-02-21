package glow

import "core:strings"
import "core:sync"
import "core:thread"

CompileRequest :: struct {
	ren:    ^GlowRenderer,
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

compiler_start :: proc(w: ^CompilerThread) {
	w.stop = false
	w.thread = thread.create_and_start_with_data(w, compiler_proc, context)
}

compiler_stop :: proc(w: ^CompilerThread) {
	if w.thread == nil {
		return
	}

	sync.atomic_store(&w.stop, true)
	sync.auto_reset_event_signal(&w.evt)

	thread.join(w.thread)
	thread.destroy(w.thread)
	w.thread = nil
}

compiler_submit :: proc(w: ^CompilerThread, req: CompileRequest) {
	sync.lock(&w.mtx)
	w.request = req
	sync.unlock(&w.mtx)
	sync.auto_reset_event_signal(&w.evt)
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

		ctx: GlowContext
		success := compile_program(&ctx, path_c, source_c)
		if !success {
			continue
		}
		swapper_set_next(&request.ren.context_swapper, ctx)

		sync.auto_reset_event_signal(&g_wakeup_renderer)
	}
}
