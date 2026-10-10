package main

import "core:math/linalg"
import sg "sokol-odin/sokol/gfx"
import shaders "shaders"

Pipeline_Type :: enum {
	Unlit_Triangles,
	// Skinned_Triangles,
}

Pipeline_Resource :: struct {
	pipeline : sg.Pipeline,
	shader   : sg.Shader,
}

Mvp_Vs_Param :: struct {
	mvp : matrix[4, 4]f32,
}

Renderer :: struct {
	pip_resources : [Pipeline_Type]Pipeline_Resource,
	shaders       : [Pipeline_Type]sg.Shader,
	bindings      : sg.Bindings,
	meshes        : [dynamic]Mesh,
}

renderer_init :: proc(renderer : ^Renderer) {
	res := &renderer.pip_resources[.Unlit_Triangles]
	
	res.shader   = sg.make_shader(shaders.unlit_shader_desc(sg.query_backend()))
	res.pipeline = sg.make_pipeline({
		index_type  = .UINT16,
		shader      = res.shader,
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

}

renderer_destroy :: proc(renderer : ^Renderer) {
	for p in renderer.pip_resources {
		sg.destroy_shader(p.shader)
		sg.destroy_pipeline(p.pipeline)
	}
}

renderer_draw_mesh :: proc(
	renderer     : ^Renderer,
	camera       : ^Camera,
	viewport     : ^Viewport,
	mesh         : ^Mesh,
	position     : [3]f32,
	rotation     : quaternion128,
) {
	sg.apply_pipeline(renderer.pip_resources[.Unlit_Triangles].pipeline)
	
	model_matrix := linalg.matrix4_translate(position) * linalg.matrix4_from_quaternion(rotation)

	mvp : Mvp_Vs_Param = {
		mvp = camera_view_projection_matrix(camera, viewport) * model_matrix,
	}
	
	// Warning: This assumes alot, that all pipelines must use mvp and the ub index is 0
	sg.apply_uniforms(0, {ptr = &mvp, size = size_of(mvp)})
	sg.apply_bindings(mesh.bindings)

	sg.draw(0, mesh.index_count, 1)
}


renderer_new_mesh :: proc(renderer : ^Renderer) -> ^Mesh {
	append(&renderer.meshes, Mesh{})
	return &renderer.meshes[len(renderer.meshes) - 1]
}
