package rend

import "core:log"
import vk "vendor:vulkan"

Swapchain :: struct {
	h:           vk.SwapchainKHR,
	extent:      vk.Extent2D,
	image_count: u32,
	images:      []vk.Image,
	image_views: []vk.ImageView,
}

Renderer :: struct {
	using vk_context:           VulkanContext,
	surface:                    vk.SurfaceKHR,
	surface_format:             vk.SurfaceFormatKHR,
	present_mode:               vk.PresentModeKHR,
	swapchain:                  Swapchain,
	swapchain_width:            uint,
	swapchain_height:           uint,
	image_available_semaphore:  vk.Semaphore,
	render_finished_semaphores: []vk.Semaphore,
	cmd_pool:                   vk.CommandPool,
	cmd_buffer:                 vk.CommandBuffer,
	render_fence:               vk.Fence,
	res:                        ^ResourceManager,
}

PushConstants :: struct {
	width:       f32,
	height:      f32,
	mouse_x:     f32,
	mouse_y:     f32,
	input:       [4]u32,
	position:    [3]f32,
	time:        f32,
	forward:     [3]f32,
	frame_index: u32,
	right:       [3]f32,
	pool_index:  u32,
	up:          [3]f32,
	start_index: u32,
	prev_index:  u32,
	image_count: u32,
}

RenderInfo :: struct {
	dst_width:  u32,
	dst_height: u32,
	constants:  PushConstants,
}

create_renderer :: proc(
	vkc: VulkanContext,
	res: ^ResourceManager,
	surface: vk.SurfaceKHR,
	swapchain_width: uint,
	swapchain_height: uint,
) -> Renderer {
	ren: Renderer
	ren.vk_context = vkc
	ren.res = res
	ren.surface = surface

	ren.swapchain_width = swapchain_width
	ren.swapchain_height = swapchain_height
	get_surface_capabilities(&ren)
	create_swapchain(&ren, &ren.swapchain, nil)

	cmd_pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = ren.graphics_queue_idx,
	}
	vk_try(vk.CreateCommandPool(ren.device, &cmd_pool_info, nil, &ren.cmd_pool))

	cmd_buffer_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		level              = .PRIMARY,
		commandPool        = ren.cmd_pool,
		commandBufferCount = 1,
	}
	vk_try(vk.AllocateCommandBuffers(ren.device, &cmd_buffer_info, &ren.cmd_buffer))

	ren.render_finished_semaphores = make([]vk.Semaphore, ren.swapchain.image_count)
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}

	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	vk_try(vk.CreateFence(ren.device, &fence_info, nil, &ren.render_fence))

	vk_try(vk.CreateSemaphore(ren.device, &sem_info, nil, &ren.image_available_semaphore))
	for &sem in ren.render_finished_semaphores {
		vk_try(vk.CreateSemaphore(ren.device, &sem_info, nil, &sem))
	}

	return ren
}

destroy_renderer :: proc(ren: ^Renderer) {
	destroy_swapchain(ren, &ren.swapchain)

	vk.DestroySurfaceKHR(ren.instance, ren.surface, nil)

	vk.DestroySemaphore(ren.device, ren.image_available_semaphore, nil)
	vk.DestroyFence(ren.device, ren.render_fence, nil)

	for sem in ren.render_finished_semaphores {
		vk.DestroySemaphore(ren.device, sem, nil)
	}
	delete(ren.render_finished_semaphores)
	vk.DestroyCommandPool(ren.device, ren.cmd_pool, nil)
}

wait_renderer :: proc(ren: ^Renderer) {
	vk_try(vk.WaitForFences(ren.device, 1, &ren.render_fence, true, max(u64)))
	vk_try(vk.QueueWaitIdle(ren.present_queue))
}

resize_swapchain :: proc(ren: ^Renderer, new_width: uint, new_height: uint) {
	wait_renderer(ren)
	ren.swapchain_width = new_width
	ren.swapchain_height = new_height
	recreate_swapchain(ren)
}

