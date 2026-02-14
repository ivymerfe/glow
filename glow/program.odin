package glow

import "core:log"
import "core:slice"
import "core:time"

import slang "odin_slang"

GlowProgram :: struct {
	code: ^slang.IBlob,
}

ProgramInfo :: struct {
	version: u32,
	path:    string,
	source:  string,
}

slang_check :: proc(result: slang.Result, loc := #caller_location) {
	if result != slang.OK {
		log.panicf("Slang error: %d", int(result), loc)
	}
}

diagnostics_check :: proc(path: cstring, diagnostics: ^slang.IBlob, loc := #caller_location) {
	if diagnostics != nil {
		buffer := slice.bytes_from_ptr(
			diagnostics->getBufferPointer(),
			int(diagnostics->getBufferSize()),
		)
		log.debugf("[%s]: %s", path, string(buffer), loc)
	}
}

create_slang_session :: proc() -> (session: ^slang.ISession) {
	target_desc := slang.TargetDesc {
		structureSize = size_of(slang.TargetDesc),
		format        = .SPIRV,
		flags         = {.GENERATE_SPIRV_DIRECTLY},
		profile       = g_ctx.slang->findProfile("sm_6_0"),
	}

	compiler_option_entries := [?]slang.CompilerOptionEntry {
		{name = .VulkanUseEntryPointName, value = {intValue0 = 1}},
	}
	session_desc := slang.SessionDesc {
		structureSize            = size_of(slang.SessionDesc),
		targets                  = &target_desc,
		targetCount              = 1,
		compilerOptionEntries    = &compiler_option_entries[0],
		compilerOptionEntryCount = 1,
	}
	slang_check(g_ctx.slang->createSession(session_desc, &session))
	return
}

compile_program :: proc(path: cstring, source: cstring) -> (program: GlowProgram, success: bool) {
	time_start := time.now()
	defer {
		elapsed := time.duration_milliseconds(time.diff(time_start, time.now()))
		log.debugf("[%s] -> %.2f ms", path, elapsed)
	}

	session := create_slang_session()
	defer session->release()

	diagnostics: ^slang.IBlob
	slang_module := session->loadModuleFromSourceString("shader", path, source, &diagnostics)
	diagnostics_check(path, diagnostics)
	if slang_module == nil {
		return
	}
	fragment_entry: ^slang.IEntryPoint
	slang_module->findEntryPointByName("main", &fragment_entry)
	if fragment_entry == nil {
		log.debugf("[%s] failed to find fragment entry point", path)
		return
	}
	components: [2]^slang.IComponentType = {slang_module, fragment_entry}

	composed_program: ^slang.IComponentType
	slang_check(
		session->createCompositeComponentType(
			&components[0],
			len(components),
			&composed_program,
			&diagnostics,
		),
	)
	diagnostics_check(path, diagnostics)
	if composed_program == nil {
		return
	}
	linked_program: ^slang.IComponentType
	slang_check(composed_program->link(&linked_program, &diagnostics))
	diagnostics_check(path, diagnostics)
	if linked_program == nil {
		return
	}
	target_code: ^slang.IBlob
	slang_check(linked_program->getTargetCode(0, &target_code, &diagnostics))
	diagnostics_check(path, diagnostics)
	if target_code == nil {
		return
	}
	program.code = target_code
	success = true
	return
}

free_program :: proc(program: ^GlowProgram) {
	if program.code != nil {
		program.code->release()
		program.code = nil
	}
}

