package glowr

import "core:log"
import vk "vendor:vulkan"

GlowImage :: struct {
	extent:     vk.Extent2D,
	format:     vk.Format,
	image:      vk.Image,
	view:       vk.ImageView,
	mem:        vk.DeviceMemory,
	layout:     vk.ImageLayout,
	src_stage:  vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	used:       int,
}

TARGET_FORMAT: vk.Format = .R32G32B32A32_SFLOAT

MAX_DESCRIPTOR_SETS :: 8
MAX_STORAGE_IMAGES :: 8

VS_FULLSCREEN_SPV: []u8 = #load("shaders/vs_fullscreen.spv")

ResourceManager :: struct {
	using vk_context: VulkanContext,
	images:           [dynamic]GlowImage,
	descriptor_pool:  vk.DescriptorPool,
	vs_fullscreen:    vk.ShaderModule,
	image_width:      u32,
	image_height:     u32,
}

create_resource_manager :: proc(
	res: ^ResourceManager,
	vkc: VulkanContext,
	image_width: u32,
	image_height: u32,
) {
	res.vk_context = vkc
	res.image_width = image_width
	res.image_height = image_height

	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_IMAGE,
		descriptorCount = MAX_STORAGE_IMAGES * MAX_DESCRIPTOR_SETS,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = MAX_DESCRIPTOR_SETS,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	vk_try(vk.CreateDescriptorPool(res.device, &pool_info, nil, &res.descriptor_pool))

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

	for &image in res.images {
		destroy_image(&res.vk_context, &image)
	}
}

acquire_image :: proc(res: ^ResourceManager) -> ^GlowImage {
	for image, i in res.images {
		if image.used == 0 {
			res.images[i].used = 1
			return &res.images[i]
		}
	}
	new_image := create_image(&res.vk_context, res.image_width, res.image_height)
	new_image.used = 1
	append(&res.images, new_image)
	return &res.images[len(res.images) - 1]
}

release_image :: proc(res: ^ResourceManager, image: ^GlowImage) {
	image.used = 0
}

transition_image :: proc(
	cmd: vk.CommandBuffer,
	image: ^GlowImage,
	new_layout: vk.ImageLayout,
	new_stage: vk.PipelineStageFlags2,
	new_access: vk.AccessFlags2,
) {
	transition_image_layout(
		cmd,
		image.image,
		image.layout,
		new_layout,
		image.src_stage,
		new_stage,
		image.src_access,
		new_access,
		{.COLOR},
	)
	image.layout = new_layout
	image.src_stage = new_stage
	image.src_access = new_access
}

create_image :: proc(vk_context: ^VulkanContext, width: u32, height: u32) -> GlowImage {
	extent := vk.Extent2D {
		width  = width,
		height = height,
	}
	img, mem := create_image_2d(
		vk_context,
		TARGET_FORMAT,
		extent.width,
		extent.height,
		{.COLOR_ATTACHMENT, .TRANSFER_SRC, .STORAGE},
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
		src_stage = {vk.PipelineStageFlags2.TOP_OF_PIPE},
		src_access = {},
		used = 0,
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
