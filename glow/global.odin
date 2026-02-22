package glow

import "base:runtime"
import "glowr"
import "gwin"
import "slang"
import vk "vendor:vulkan"

SWAPCHAIN_WIDTH :: 1920
SWAPCHAIN_HEIGHT :: 1080
TARGET_WIDTH :: 1920
TARGET_HEIGHT :: 1080

GlobalContext :: struct {
	app:      runtime.Context,
	vkc:      glowr.VulkanContext,
	instance: vk.Instance,
	slang:    ^slang.IGlobalSession,
	res:      glowr.ResourceManager,
	wayland:  gwin.WaylandContext,
	compiler: CompilerThread,
	renderer: RenderThread,
}

g_ctx: GlobalContext
