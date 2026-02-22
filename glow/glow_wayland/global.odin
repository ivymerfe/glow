package glow_wayland

import glow "../glow_base"
import slang "../odin_slang"
import "base:runtime"
import "gwin"
import vk "vendor:vulkan"

SWAPCHAIN_WIDTH :: 1920
SWAPCHAIN_HEIGHT :: 1080
TARGET_WIDTH :: 1920
TARGET_HEIGHT :: 1080

GlobalContext :: struct {
	app:      runtime.Context,
	vkc:      glow.VulkanContext,
	instance: vk.Instance,
	slang:    ^slang.IGlobalSession,
	res:      glow.ResourceManager,
	wayland:  gwin.WaylandContext,
	compiler: CompilerThread,
	renderer: RenderThread,
}

g_ctx: GlobalContext
