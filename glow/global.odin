package glow

import "base:runtime"
import "core:log"
import slang "odin_slang"
import vk "vendor:vulkan"

SWAPCHAIN_WIDTH :: 1920
SWAPCHAIN_HEIGHT :: 1080
TARGET_WIDTH :: 1920
TARGET_HEIGHT :: 1080

GlobalContext :: struct {
	app:      runtime.Context,
	vkc:      VulkanContext,
	instance: vk.Instance,
	slang:    ^slang.IGlobalSession,
	fences:   [dynamic]vk.Fence,
}

g_ctx: GlobalContext
