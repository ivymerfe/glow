package glowr

import "core:log"
import vk "vendor:vulkan"

MAX_IMAGES :: 1024
TARGET_FORMAT: vk.Format = .R32G32B32A32_SFLOAT
VS_FULLSCREEN_SPV: []u8 = #load("shaders/vs_fullscreen.spv")

GlowImage :: struct {
	extent:     vk.Extent2D,
	format:     vk.Format,
	image:      vk.Image,
	view:       vk.ImageView,
	mem:        vk.DeviceMemory,
	layout:     vk.ImageLayout,
	src_stage:  vk.PipelineStageFlags2,
	src_access: vk.AccessFlags2,
	allocated:  bool,
}

ResourceManager :: struct {
	using vk_context: VulkanContext,
	images:           [MAX_IMAGES]GlowImage,
	image_width:      u32,
	image_height:     u32,
	vs_fullscreen:    vk.ShaderModule,
	descriptor_pool:  vk.DescriptorPool,
	desc_set_layout:  vk.DescriptorSetLayout,
	desc_set:         vk.DescriptorSet,
	pipeline_layout:  vk.PipelineLayout,
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

	vs_loaded: bool
	res.vs_fullscreen, vs_loaded = load_shader_from_memory(res, VS_FULLSCREEN_SPV)
	if !vs_loaded {
		log.panic("Failed to load vertex shader")
	}

	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_IMAGE,
		descriptorCount = MAX_IMAGES,
	}
	pool_info := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.FREE_DESCRIPTOR_SET},
		maxSets       = 1,
		poolSizeCount = 1,
		pPoolSizes    = &pool_size,
	}
	vk_try(vk.CreateDescriptorPool(res.device, &pool_info, nil, &res.descriptor_pool))
	create_descriptor_set(res)
	create_pipeline_layout(res)
}

destroy_resource_manager :: proc(res: ^ResourceManager) {
	device := res.vk_context.device

	vk.DestroyPipelineLayout(device, res.pipeline_layout, nil)
	vk.DestroyDescriptorSetLayout(device, res.desc_set_layout, nil)
	vk.DestroyDescriptorPool(device, res.descriptor_pool, nil)
	vk.DestroyShaderModule(device, res.vs_fullscreen, nil)

	for &image in res.images {
		if image.allocated {
			destroy_image(&res.vk_context, &image)
		}
	}
}

request_images :: proc(res: ^ResourceManager, base: u32, count: u32) {
	for i in 0 ..< count {
		if res.images[base + i].image == {} {
			create_image(&res.vk_context, res.image_width, res.image_height, &res.images[base + i])
		}
	}
	write_image_descriptors(res, base, count)
}

free_images :: proc(res: ^ResourceManager, base: int, count: int) {
	for i in 0 ..< count {
		if res.images[base + i].allocated {
			destroy_image(&res.vk_context, &res.images[base + i])
		}
	}
}

get_image :: proc(res: ^ResourceManager, idx: u32, location := #caller_location) -> ^GlowImage {
	if idx >= MAX_IMAGES {
		log.panicf("get_image out of bounds: %d", idx, location)
	}
	img := &res.images[idx]
	if !img.allocated {
		log.panicf("get_image not allocated: %d", idx, location)
	}
	return img
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

create_image :: proc(vk_context: ^VulkanContext, width: u32, height: u32, image: ^GlowImage) {
	image.format = TARGET_FORMAT
	image.extent = vk.Extent2D {
		width  = width,
		height = height,
	}
	img, mem := create_image_2d(
		vk_context,
		TARGET_FORMAT,
		image.extent.width,
		image.extent.height,
		{.COLOR_ATTACHMENT, .TRANSFER_SRC, .STORAGE},
		.UNDEFINED,
	)
	image.image = img
	image.mem = mem
	image.view = create_image_view_2d(vk_context, img, TARGET_FORMAT, {.COLOR})
	image.layout = .UNDEFINED
	image.src_stage = {.TOP_OF_PIPE}
	image.src_access = {}
	image.allocated = true
}

destroy_image :: proc(ctx: ^VulkanContext, image: ^GlowImage) {
	if image.view != {} {
		vk.DestroyImageView(ctx.device, image.view, nil)
		image.view = {}
	}
	if image.image != {} {
		vk.DestroyImage(ctx.device, image.image, nil)
		image.image = {}
	}
	if image.mem != {} {
		vk.FreeMemory(ctx.device, image.mem, nil)
		image.mem = {}
	}
	image.allocated = false
}

@(private = "file")
write_image_descriptors :: proc(res: ^ResourceManager, base: u32, count: u32) {
	infos := make([]vk.DescriptorImageInfo, count, context.temp_allocator)
	for i in 0 ..< count {
		img := res.images[base + i]
		infos[i] = vk.DescriptorImageInfo {
			imageView   = img.view,
			imageLayout = .GENERAL,
		}
	}
	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = res.desc_set,
		dstBinding      = 0,
		dstArrayElement = u32(base),
		descriptorCount = u32(count),
		descriptorType  = .STORAGE_IMAGE,
		pImageInfo      = &infos[0],
	}
	vk.UpdateDescriptorSets(res.device, 1, &write, 0, nil)
}

@(private = "file")
create_descriptor_set :: proc(res: ^ResourceManager) {
	binding := vk.DescriptorSetLayoutBinding {
		binding            = 0,
		descriptorType     = .STORAGE_IMAGE,
		descriptorCount    = MAX_IMAGES,
		stageFlags         = {.FRAGMENT},
		pImmutableSamplers = nil,
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
		pNext        = &vk.DescriptorSetLayoutBindingFlagsCreateInfo {
			sType = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
			bindingCount = 1,
			pBindingFlags = &vk.DescriptorBindingFlags{.PARTIALLY_BOUND},
		},
	}
	vk_try(vk.CreateDescriptorSetLayout(res.device, &layout_info, nil, &res.desc_set_layout))

	layouts := [1]vk.DescriptorSetLayout{res.desc_set_layout}
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = res.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &layouts[0],
	}
	vk_try(vk.AllocateDescriptorSets(res.device, &alloc_info, &res.desc_set))
}

@(private = "file")
create_pipeline_layout :: proc(res: ^ResourceManager) {
	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(PushConstants)},
	}
	descriptor_layouts := []vk.DescriptorSetLayout{res.desc_set_layout}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
		setLayoutCount         = 1,
		pSetLayouts            = raw_data(descriptor_layouts),
	}
	vk_try(vk.CreatePipelineLayout(res.device, &layout_info, nil, &res.pipeline_layout))
}
