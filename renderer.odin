package main

import "core:fmt"
import "core:slice"
import "core:math/linalg"
import sg "sokol-odin/sokol/gfx"
import shaders "shaders"

Pipeline_Type :: enum {
	Unlit_Triangles,
	Skinned_Unlit_Triangles,
}

Pipeline_Resource :: struct {
	pipeline : sg.Pipeline,
	shader   : sg.Shader,
}

Renderer :: struct {
	pip_resources : [Pipeline_Type]Pipeline_Resource,
	shaders       : [Pipeline_Type]sg.Shader,
	bindings      : sg.Bindings,
	viewport      : ^Viewport,
	camera        : ^Camera,
}

// For .RGBA8 pixel format
@(rodata)
white_pixel : []u32 = { 0xFFFFFFFF }
// This would be managed by the renderer, can be used as a temporal sample image
sg_placeholder_image : sg.Image

renderer_init :: proc(renderer : ^Renderer) {
	// This is somewhat a shared resource for other graphical module to use
	sg_placeholder_image = sg.make_image({
		width = 1,
		height = 1,
		data = {
			mip_levels = {
				0 = {
					ptr = raw_data(white_pixel),
					size = cast(uint)slice.size(white_pixel)
				}
			}
		}
	})

	for pipeline_type in Pipeline_Type {
		pip_res := &renderer.pip_resources[pipeline_type]
		switch pipeline_type {
			case .Unlit_Triangles:
				pip_res.shader   = sg.make_shader(shaders.unlit_shader_desc(sg.query_backend()))
				pip_res.pipeline = sg.make_pipeline({
					index_type  = .UINT16,
					shader      = pip_res.shader,
					layout      = {
						attrs   = {
							shaders.ATTR_unlit_pos       = { format = .FLOAT3 },
							shaders.ATTR_unlit_color0    = { format = .FLOAT4 },
							shaders.ATTR_unlit_texcoord0 = { format = .FLOAT2 },
						}
					},
					cull_mode   = .BACK,
					depth       = {
						write_enabled = true,
						compare       = .LESS_EQUAL
					},
				})
			case .Skinned_Unlit_Triangles:
				pip_res.shader   = sg.make_shader(shaders.skinned_shader_desc(sg.query_backend()))
				pip_res.pipeline = sg.make_pipeline({
					index_type  = .UINT16,
					shader      = pip_res.shader,
					layout      = {
						attrs   = {
							shaders.ATTR_skinned_pos       = { format = .FLOAT3 },
							shaders.ATTR_skinned_color0    = { format = .FLOAT4 },
							shaders.ATTR_skinned_texcoord0 = { format = .FLOAT2 },
							shaders.ATTR_skinned_joints    = { format = .FLOAT4 },
							shaders.ATTR_skinned_weights   = { format = .FLOAT4 },
						}
					},
					cull_mode   = .BACK,
					depth       = {
						write_enabled = true,
						compare       = .LESS_EQUAL
					},
				})
		}
	}
}

renderer_begin :: proc(renderer : ^Renderer, camera : ^Camera, viewport : ^Viewport) {
	renderer.camera = camera
	renderer.viewport = viewport
}

renderer_end :: proc(renderer : ^Renderer) {
	// nothing for now
}

renderer_destroy :: proc(renderer : ^Renderer) {
	for p in renderer.pip_resources {
		sg.destroy_shader(p.shader)
		sg.destroy_pipeline(p.pipeline)
	}

	// destroy shared resources, seems like the right place
	sg.destroy_image(sg_placeholder_image)
}

renderer_draw_mesh :: proc(
	renderer     : ^Renderer,
	mesh         : ^Mesh,
	position     : [3]f32,
	rotation     : quaternion128,
) {
	camera   := renderer.camera
	viewport := renderer.viewport

	sg.apply_pipeline(renderer.pip_resources[.Unlit_Triangles].pipeline)
	
	model_matrix := linalg.matrix4_translate(position) * linalg.matrix4_from_quaternion(rotation)

	params : shaders.Unlit_Vs_Params = {
		mvp = camera_view_projection_matrix(camera, viewport) * model_matrix,
	}
	
	// Warning: This assumes alot, that all pipelines must use mvp and the ub index is 0
	sg.apply_uniforms(0, {ptr = &params, size = size_of(params)})
	sg.apply_bindings(mesh.bindings)

	sg.draw(0, mesh.index_count, 1)
}

renderer_draw_model :: proc(
	renderer : ^Renderer,
	model    : Model,
	position: [3]f32,
	rotation : quaternion128,
) {
	camera   := renderer.camera
	viewport := renderer.viewport

	sg.apply_pipeline(renderer.pip_resources[.Skinned_Unlit_Triangles].pipeline)
	
	model_matrix := linalg.matrix4_translate(position) * linalg.matrix4_from_quaternion(rotation)

	params : shaders.Skinned_Vs_Params = {
		mvp   = camera_view_projection_matrix(camera, viewport) * model_matrix,
	}

	assert(len(model.model_to_bone_matrix) <= len(params.bones))
	for bone, i in model.bones {
		params.bones[i] = model.bones[i].model_matrix * model.model_to_bone_matrix[i]
	}
	
	// Warning: This assumes alot, that all pipelines must use mvp and the ub index is 0
	sg.apply_uniforms(0, {ptr = &params, size = size_of(params)})
	sg.apply_bindings(model.bindings)

	sg.draw(0, model.index_count, 1)
}