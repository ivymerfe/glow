package glowr

import "../slang"
import refl "../slang/reflection_wrapper"
import "core:log"
import "core:time"
import vk "vendor:vulkan"

ProgramPass :: struct {
	entry_name: cstring,
	pipeline:   vk.Pipeline,
}

Program :: struct {
	using vk_context:  VulkanContext,
	res:               ^ResourceManager,
	shader:            vk.ShaderModule,
	descriptor_layout: vk.DescriptorSetLayout,
	layout:            vk.PipelineLayout,
	descriptor_set:    vk.DescriptorSet,
	buffer_index:      int,
	passes:            [dynamic]ProgramPass,
	images:            [dynamic]^GlowImage,
	images_loaded:     bool,
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
	module := session->loadModuleFromSourceString("shader", path, source, &diagnostics)
	diagnostics_check(path, diagnostics)
	if module == nil {
		return
	}
	entry_count := module->getDefinedEntryPointCount()
	components := make([]^slang.IComponentType, entry_count + 1, context.temp_allocator)
	for i in 0 ..< entry_count {
		entry: ^slang.IEntryPoint
		slang_check(module->getDefinedEntryPoint(i, &entry))
		components[i] = entry
	}
	components[entry_count] = module

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

	program_layout := linked_program->getLayout(0, &diagnostics)
	diagnostics_check(path, diagnostics)
	layout_wrap := refl.init_program_layout(program_layout)

	entry_point_count := layout_wrap->getEntryPointCount()
	if entry_point_count == 0 {
		log.debugf("[%s] no entry points found", path)
		return
	}
	for i in 0 ..< entry_point_count {
		entry_layout := layout_wrap->getEntryPointByIndex(i)
		if entry_layout->getStage() == .FRAGMENT {
			entry_name := entry_layout->getNameOverride()
			if entry_name == nil {
				entry_name = entry_layout->getName()
			}
			entry: ^slang.IComponentType
			append(&prog.passes, ProgramPass{entry_name = entry_name})
		}
	}
	if len(prog.passes) == 0 {
		log.debugf("[%s] no fragment entry points found", path)
		return
	}
	target_code: ^slang.IBlob

	slang_check(linked_program->getTargetCode(0, &target_code, &diagnostics))
	diagnostics_check(path, diagnostics)
	if target_code == nil {
		return
	}
	defer target_code->release()

	prog.vk_context = res.vk_context
	prog.res = res
	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = int(target_code->getBufferSize()),
		pCode    = auto_cast target_code->getBufferPointer(),
	}
	vk_try(vk.CreateShaderModule(prog.device, &create_info, nil, &prog.shader))

	create_descriptor_set(prog, len(prog.passes) + 1)
	create_pipeline_layout(prog)
	for &pass in prog.passes {
		pass.pipeline = create_pipeline(prog, prog.shader, pass.entry_name)
	}
	load_program_images(prog)
	success = true
	return
}

destroy_program :: proc(ctx: ^Program) {
	for pass in ctx.passes {
		if pass.pipeline != {} {
			vk.DestroyPipeline(ctx.device, pass.pipeline, nil)
		}
	}
	delete(ctx.passes)

	if ctx.descriptor_set != {} {
		vk_try(vk.FreeDescriptorSets(ctx.device, ctx.res.descriptor_pool, 1, &ctx.descriptor_set))
	}
	ctx.descriptor_set = {}

	if ctx.images_loaded {
		for image in ctx.images {
			release_image(ctx.res, image)
		}
		delete(ctx.images)
		ctx.images_loaded = false
	}

	if ctx.layout != {} {
		vk.DestroyPipelineLayout(ctx.device, ctx.layout, nil)
	}
	if ctx.descriptor_layout != {} {
		vk.DestroyDescriptorSetLayout(ctx.device, ctx.descriptor_layout, nil)
	}
	if ctx.shader != {} {
		vk.DestroyShaderModule(ctx.device, ctx.shader, nil)
	}
}

load_program_images :: proc(prog: ^Program) {
	image_count := len(prog.passes) + 1
	for _ in 0 ..< image_count {
		append(&prog.images, acquire_image(prog.res))
	}
	update_descriptor_set(prog, prog.descriptor_set)
	prog.images_loaded = true
}

