package glow

import "core:log"
import "core:slice"
import "core:time"

import slang "odin_slang"


GlowCompiler :: struct {
	global_session: ^slang.IGlobalSession,
	session:        ^slang.ISession,
}

GlowProgram :: struct {
	code: ^slang.IBlob,
}

slang_check :: proc(result: slang.Result, loc := #caller_location) {
	if result != slang.OK {
		log.panicf("Slang error: %d", int(result), loc)
	}
}

diagnostics_check :: proc(diagnostics: ^slang.IBlob, loc := #caller_location) {
	if diagnostics != nil {
		buffer := slice.bytes_from_ptr(
			diagnostics->getBufferPointer(),
			int(diagnostics->getBufferSize()),
		)
		log.errorf("Slang: %s", string(buffer), loc)
	}
}

create_glow_compiler :: proc() -> GlowCompiler {
	comp: GlowCompiler

	slang_check(slang.createGlobalSession(slang.API_VERSION, &comp.global_session))
	target_desc := slang.TargetDesc {
		structureSize = size_of(slang.TargetDesc),
		format        = .SPIRV,
		flags         = {.GENERATE_SPIRV_DIRECTLY},
		profile       = comp.global_session->findProfile("sm_6_0"),
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

	slang_check(comp.global_session->createSession(session_desc, &comp.session))

	return comp
}

compile_program :: proc(
	comp: ^GlowCompiler,
	path: cstring,
	source: cstring,
) -> (
	program: GlowProgram,
) {
	diagnostics: ^slang.IBlob
	slang_module := comp.session->loadModuleFromSourceString("shader", path, source, &diagnostics)
	diagnostics_check(diagnostics)

	if slang_module == nil {
		return
	}

	fragment_entry: ^slang.IEntryPoint
	slang_module->findEntryPointByName("main", &fragment_entry)

	if fragment_entry == nil {
		log.error("Failed to find fragment entry point")
		return
	}
	components: [2]^slang.IComponentType = {slang_module, fragment_entry}

	composed_program: ^slang.IComponentType
	slang_check(
		comp.session->createCompositeComponentType(
			&components[0],
			len(components),
			&composed_program,
			&diagnostics,
		),
	)
	diagnostics_check(diagnostics)
	if composed_program == nil {
		log.error("Failed to create composed program")
		return
	}

	linked_program: ^slang.IComponentType
	slang_check(composed_program->link(&linked_program, &diagnostics))
	diagnostics_check(diagnostics)

	target_code: ^slang.IBlob
	slang_check(linked_program->getTargetCode(0, &target_code, &diagnostics))
	diagnostics_check(diagnostics)
	if target_code == nil {
		return
	}
	program.code = target_code
	return
}

destroy_glow_compiler :: proc(comp: ^GlowCompiler) {
	comp.session->release()
	comp.global_session->release()
}
