package glowr

import "core:log"
import "core:slice"

import "../slang"

slang_check :: proc(result: slang.Result, loc := #caller_location) {
	if result != slang.OK {
		log.panicf("Slang error: %d", int(result), loc)
	}
}

diagnostics_check :: proc(path: string, diagnostics: ^slang.IBlob) {
	if diagnostics != nil {
		buffer := slice.bytes_from_ptr(
			diagnostics->getBufferPointer(),
			int(diagnostics->getBufferSize()),
		)
		log.debugf("%s", buffer)
	}
}

create_slang_session :: proc(global: ^slang.IGlobalSession) -> (session: ^slang.ISession) {
	target_desc := slang.TargetDesc {
		structureSize = size_of(slang.TargetDesc),
		format        = .SPIRV,
		flags         = {.GENERATE_SPIRV_DIRECTLY},
		profile       = global->findProfile("sm_6_0"),
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
	slang_check(global->createSession(session_desc, &session))
	return
}
