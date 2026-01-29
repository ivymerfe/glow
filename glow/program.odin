package glow

import "core:log"
import "core:slice"

import slang "odin_slang"

GlowProgram :: struct {
	code: ^slang.IBlob,
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

compile_program :: proc(
	session: ^slang.ISession,
	path: cstring,
	source: cstring,
) -> (
	program: GlowProgram,
) {
	diagnostics: ^slang.IBlob
	slang_module := session->loadModuleFromSourceString("shader", path, source, &diagnostics)
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
		session->createCompositeComponentType(
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
