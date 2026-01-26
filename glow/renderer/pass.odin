package renderer

import "core:log"
import vk "vendor:vulkan"

RenderPass :: struct {
	ren:      ^GlowRenderer,
	pipeline: vk.Pipeline,
	layout:   vk.PipelineLayout,
}

record_pass_commands :: proc(pass: ^RenderPass, cmd: vk.CommandBuffer, push: ^PushConstants) {
	vk.CmdBindPipeline(cmd, .GRAPHICS, pass.pipeline)

	width := pass.ren.target_width
	height := pass.ren.target_height

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

	vk.CmdPushConstants(cmd, pass.layout, {.VERTEX, .FRAGMENT}, 0, size_of(PushConstants), push)

	vk.CmdDraw(cmd, 3, 1, 0, 0)
}

create_render_pass :: proc(pass: ^RenderPass, ren: ^GlowRenderer, module: vk.ShaderModule) {
	pass.ren = ren

	push_constant_ranges := []vk.PushConstantRange {
		{stageFlags = {.VERTEX, .FRAGMENT}, offset = 0, size = size_of(PushConstants)},
	}
	layout_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount = 1,
		pPushConstantRanges    = raw_data(push_constant_ranges),
		setLayoutCount         = 0,
	}
	vk_try(vk.CreatePipelineLayout(ren.device, &layout_info, nil, &pass.layout))

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
		module = module,
		pName  = "vsMain",
	}
	pixel_shader_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = module,
		pName  = "psMain",
	}
	shader_stages := []vk.PipelineShaderStageCreateInfo{vertex_shader_info, pixel_shader_info}
	format: vk.Format = OFFSCREEN_FORMAT
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
		layout              = pass.layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}
	vk_try(vk.CreateGraphicsPipelines(ren.device, 0, 1, &pipeline_info, nil, &pass.pipeline))
}

destroy_render_pass :: proc(pass: ^RenderPass) {
	device := pass.ren.vk_context.device
	vk.DestroyPipelineLayout(device, pass.layout, nil)
	vk.DestroyPipeline(device, pass.pipeline, nil)
}
