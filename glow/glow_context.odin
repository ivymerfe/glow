package glow

import vk "vendor:vulkan"

PushConstants :: struct {
	camera_pos:       [4]f32,
	camera_forward:   [4]f32,
	camera_right:     [4]f32,
	camera_up:        [4]f32,
	mouse_pos:        [2]f32,
	mouse_data:       [2]u32,
	keyboard_pressed: [4]u32,
	keyboard_down:    [4]u32,
	aspect_ratio:     f32,
	time:             f32,
	frame_index:      u32,
}

GlowContext :: struct {
	using vk_context: VulkanContext,
	res:              ^ResourceManager,
	pipeline:         vk.Pipeline,
	layout:           vk.PipelineLayout,
}

RenderInfo :: struct {
	width:     u32,
	height:    u32,
	constants: PushConstants,
}

create_context :: proc(ctx: ^GlowContext, res: ^ResourceManager, program: ^GlowProgram) {
	ctx.vk_context = res.vk_context
	ctx.res = res

	module: vk.ShaderModule
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = int(program.code->getBufferSize()),
		pCode    = auto_cast program.code->getBufferPointer(),
	}
	vk_try(vk.CreateShaderModule(ctx.device, &create_info, nil, &module))
	create_pipeline(ctx, module)
	vk.DestroyShaderModule(ctx.device, module, nil)
}

destroy_context :: proc(ctx: ^GlowContext) {
	if ctx.pipeline != {} {
		vk.DestroyPipeline(ctx.device, ctx.pipeline, nil)
	}
	if ctx.layout != {} {
		vk.DestroyPipelineLayout(ctx.device, ctx.layout, nil)
	}
}

draw_context :: proc(ctx: ^GlowContext, cmd: vk.CommandBuffer, render_info: ^RenderInfo) {
	target := &ctx.res.target

	src_stage := vk.PipelineStageFlags2.TOP_OF_PIPE
	src_access := vk.AccessFlags2{}
	if target.layout == .TRANSFER_SRC_OPTIMAL {
		src_stage = vk.PipelineStageFlags2.TRANSFER
		src_access = vk.AccessFlags2{.TRANSFER_READ}
	}
	transition_image_layout(
		cmd,
		target.image,
		target.layout,
		.COLOR_ATTACHMENT_OPTIMAL,
		src_access,
		{.COLOR_ATTACHMENT_WRITE},
		{src_stage},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.COLOR},
	)
	target.layout = .COLOR_ATTACHMENT_OPTIMAL

	color_attachment := vk.RenderingAttachmentInfo {
		sType       = .RENDERING_ATTACHMENT_INFO,
		imageView   = target.view,
		imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
		loadOp      = .DONT_CARE,
		storeOp     = .STORE,
	}
	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {
			offset = {0, 0},
			extent = vk.Extent2D{width = render_info.width, height = render_info.height},
		},
		layerCount = 1,
		colorAttachmentCount = 1,
		pColorAttachments = &color_attachment,
	}
	vk.CmdBeginRendering(cmd, &rendering_info)

	vk.CmdBindPipeline(cmd, .GRAPHICS, ctx.pipeline)

	width := render_info.width
	height := render_info.height
	viewport := vk.Viewport {
		x        = 0.0,
		y        = 0.0,
		width    = f32(width),
		height   = f32(height),
		minDepth = 0.0,
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(cmd, 0, 1, &viewport)

	scissor := vk.Rect2D {
		offset = vk.Offset2D{x = 0, y = 0},
		extent = vk.Extent2D{width = u32(width), height = u32(height)},
	}
	vk.CmdSetScissor(cmd, 0, 1, &scissor)

	vk.CmdPushConstants(
		cmd,
		ctx.layout,
		{.VERTEX, .FRAGMENT},
		0,
		size_of(PushConstants),
		&render_info.constants,
	)

	vk.CmdDraw(cmd, 3, 1, 0, 0)
	vk.CmdEndRendering(cmd)

	transition_image_layout(
		cmd,
		target.image,
		.COLOR_ATTACHMENT_OPTIMAL,
		.TRANSFER_SRC_OPTIMAL,
		{.COLOR_ATTACHMENT_WRITE},
		{.TRANSFER_READ},
		{.COLOR_ATTACHMENT_OUTPUT},
		{.TRANSFER},
		{.COLOR},
	)
	target.layout = .TRANSFER_SRC_OPTIMAL
}

@(private = "file")
create_pipeline :: proc(ctx: ^GlowContext, ps_module: vk.ShaderModule) {
	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(PushConstants)},
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
		setLayoutCount         = 0,
	}
	vk_try(vk.CreatePipelineLayout(ctx.device, &layout_info, nil, &ctx.layout))

	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}
	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}
	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}
	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}
	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth   = 1,
		cullMode    = {.BACK},
		frontFace   = .CLOCKWISE,
	}
	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		minSampleShading     = 1,
	}
	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
	}
	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}
	depth_stencil_state := vk.PipelineDepthStencilStateCreateInfo {
		sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable  = true,
		depthWriteEnable = true,
		depthCompareOp   = .LESS,
	}

	vertex_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = ctx.res.vs_fullscreen,
		pName  = "main",
	}
	pixel_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = ps_module,
		pName  = "main",
	}
	shader_stages := []vk.PipelineShaderStageCreateInfo{vertex_shader_info, pixel_shader_info}
	format: vk.Format = TARGET_FORMAT
	pipeline_rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &format,
		depthAttachmentFormat   = .D32_SFLOAT,
		stencilAttachmentFormat = .UNDEFINED,
	}
	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_info,
		stageCount          = 2,
		pStages             = raw_data(shader_stages),
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state,
		pDepthStencilState  = &depth_stencil_state,
		layout              = ctx.layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}
	vk_try(vk.CreateGraphicsPipelines(ctx.device, 0, 1, &pipeline_info, nil, &ctx.pipeline))
}
