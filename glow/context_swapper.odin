package glow

import "core:sync"

ContextSwapper :: struct {
	current:     GlowContext,
	next:        GlowContext,
	swap_mutex:  sync.Mutex,
	has_current: bool,
	should_swap: bool,
	ready:       bool,
}

swapper_set_next :: proc(swapper: ^ContextSwapper, ctx: GlowContext) {
	sync.lock(&swapper.swap_mutex)
	if swapper.should_swap {
		destroy_context(&swapper.next)
	}
	swapper.next = ctx
	sync.unlock(&swapper.swap_mutex)
	sync.atomic_store(&swapper.should_swap, true)
	sync.atomic_store(&swapper.ready, true)
}

swapper_get_current :: proc(swapper: ^ContextSwapper) -> ^GlowContext {
	if sync.atomic_load(&swapper.should_swap) {
		sync.lock(&swapper.swap_mutex)
		if swapper.has_current {
			destroy_context(&swapper.current)
		}
		swapper.current = swapper.next
		swapper.should_swap = false
		swapper.has_current = true
		sync.unlock(&swapper.swap_mutex)
	}
	if !swapper.has_current {
		return nil
	}
	current := &swapper.current
	return current
}