draw_program :: proc(prog: ^Program, cmd: vk.CommandBuffer, render_info: ^RenderInfo) {
	if len(prog.passes) == 0 {
		return
	}
	for image in prog.images {
		transition_image(cmd, image, .GENERAL, {.FRAGMENT_SHADER}, {.SHADER_READ})
	}
	source_idx := prog.buffer_index
	pass_constants := render_info.constants
	pass_constants.base_idx = u32((source_idx + 1) % len(prog.images))

	for pass in prog.passes {
		target_idx := (source_idx + 1) % len(prog.images)
		target := prog.images[target_idx]

		pass_constants.prev_idx = u32((source_idx + 2) % len(prog.images))

		transition_image(
			cmd,
			target,
			.COLOR_ATTACHMENT_OPTIMAL,
			{.COLOR_ATTACHMENT_OUTPUT},
			{.COLOR_ATTACHMENT_WRITE},
		)

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

		vk.CmdBindPipeline(cmd, .GRAPHICS, pass.pipeline)
		vk.CmdBindDescriptorSets(cmd, .GRAPHICS, prog.layout, 0, 1, &prog.descriptor_set, 0, nil)

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
			&pass_constants,
		)

		vk.CmdDraw(cmd, 3, 1, 0, 0)
		vk.CmdEndRendering(cmd)

		transition_image(cmd, target, .GENERAL, {.FRAGMENT_SHADER}, {.SHADER_READ})
		source_idx = target_idx
	}
	prog.buffer_index = source_idx
}

get_output_image :: proc(prog: ^Program) -> ^GlowImage {
	if !prog.images_loaded || len(prog.passes) == 0 {
		return nil
	}
	return prog.images[prog.buffer_index]
}

@(private = "file")
create_descriptor_set :: proc(prog: ^Program, image_count: int) {
	binding := vk.DescriptorSetLayoutBinding {
		binding            = 0,
		descriptorType     = .STORAGE_IMAGE,
		descriptorCount    = u32(image_count),
		stageFlags         = {.FRAGMENT},
		pImmutableSamplers = nil,
	}
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 1,
		pBindings    = &binding,
	}
	vk_try(vk.CreateDescriptorSetLayout(prog.device, &layout_info, nil, &prog.descriptor_layout))

	layouts := [1]vk.DescriptorSetLayout{prog.descriptor_layout}
	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = prog.res.descriptor_pool,
		descriptorSetCount = 1,
		pSetLayouts        = &layouts[0],
	}
	descriptor_sets: [1]vk.DescriptorSet
	vk_try(vk.AllocateDescriptorSets(prog.device, &alloc_info, &descriptor_sets[0]))
	prog.descriptor_set = descriptor_sets[0]
}

@(private = "file")
update_descriptor_set :: proc(prog: ^Program, descriptor_set: vk.DescriptorSet) {
	image_count := len(prog.images)
	image_infos := make([]vk.DescriptorImageInfo, image_count, context.temp_allocator)
	for i in 0 ..< image_count {
		image := prog.images[i]
		image_infos[i] = vk.DescriptorImageInfo {
			imageLayout = .GENERAL,
			imageView   = image.view,
		}
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		dstSet          = descriptor_set,
		dstBinding      = 0,
		dstArrayElement = 0,
		descriptorCount = u32(image_count),
		descriptorType  = .STORAGE_IMAGE,
		pImageInfo      = raw_data(image_infos),
	}
	vk.UpdateDescriptorSets(prog.device, 1, &write, 0, nil)
}

@(private = "file")
create_pipeline_layout :: proc(prog: ^Program) {
	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(PushConstants)},
	}
	descriptor_layouts := []vk.DescriptorSetLayout{prog.descriptor_layout}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
		setLayoutCount         = 1,
		pSetLayouts            = raw_data(descriptor_layouts),
	}
	vk_try(vk.CreatePipelineLayout(prog.device, &layout_info, nil, &prog.layout))
}

@(private = "file")
create_pipeline :: proc(
	prog: ^Program,
	ps_module: vk.ShaderModule,
	entry_name: cstring,
) -> (
	pipeline: vk.Pipeline,
) {
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
		pName  = entry_name,
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
	vk_try(vk.CreateGraphicsPipelines(prog.device, 0, 1, &pipeline_info, nil, &pipeline))
	return
}
