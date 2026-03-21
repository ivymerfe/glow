package glowr

import "../slang"
import refl "../slang/reflection_wrapper"
import "core:log"
import "core:strings"
import "core:time"
import vk "vendor:vulkan"

ProgramPass :: struct {
	entry_name: cstring,
	pipeline:   vk.Pipeline,
}

Program :: struct {
	using vk_context: VulkanContext,
	res:              ^ResourceManager,
	passes:           []ProgramPass,
	allocated:        bool,
	pool_index:       u32,
	start_index:      u32,
	image_count:      u32,
	camera_supported: bool,
}

compile_program :: proc(
	prog: ^Program,
	res: ^ResourceManager,
	global: ^slang.IGlobalSession,
	path: string,
	source: string,
	pool_index: u32,
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

	path_c := strings.clone_to_cstring(path)
	source_c := strings.clone_to_cstring(source)
	defer delete_cstring(path_c)
	defer delete_cstring(source_c)

	diagnostics: ^slang.IBlob
	module := session->loadModuleFromSourceString("shader", path_c, source_c, &diagnostics)
	diagnostics_check(path, diagnostics)
	if module == nil {
		return
	}
	entry_count := module->getDefinedEntryPointCount()
	components := make([]^slang.IComponentType, entry_count + 1, context.temp_allocator)
	for i in 0 ..< entry_count {
		entry: ^slang.IEntryPoint
		module->getDefinedEntryPoint(i, &entry)
		components[i] = entry
	}
	components[entry_count] = module

	composed_program: ^slang.IComponentType
	session->createCompositeComponentType(
		&components[0],
		len(components),
		&composed_program,
		&diagnostics,
	)
	diagnostics_check(path, diagnostics)
	if composed_program == nil {
		return
	}
	defer composed_program->release()

	linked_program: ^slang.IComponentType
	composed_program->link(&linked_program, &diagnostics)
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
	prog.passes = make([]ProgramPass, entry_point_count)

	entry_idx := 0
	for i in 0 ..< entry_point_count {
		entry_layout := layout_wrap->getEntryPointByIndex(i)
		if entry_layout->getStage() == .FRAGMENT {
			entry_name := entry_layout->getNameOverride()
			if entry_name == nil {
				entry_name = entry_layout->getName()
			}
			entry: ^slang.IComponentType
			prog.passes[entry_idx] = ProgramPass {
				entry_name = entry_name,
			}
			entry_idx += 1
		}
	}
	prog.passes = prog.passes[:entry_idx]
	if len(prog.passes) == 0 {
		log.debugf("[%s] no fragment entry points found", path)
		return
	}
	target_code: ^slang.IBlob

	linked_program->getTargetCode(0, &target_code, &diagnostics)
	diagnostics_check(path, diagnostics)
	if target_code == nil {
		return
	}
	defer target_code->release()

	prog.vk_context = res.vk_context
	prog.res = res
	prog.pool_index = pool_index
	prog.image_count = u32(len(prog.passes) + 1)
	prog.camera_supported = false

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = int(target_code->getBufferSize()),
		pCode    = auto_cast target_code->getBufferPointer(),
	}
	shader: vk.ShaderModule
	vk_try(vk.CreateShaderModule(prog.device, &create_info, nil, &shader))

	for &pass in prog.passes {
		pass.pipeline = create_pipeline(prog, shader, pass.entry_name)
	}
	vk.DestroyShaderModule(prog.device, shader, nil)

	request_images(res, prog.pool_index, prog.image_count)
	parse_program_header(prog, source)
	prog.allocated = true
	success = true
	return
}

destroy_program :: proc(prog: ^Program) {
	if !prog.allocated {
		return
	}
	for pass in prog.passes {
		if pass.pipeline != {} {
			vk.DestroyPipeline(prog.device, pass.pipeline, nil)
		}
	}
	delete(prog.passes)
	prog.allocated = false
}

parse_program_header :: proc(prog: ^Program, source: string) {
	first_line := strings.cut(source, 0, strings.index_rune(source, '\n'))
	if strings.starts_with(first_line, "//") {
		flags := strings.split(strings.cut(first_line, 2), ";")
		for flag in flags {
			switch strings.trim_space(flag) {
			case "+camera":
				prog.camera_supported = true
			}
		}
	}
}

inherit_program_state :: proc(dest: ^Program, src: ^Program) {
	dest.start_index = src.start_index
}

get_program_output :: proc(prog: ^Program) -> ^GlowImage {
	return get_image(
		prog.res,
		prog.pool_index + (prog.start_index + prog.image_count - 1) % prog.image_count,
	)
}

shift_program_images :: proc(prog: ^Program) {
	prog.start_index = (prog.start_index + 1) % prog.image_count
}

draw_program :: proc(prog: ^Program, cmd: vk.CommandBuffer, render_info: ^RenderInfo) {
	if len(prog.passes) == 0 {
		return
	}
	image_count := prog.image_count

	pass_constants := render_info.constants
	pass_constants.start_index = prog.start_index
	pass_constants.pool_index = prog.pool_index
	pass_constants.image_count = image_count

	for pass, pass_index in prog.passes {
		target := get_image(prog.res, prog.pool_index + prog.start_index)
		pass_constants.prev_index = (prog.start_index + 1) % image_count

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

		vk.CmdPushConstants(
			cmd,
			prog.res.pipeline_layout,
			{.VERTEX, .FRAGMENT},
			0,
			size_of(PushConstants),
			&pass_constants,
		)

		vk.CmdDraw(cmd, 3, 1, 0, 0)
		vk.CmdEndRendering(cmd)

		transition_image(cmd, target, .GENERAL, {.FRAGMENT_SHADER}, {.SHADER_READ})
		shift_program_images(prog)
	}
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
		layout              = prog.res.pipeline_layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}
	vk_try(vk.CreateGraphicsPipelines(prog.device, 0, 1, &pipeline_info, nil, &pipeline))
	return
}
