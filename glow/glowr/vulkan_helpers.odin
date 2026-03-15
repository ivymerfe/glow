package glowr

import "core:log"
import os "core:os"
import vk "vendor:vulkan"

load_shader_from_file :: proc(vkc: ^VulkanContext, filename: string) -> (vk.ShaderModule, bool) {
	bytes, success := os.read_entire_file(filename)
	if !success {
		return vk.ShaderModule{}, false
	}
	return load_shader_from_memory(vkc, bytes)
}

load_shader_from_memory :: proc(vkc: ^VulkanContext, code: []u8) -> (vk.ShaderModule, bool) {
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = auto_cast raw_data(code),
	}
	module: vk.ShaderModule
	result := vk.CreateShaderModule(vkc.device, &create_info, nil, &module)
	if result != .SUCCESS {
		return vk.ShaderModule{}, false
	}
	return module, true
}

transition_image_layout :: proc(
	command_buffer: vk.CommandBuffer,
	image: vk.Image,
	old_layout, new_layout: vk.ImageLayout,
	src_stage_mask, dst_stage_mask: vk.PipelineStageFlags2,
	src_access_mask, dst_access_mask: vk.AccessFlags2,
	aspect_mask: vk.ImageAspectFlags,
) {
	barrier := vk.ImageMemoryBarrier2 {
		sType = .IMAGE_MEMORY_BARRIER_2,
		srcStageMask = src_stage_mask,
		srcAccessMask = src_access_mask,
		dstStageMask = dst_stage_mask,
		dstAccessMask = dst_access_mask,
		oldLayout = old_layout,
		newLayout = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image = image,
		subresourceRange = {aspectMask = aspect_mask, levelCount = 1, layerCount = 1},
	}
	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
	}
	vk.CmdPipelineBarrier2(command_buffer, &dependency_info)
}

try_allocate :: proc(
	vkc: ^VulkanContext,
	mem_requirements: vk.MemoryRequirements,
	props: vk.MemoryPropertyFlags,
) -> (
	memory: vk.DeviceMemory,
) {
	type_filter := mem_requirements.memoryTypeBits
	for i in 0 ..< vkc.mem_props.memoryTypeCount {
		if bool(type_filter & (1 << i)) && props <= vkc.mem_props.memoryTypes[i].propertyFlags {
			allocate_info := vk.MemoryAllocateInfo {
				sType           = .MEMORY_ALLOCATE_INFO,
				allocationSize  = mem_requirements.size,
				memoryTypeIndex = i,
			}
			vk_try(vk.AllocateMemory(vkc.device, &allocate_info, nil, &memory))
			return
		}
	}
	log.panic("Failed to find memory type")
}

create_image_2d :: proc(
	vkc: ^VulkanContext,
	format: vk.Format,
	width, height: u32,
	usage: vk.ImageUsageFlags,
	initialLayout: vk.ImageLayout,
) -> (
	image: vk.Image,
	mem: vk.DeviceMemory,
) {
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		format = format,
		extent = {width = width, height = height, depth = 1},
		mipLevels = 1,
		arrayLayers = 1,
		samples = {._1},
		tiling = .OPTIMAL,
		usage = usage,
		initialLayout = initialLayout,
	}
	vk_try(vk.CreateImage(vkc.device, &image_info, nil, &image))
	mem_req: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(vkc.device, image, &mem_req)
	mem = try_allocate(vkc, mem_req, {.DEVICE_LOCAL})
	vk_try(vk.BindImageMemory(vkc.device, image, mem, 0))
	return
}

create_image_view_2d :: proc(
	vkc: ^VulkanContext,
	image: vk.Image,
	format: vk.Format,
	aspect: vk.ImageAspectFlags,
) -> (
	view: vk.ImageView,
) {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = .D2,
		format = format,
		subresourceRange = {aspectMask = aspect, levelCount = 1, layerCount = 1},
	}
	vk_try(vk.CreateImageView(vkc.device, &create_info, nil, &view))
	return
}
