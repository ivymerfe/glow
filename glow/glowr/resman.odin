package glowr

import "core:log"
import vk "vendor:vulkan"

TARGET_FORMAT: vk.Format = .R32G32B32A32_SFLOAT
VS_FULLSCREEN_SPV: []u8 = #load("shaders/vs_fullscreen.spv")

GlowImage :: struct {
	extent:            vk.Extent2D,
	format:            vk.Format,
	image:             vk.Image,
	view:              vk.ImageView,
	mem:               vk.DeviceMemory,
	layout:            vk.ImageLayout,
	src_stage:         vk.PipelineStageFlags2,
	src_access:        vk.AccessFlags2,
	pass_width:        uint,
	pass_height:       uint,
	allocated:         bool,
	in_descriptor_set: bool,
}

ResourceManager :: struct {
	using vk_context:  VulkanContext,
	desc_count:        uint,
	images:            []GlowImage,
	image_width:       uint,
	image_height:      uint,
	vs_fullscreen:     vk.ShaderModule,
	descriptor_pool:   vk.DescriptorPool,
	desc_set_layout:   vk.DescriptorSetLayout,
	desc_set:          vk.DescriptorSet,
	pipeline_layout:   vk.PipelineLayout,
	descriptors_dirty: bool,
}

create_resource_manager :: proc(
	res: ^ResourceManager,
	vkc: VulkanContext,
	image_width: uint,
	image_height: uint,
	desc_count: uint,
) {
	res.vk_context = vkc
	res.image_width = image_width
	res.image_height = image_height

	vs_loaded: bool
	res.vs_fullscreen, vs_loaded = load_shader_from_memory(res, VS_FULLSCREEN_SPV)
	if !vs_loaded {
		log.panic("Failed to load vertex shader")
	}

	res.desc_count = desc_count
	pool_size := vk.DescriptorPoolSize {
		type            = .STORAGE_IMAGE,
		descriptorCount = u32(desc_count),
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
	res.images = make([]GlowImage, desc_count)
	res.descriptors_dirty = false
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
	delete(res.images)
}

request_images :: proc(res: ^ResourceManager, base: uint, count: uint) {
	created_any := false
	for i in 0 ..< count {
		if !res.images[base + i].allocated {
			create_image(&res.vk_context, res.image_width, res.image_height, &res.images[base + i])
			created_any = true
		}
	}
	if created_any {
		res.descriptors_dirty = true
	}
}

free_images :: proc(res: ^ResourceManager, base: int, count: int) {
	for i in 0 ..< count {
		if res.images[base + i].allocated {
			destroy_image(&res.vk_context, &res.images[base + i])
		}
	}
}

get_image :: proc(res: ^ResourceManager, idx: uint, location := #caller_location) -> ^GlowImage {
	if idx >= len(res.images) {
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

create_image :: proc(vk_context: ^VulkanContext, width: uint, height: uint, image: ^GlowImage) {
	image.format = TARGET_FORMAT
	image.extent = vk.Extent2D {
		width  = u32(width),
		height = u32(height),
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
	image.in_descriptor_set = false
	image.allocated = false
}

prepare_resources :: proc(res: ^ResourceManager) {
	if !res.descriptors_dirty {
		return
	}
	pending: u32 = 0
	for &img, i in res.images {
		if img.allocated && !img.in_descriptor_set {
			pending += 1
		}
	}
	if pending == 0 {
		res.descriptors_dirty = false
		return
	}
	infos := make([]vk.DescriptorImageInfo, pending, context.temp_allocator)
	writes := make([]vk.WriteDescriptorSet, pending, context.temp_allocator)
	idx: u32 = 0
	for &img, i in res.images {
		if !img.allocated || img.in_descriptor_set {
			continue
		}

		infos[idx] = vk.DescriptorImageInfo {
			imageView   = img.view,
			imageLayout = .GENERAL,
		}
		writes[idx] = vk.WriteDescriptorSet {
			sType           = .WRITE_DESCRIPTOR_SET,
			dstSet          = res.desc_set,
			dstBinding      = 0,
			dstArrayElement = u32(i),
			descriptorCount = 1,
			descriptorType  = .STORAGE_IMAGE,
			pImageInfo      = &infos[idx],
		}

		img.in_descriptor_set = true
		idx += 1
	}

	vk.UpdateDescriptorSets(res.device, idx, &writes[0], 0, nil)
	res.descriptors_dirty = false
}

@(private = "file")
create_descriptor_set :: proc(res: ^ResourceManager) {
	binding := vk.DescriptorSetLayoutBinding {
		binding            = 0,
		descriptorType     = .STORAGE_IMAGE,
		descriptorCount    = u32(res.desc_count),
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
