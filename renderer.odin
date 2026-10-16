package main

import "core:slice"
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
	viewport      : ^Viewport,
	camera        : ^Camera,
}

// For .RGBA8 pixel format
WHITE_PIXEL :: []u32 { 0xFFFFFFFF }
// This would be managed by the renderer
shared_white_pixel_image : sg.Image

renderer_init :: proc(renderer : ^Renderer) {
	// This is somewhat a shared resource for other graphical module to use
	shared_white_pixel_image = sg.make_image({
		width = 1,
		height = 1,
		data = {
			mip_levels = {
				0 = {
					ptr = raw_data(WHITE_PIXEL),
					size = cast(uint)slice.size(WHITE_PIXEL)
				}
			}
		}
	})

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
	sg.destroy_image(shared_white_pixel_image)
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

	mvp : Mvp_Vs_Param = {
		mvp = camera_view_projection_matrix(camera, viewport) * model_matrix,
	}
	
	// Warning: This assumes alot, that all pipelines must use mvp and the ub index is 0
	sg.apply_uniforms(0, {ptr = &mvp, size = size_of(mvp)})
	sg.apply_bindings(mesh.bindings)

	sg.draw(0, mesh.index_count, 1)
}