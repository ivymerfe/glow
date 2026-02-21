package glow

import "core:log"
import vk "vendor:vulkan"

GlowImage :: struct {
	extent: vk.Extent2D,
	format: vk.Format,
	image:  vk.Image,
	view:   vk.ImageView,
	mem:    vk.DeviceMemory,
	layout: vk.ImageLayout,
}

TARGET_FORMAT: vk.Format = .R32G32B32A32_SFLOAT

MAX_DESCRIPTOR_SETS :: 2
MAX_STORAGE_IMAGES :: 8

VS_FULLSCREEN_SPV: []u8 = #load("shaders/vs_fullscreen.spv")

ResourceManager :: struct {
	using vk_context: VulkanContext,
	target:           GlowImage,
	descriptor_pool:  vk.DescriptorPool,
	vs_fullscreen:    vk.ShaderModule,
}

create_resource_manager :: proc(
	res: ^ResourceManager,
	vkc: VulkanContext,
	target_width: u32,
	target_height: u32,
) {
	res.vk_context = vkc

	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_IMAGE,
		descriptorCount = MAX_STORAGE_IMAGES,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = MAX_DESCRIPTOR_SETS,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	vk_try(vk.CreateDescriptorPool(res.device, &pool_info, nil, &res.descriptor_pool))

	res.target = create_image(res, target_width, target_height)

	vs_loaded: bool
	res.vs_fullscreen, vs_loaded = load_shader_from_memory(res, VS_FULLSCREEN_SPV)
	if !vs_loaded {
		log.panic("Failed to load vertex shader")
	}
}

destroy_resource_manager :: proc(res: ^ResourceManager) {
    device := res.vk_context.device

    vk.DestroyDescriptorPool(device, res.descriptor_pool, nil)
    vk.DestroyShaderModule(device, res.vs_fullscreen, nil)

    destroy_image(res, &res.target)
}



create_image :: proc(vk_context: ^VulkanContext, width: u32, height: u32) -> GlowImage {
	extent := vk.Extent2D {
		width  = width,
		height = height,
	}
	img, mem := create_2d_image(
		vk_context,
		TARGET_FORMAT,
		extent.width,
		extent.height,
		{.COLOR_ATTACHMENT, .TRANSFER_SRC},
		.UNDEFINED,
	)
	view := create_image_view_2d(vk_context, img, TARGET_FORMAT, {.COLOR})
	return GlowImage {
		extent = extent,
		format = TARGET_FORMAT,
		image = img,
		view = view,
		mem = mem,
		layout = .UNDEFINED,
	}
}

destroy_image :: proc(ctx: ^VulkanContext, image: ^GlowImage) {
	if image.view != {} {
		vk.DestroyImageView(ctx.device, image.view, nil)
	}
	if image.image != {} {
		vk.DestroyImage(ctx.device, image.image, nil)
	}
	if image.mem != {} {
		vk.FreeMemory(ctx.device, image.mem, nil)
	}
}
