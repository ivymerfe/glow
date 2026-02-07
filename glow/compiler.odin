package glow

import "core:time"
import "core:log"
import "core:strings"
import "core:sync"
import "core:thread"

import slang "odin_slang"

CompilerWorker :: struct {
	thread:  ^thread.Thread,
	mtx:     sync.Mutex,
	evt:     sync.Auto_Reset_Event,

	// Wiring (owned elsewhere; must outlive the worker thread)
	glow:    ^GlowContext,

	// Request state (protected by mtx)
	pending: bool,
	info:    ProgramInfo,

	// Shutdown (atomic for cross-thread visibility)
	stop:    bool,
}

compiler_worker_start :: proc(w: ^CompilerWorker, glow: ^GlowContext) {
	w.glow = glow
	w.stop = false
	w.pending = false

	w.thread = thread.create_and_start_with_data(w, compiler_worker_proc, context)
}

compiler_worker_stop :: proc(w: ^CompilerWorker) {
	if w.thread == nil {
		return
	}

	sync.atomic_store(&w.stop, true)
	sync.auto_reset_event_signal(&w.evt)

	thread.join(w.thread)
	thread.destroy(w.thread)
	w.thread = nil
}

compiler_worker_submit :: proc(w: ^CompilerWorker, info: ProgramInfo) {
	sync.lock(&w.mtx)
	w.info = info
	w.pending = true
	sync.unlock(&w.mtx)

	sync.auto_reset_event_signal(&w.evt)
}

compiler_worker_proc :: proc(raw: rawptr) {
	w := cast(^CompilerWorker)raw

	for {
		sync.auto_reset_event_wait(&w.evt)
		if sync.atomic_load(&w.stop) {
			break
		}
        
		info: ProgramInfo
		has_work := false
        
		sync.lock(&w.mtx)
		if w.pending {
            info = w.info
			w.pending = false
			has_work = true
		}
		sync.unlock(&w.mtx)
        
		if !has_work {
            continue
		}
        log.infof("Compiling shader: %s", info.path)
        time_start := time.now()

		// NOTE: clone_to_cstring allocates; free it.
		path_c := strings.clone_to_cstring(info.path)
		source_c := strings.clone_to_cstring(info.source)
		defer delete_cstring(path_c)
		defer delete_cstring(source_c)

		program := compile_program(path_c, source_c)

        elapsed := time.duration_milliseconds(time.diff(time_start, time.now()))
        log.infof("Compilation finished in %.2f milliseconds", elapsed)

		sync.lock(&w.glow.program_mtx)
		w.glow.program = program
		sync.unlock(&w.glow.program_mtx)

		sync.atomic_store(&w.glow.program_should_reload, true)
	}
}