is_renderer_ready :: proc(ren: ^Renderer) -> bool {
	fence_status := vk.GetFenceStatus(ren.device, ren.render_fence)
	return fence_status == .SUCCESS
}

render :: proc(ren: ^Renderer, render_info: ^RenderInfo, program: ^Program) -> bool {
	swapchain := ren.swapchain

	sem_image_available := ren.image_available_semaphore
	image_index: u32
	acquire_result := vk.AcquireNextImageKHR(
		ren.device,
		swapchain.h,
		max(u64), // less cpu
		sem_image_available,
		{},
		&image_index,
	)
	#partial switch acquire_result {
	case .TIMEOUT:
		return false
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain(ren)
		return false
	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("vulkan: acquire next image failure: %v", acquire_result)
	}

	swapchain_image := swapchain.images[image_index]

	cmd := ren.cmd_buffer
	vk.ResetCommandBuffer(cmd, {})
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(cmd, &begin_info)

	scissor := vk.Rect2D {
		offset = vk.Offset2D{x = 0, y = 0},
		extent = vk.Extent2D{width = u32(ren.swapchain_width), height = u32(ren.swapchain_height)},
	}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	vk.CmdBindDescriptorSets(
		cmd,
		.GRAPHICS,
		ren.res.pipeline_layout,
		0,
		1,
		&ren.res.desc_set,
		0,
		nil,
	)

	draw_program(program, cmd, render_info)
	output := get_program_output(program)
	if output == nil {
		log.panic("no program output")
	}

	transition_image(cmd, output, .TRANSFER_SRC_OPTIMAL, {.TRANSFER}, {.TRANSFER_READ})

	transition_image_layout(
		cmd,
		swapchain_image,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.BOTTOM_OF_PIPE},
		{.TRANSFER},
		{},
		{.TRANSFER_WRITE},
		{.COLOR},
	)
	copy_region := vk.ImageBlit {
		srcSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		srcOffsets = [2]vk.Offset3D {
			{0, 0, 0},
			{i32(output.pass_width), i32(output.pass_height), 1},
		},
		dstSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		dstOffsets = [2]vk.Offset3D {
			{0, 0, 0},
			{
				i32(min(swapchain.extent.width, render_info.dst_width)),
				i32(min(swapchain.extent.height, render_info.dst_height)),
				1,
			},
		},
	}
	vk.CmdBlitImage(
		cmd,
		output.image,
		.TRANSFER_SRC_OPTIMAL,
		swapchain_image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&copy_region,
		.LINEAR,
	)
	transition_image(cmd, output, .GENERAL, {.FRAGMENT_SHADER}, {.SHADER_READ})

	transition_image_layout(
		cmd,
		swapchain_image,
		.TRANSFER_DST_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.TRANSFER},
		{.BOTTOM_OF_PIPE},
		{.TRANSFER_WRITE},
		{},
		{.COLOR},
	)
	vk.EndCommandBuffer(cmd)

	sem_render_finished := ren.render_finished_semaphores[image_index]
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &sem_image_available,
		pWaitDstStageMask    = &vk.PipelineStageFlags{.TRANSFER},
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &sem_render_finished,
	}
	vk_try(vk.ResetFences(ren.device, 1, &ren.render_fence))
	vk_try(vk.QueueSubmit(ren.graphics_queue, 1, &submit_info, ren.render_fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &sem_render_finished,
		swapchainCount     = 1,
		pSwapchains        = &swapchain.h,
		pImageIndices      = &image_index,
	}
	present_result := vk.QueuePresentKHR(ren.present_queue, &present_info)
	switch {
	case present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR:
		recreate_swapchain(ren)
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}
	return true
}

recreate_swapchain :: proc(ren: ^Renderer) {
	new_swapchain: Swapchain
	create_swapchain(ren, &new_swapchain, &ren.swapchain)
	destroy_swapchain(ren, &ren.swapchain)
	ren.swapchain = new_swapchain
}

