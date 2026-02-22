package glow_base

import "core:sync"

ProgramBuffer :: struct {
	current:     GlowProgram,
	next:        GlowProgram,
	swap_mutex:  sync.Mutex,
	has_current: bool,
	should_swap: bool,
	ready:       bool,
}

program_buffer_set :: proc(swapper: ^ProgramBuffer, ctx: GlowProgram) {
	sync.lock(&swapper.swap_mutex)
	if swapper.should_swap {
		destroy_program(&swapper.next)
	}
	swapper.next = ctx
	sync.unlock(&swapper.swap_mutex)
	sync.atomic_store(&swapper.should_swap, true)
	sync.atomic_store(&swapper.ready, true)
}

program_buffer_get :: proc(swapper: ^ProgramBuffer) -> ^GlowProgram {
	if sync.atomic_load(&swapper.should_swap) {
		sync.lock(&swapper.swap_mutex)
		if swapper.has_current {
			destroy_program(&swapper.current)
		}
		swapper.current = swapper.next
		sync.unlock(&swapper.swap_mutex)
		sync.atomic_store(&swapper.should_swap, false)
		swapper.has_current = true
	}
	if !swapper.has_current {
		return nil
	}
	current := &swapper.current
	return current
}

