package glow

import "../slang"
import "core:log"
import "core:os/os2"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:time"

CompilationTarget :: enum u8 {
	SlangModule,
	GlslSource,
}

CompilerPayload :: struct {
	target:   CompilationTarget,
	path:     string,
	source:   string,
	dst_path: string,
}


run_compiler_thread :: proc(
	target: CompilationTarget,
	path: string,
	source: string,
	dst_path: string,
) {
	payload := new(CompilerPayload)
	payload.target = target
	payload.path = path
	payload.source = source
	payload.dst_path = dst_path
	thread.create_and_start_with_data(payload, compiler_proc, context, .Normal, true)
}

compiler_proc :: proc(raw: rawptr) {
	payload := cast(^CompilerPayload)raw
	defer free(payload)

	target := payload.target
	path := payload.path
	source := payload.source
	dst_path := payload.dst_path

	compilation_start := time.now()
	switch target {
	case .SlangModule:
		session_desc := slang.SessionDesc {
			structureSize = size_of(slang.SessionDesc),
		}
		session: ^slang.ISession
		result := g_slang->createSession(session_desc, &session)
		if result != slang.OK {
			log.errorf("%v[%s] failed to create session: %d", target, path, result)
			return
		}
		defer session->release()

		path_c := strings.clone_to_cstring(path)
		source_c := strings.clone_to_cstring(source)
		defer delete_cstring(path_c)
		defer delete_cstring(source_c)
		diagnostics: ^slang.IBlob
		module := session->loadModuleFromSourceString("shader", path_c, source_c, &diagnostics)
		if module == nil {
			buffer := slice.bytes_from_ptr(
				diagnostics->getBufferPointer(),
				int(diagnostics->getBufferSize()),
			)
			log.errorf("%v[%s] failed: %s", target, path, buffer)
			return
		}
		dst_c := strings.clone_to_cstring(dst_path)
		defer delete_cstring(dst_c)
		result = module->writeToFile(dst_c)
		if result != slang.OK {
			log.errorf("%v[%s] failed to write file %s: %d", target, path, dst_path, result)
			return
		}
		compile_time := time.duration_milliseconds(time.diff(compilation_start, time.now()))
		log.infof("%v[%s] compiled in %.2f ms", target, path, compile_time)

	case .GlslSource:
		target_desc := slang.TargetDesc {
			structureSize     = size_of(slang.TargetDesc),
			format            = .GLSL,
			profile           = g_slang->findProfile("glsl_460"),
			lineDirectiveMode = .NONE,
		}
		session_desc := slang.SessionDesc {
			structureSize            = size_of(slang.SessionDesc),
			targets                  = &target_desc,
			targetCount              = 1,
			compilerOptionEntries    = nil,
			compilerOptionEntryCount = 0,
		}
		session: ^slang.ISession
		result := g_slang->createSession(session_desc, &session)
		if result != slang.OK {
			log.errorf("%v[%s] failed to create session: %d", target, path, result)
			return
		}
		defer session->release()

		path_c := strings.clone_to_cstring(path)
		source_c := strings.clone_to_cstring(source)
		defer delete_cstring(path_c)
		defer delete_cstring(source_c)
		diagnostics: ^slang.IBlob
		module := session->loadModuleFromSourceString("shader", path_c, source_c, &diagnostics)
		if module == nil {
			buffer := slice.bytes_from_ptr(
				diagnostics->getBufferPointer(),
				int(diagnostics->getBufferSize()),
			)
			log.errorf("%v[%s] failed: %s", target, path, buffer)
			return
		}
		target_code: ^slang.IBlob
		result = module->getTargetCode(0, &target_code, &diagnostics)
		if result != slang.OK {
			buffer := slice.bytes_from_ptr(
				diagnostics->getBufferPointer(),
				int(diagnostics->getBufferSize()),
			)
			log.errorf("%v[%s] failed: %s", target, path, buffer)
			return
		}
		defer target_code->release()

		buffer := slice.bytes_from_ptr(
			target_code->getBufferPointer(),
			int(target_code->getBufferSize()),
		)
		err := os2.write_entire_file(dst_path, buffer)
		if err != os2.General_Error.None {
			log.errorf("%v[%s] failed to write file %s: %v", target, path, dst_path, err)
			return
		}
		compile_time := time.duration_milliseconds(time.diff(compilation_start, time.now()))
		log.infof("%v[%s] compiled in %.2f ms", target, path, compile_time)
	}
}

