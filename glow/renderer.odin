package glow

import "core:log"
import vk "vendor:vulkan"

Swapchain :: struct {
	h:           vk.SwapchainKHR,
	extent:      vk.Extent2D,
	image_count: u32,
	images:      []vk.Image,
	image_views: []vk.ImageView,
}

GlowRenderer :: struct {
	using vk_context:           VulkanContext,
	surface:                    vk.SurfaceKHR,
	surface_format:             vk.SurfaceFormatKHR,
	present_mode:               vk.PresentModeKHR,
	swapchain:                  Swapchain,
	swapchain_width:            int,
	swapchain_height:           int,
	image_available_semaphore:  vk.Semaphore,
	render_finished_semaphores: []vk.Semaphore,
	cmd_pool:                   vk.CommandPool,
	cmd_buffer:                 vk.CommandBuffer,
	render_fence:               vk.Fence,
}

create_renderer :: proc(
	vkc: VulkanContext,
	surface: vk.SurfaceKHR,
	swapchain_width: int,
	swapchain_height: int,
) -> GlowRenderer {
	ren: GlowRenderer
	ren.vk_context = vkc
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

destroy_renderer :: proc(ren: ^GlowRenderer) {
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

wait_renderer :: proc(ren: ^GlowRenderer) {
	vk_try(vk.WaitForFences(ren.device, 1, &ren.render_fence, true, max(u64)))
}

resize_swapchain :: proc(ren: ^GlowRenderer, new_width: int, new_height: int) {
	wait_renderer(ren)
	ren.swapchain_width = new_width
	ren.swapchain_height = new_height
	recreate_swapchain(ren)
}

render :: proc(ren: ^GlowRenderer, glow_context: ^GlowContext, render_info: ^RenderInfo) -> bool {
	fence_status := vk.GetFenceStatus(ren.device, ren.render_fence)
	if fence_status == .NOT_READY {
		return false
	}
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

	cmd_buffer := ren.cmd_buffer
	vk.ResetCommandBuffer(cmd_buffer, {})
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	vk.BeginCommandBuffer(cmd_buffer, &begin_info)

	draw_context(glow_context, cmd_buffer, render_info)

	transition_image_layout(
		cmd_buffer,
		swapchain_image,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{},
		{.TRANSFER_WRITE},
		{.BOTTOM_OF_PIPE},
		{.TRANSFER},
		{.COLOR},
	)
	copy_region := vk.ImageBlit {
		srcSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		srcOffsets = [2]vk.Offset3D {
			{0, 0, 0},
			{i32(render_info.width), i32(render_info.height), 1},
		},
		dstSubresource = {aspectMask = {.COLOR}, layerCount = 1},
		dstOffsets = [2]vk.Offset3D {
			{0, 0, 0},
			{i32(swapchain.extent.width), i32(swapchain.extent.height), 1},
		},
	}
	vk.CmdBlitImage(
		cmd_buffer,
		glow_context.target.image,
		.TRANSFER_SRC_OPTIMAL,
		swapchain_image,
		.TRANSFER_DST_OPTIMAL,
		1,
		&copy_region,
		.LINEAR,
	)
	transition_image_layout(
		cmd_buffer,
		swapchain_image,
		.TRANSFER_DST_OPTIMAL,
		.PRESENT_SRC_KHR,
		{.TRANSFER_WRITE},
		{},
		{.TRANSFER},
		{.BOTTOM_OF_PIPE},
		{.COLOR},
	)
	vk.EndCommandBuffer(cmd_buffer)

	sem_render_finished := ren.render_finished_semaphores[image_index]
	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &sem_image_available,
		pWaitDstStageMask    = &vk.PipelineStageFlags{.TRANSFER},
		commandBufferCount   = 1,
		pCommandBuffers      = &cmd_buffer,
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

recreate_swapchain :: proc(ren: ^GlowRenderer) {
	new_swapchain: Swapchain
	create_swapchain(ren, &new_swapchain, &ren.swapchain)
	destroy_swapchain(ren, &ren.swapchain)
	ren.swapchain = new_swapchain
}

@(private = "file")
get_surface_capabilities :: proc(ren: ^GlowRenderer) {
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
create_swapchain :: proc(
	ren: ^GlowRenderer,
	new_swapchain: ^Swapchain,
	old_swapchain: ^Swapchain,
) {
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
destroy_swapchain :: proc(ren: ^GlowRenderer, swapchain: ^Swapchain) {
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