@(private = "file")
get_surface_capabilities :: proc(ren: ^Renderer) {
	formats_count: u32
	vk_try(
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			ren.physical_device,
			ren.surface,
			&formats_count,
			nil,
		),
	)
	formats := make([]vk.SurfaceFormatKHR, formats_count, context.temp_allocator)
	vk_try(
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			ren.physical_device,
			ren.surface,
			&formats_count,
			raw_data(formats),
		),
	)
	present_mode_count: u32
	vk_try(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			ren.physical_device,
			ren.surface,
			&present_mode_count,
			nil,
		),
	)
	present_modes := make([]vk.PresentModeKHR, present_mode_count, context.temp_allocator)
	vk_try(
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			ren.physical_device,
			ren.surface,
			&present_mode_count,
			raw_data(present_modes),
		),
	)
	surface_format := choose_swapchain_surface_format(formats)
	present_mode := choose_swapchain_present_mode(present_modes)
	ren.surface_format = surface_format
	ren.present_mode = present_mode
}

@(private = "file")
create_swapchain :: proc(ren: ^Renderer, new_swapchain: ^Swapchain, old_swapchain: ^Swapchain) {
	capabilities: vk.SurfaceCapabilitiesKHR
	vk_try(
		vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
			ren.physical_device,
			ren.surface,
			&capabilities,
		),
	)
	if capabilities.currentExtent.width != max(u32) {
		new_swapchain.extent = capabilities.currentExtent
	} else {
		new_swapchain.extent.width = clamp(
			u32(ren.swapchain_width),
			capabilities.minImageExtent.width,
			capabilities.maxImageExtent.width,
		)
		new_swapchain.extent.height = clamp(
			u32(ren.swapchain_height),
			capabilities.minImageExtent.height,
			capabilities.maxImageExtent.height,
		)
	}

	image_count := capabilities.minImageCount + 1
	if capabilities.maxImageCount > 0 {
		image_count = min(image_count, capabilities.maxImageCount)
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ren.surface,
		minImageCount    = image_count,
		imageFormat      = ren.surface_format.format,
		imageColorSpace  = ren.surface_format.colorSpace,
		presentMode      = ren.present_mode,
		imageExtent      = new_swapchain.extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT, .TRANSFER_DST},
		preTransform     = capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		clipped          = true,
	}
	if old_swapchain != nil {
		create_info.oldSwapchain = old_swapchain.h
	}
	if ren.graphics_queue_idx != ren.present_queue_idx {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = raw_data(
			[]u32{ren.graphics_queue_idx, ren.present_queue_idx},
		)
	}
	vk_try(vk.CreateSwapchainKHR(ren.device, &create_info, nil, &new_swapchain.h))

	vk_try(vk.GetSwapchainImagesKHR(ren.device, new_swapchain.h, &image_count, nil))
	new_swapchain.image_count = image_count
	new_swapchain.images = make([]vk.Image, image_count)
	vk_try(
		vk.GetSwapchainImagesKHR(
			ren.device,
			new_swapchain.h,
			&image_count,
			raw_data(new_swapchain.images),
		),
	)

	new_swapchain.image_views = make([]vk.ImageView, image_count)
	for image, i in new_swapchain.images {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image,
			viewType = .D2,
			format = ren.surface_format.format,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}
		vk_try(vk.CreateImageView(ren.device, &create_info, nil, &new_swapchain.image_views[i]))
	}
}

@(private = "file")
destroy_swapchain :: proc(ren: ^Renderer, swapchain: ^Swapchain) {
	for image_view in swapchain.image_views {
		vk.DestroyImageView(ren.device, image_view, nil)
	}
	delete(swapchain.image_views)
	delete(swapchain.images)
	vk.DestroySwapchainKHR(ren.device, swapchain.h, nil)
}

@(private = "file")
choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}
	return formats[0]
}

@(private = "file")
choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// for mode in modes {
	// 	if mode == .MAILBOX {
	// 		return .MAILBOX
	// 	}
	// }
	return .FIFO
}

