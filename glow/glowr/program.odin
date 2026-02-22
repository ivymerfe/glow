package glowr

import "../slang"
import "core:log"
import "core:time"
import vk "vendor:vulkan"

Program :: struct {
	using vk_context: VulkanContext,
	res:              ^ResourceManager,
	pipeline:         vk.Pipeline,
	layout:           vk.PipelineLayout,
}

compile_program :: proc(
	prog: ^Program,
	res: ^ResourceManager,
	global: ^slang.IGlobalSession,
	path: cstring,
	source: cstring,
) -> (
	success: bool,
) {
	time_start := time.now()
	defer {
		elapsed := time.duration_milliseconds(time.diff(time_start, time.now()))
		log.debugf("[%s] -> %.2f ms", path, elapsed)
	}

	session := create_slang_session(global)
	defer session->release()

	diagnostics: ^slang.IBlob
	slang_module := session->loadModuleFromSourceString("shader", path, source, &diagnostics)
	diagnostics_check(path, diagnostics)
	if slang_module == nil {
		return
	}

	fragment_entry: ^slang.IEntryPoint
	slang_module->findEntryPointByName("main", &fragment_entry)
	if fragment_entry == nil {
		log.debugf("[%s] failed to find fragment entry point", path)
		return
	}
	components: [2]^slang.IComponentType = {slang_module, fragment_entry}

	composed_program: ^slang.IComponentType
	slang_check(
		session->createCompositeComponentType(
			&components[0],
			len(components),
			&composed_program,
			&diagnostics,
		),
	)
	diagnostics_check(path, diagnostics)
	if composed_program == nil {
		return
	}
	defer composed_program->release()

	linked_program: ^slang.IComponentType
	slang_check(composed_program->link(&linked_program, &diagnostics))
	diagnostics_check(path, diagnostics)
	if linked_program == nil {
		return
	}
	defer linked_program->release()

	target_code: ^slang.IBlob
	slang_check(linked_program->getTargetCode(0, &target_code, &diagnostics))
	diagnostics_check(path, diagnostics)
	if target_code == nil {
		return
	}
	defer target_code->release()

	prog.vk_context = res.vk_context
	prog.res = res
	module: vk.ShaderModule
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = int(target_code->getBufferSize()),
		pCode    = auto_cast target_code->getBufferPointer(),
	}
	vk_try(vk.CreateShaderModule(prog.device, &create_info, nil, &module))
	defer vk.DestroyShaderModule(prog.device, module, nil)

	create_pipeline(prog, module)
	success = true
	return
}

destroy_program :: proc(ctx: ^Program) {
	if ctx.pipeline != {} {
		vk.DestroyPipeline(ctx.device, ctx.pipeline, nil)
	}
	if ctx.layout != {} {
		vk.DestroyPipelineLayout(ctx.device, ctx.layout, nil)
	}
}

draw_program :: proc(prog: ^Program, cmd: vk.CommandBuffer, render_info: ^RenderInfo) {
	target := &prog.res.target

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

	vk.CmdBindPipeline(cmd, .GRAPHICS, prog.pipeline)

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
		prog.layout,
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
create_pipeline :: proc(prog: ^Program, ps_module: vk.ShaderModule) {
	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(PushConstants)},
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
		setLayoutCount         = 0,
	}
	vk_try(vk.CreatePipelineLayout(prog.device, &layout_info, nil, &prog.layout))

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
		module = prog.res.vs_fullscreen,
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
		layout              = prog.layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}
	vk_try(vk.CreateGraphicsPipelines(prog.device, 0, 1, &pipeline_info, nil, &prog.pipeline))
}
