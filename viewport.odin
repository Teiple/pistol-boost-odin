package main

import "core:slice"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import "shaders"
import linalg "core:math/linalg"

WINDOW_CLEAR_COLOR           : sg.Color : {0, 0, 0, 0}
VIEWPORT_DEFAULT_CLEAR_COLOR : [4]f32   : {0.02, 0.078, 0.078, 1}

Viewport :: struct {
	base_size         : [2]f32,
	pending_base_size : [2]f32,
	dest_rect         : [4]f32,

	scale : f32,
	gamma : f32,

	display_pipeline : sg.Pipeline,
	display_shader   : sg.Shader,
	
	offscreen_pass      : sg.Pass,
	offscreen_color_img : sg.Image,
	offscreen_depth_img : sg.Image,

	display_pass     : sg.Pass,
	display_bindings : sg.Bindings,
}

viewport_init_offscreen_size :: proc(viewport : ^Viewport) {
	viewport.offscreen_color_img = sg.make_image({
		usage  = {
			color_attachment = true,
		},
		width  = i32(viewport.base_size.x),
		height = i32(viewport.base_size.y),
		pixel_format = .RGBA8,
	})

	viewport.offscreen_depth_img = sg.make_image({
		usage  = {
			depth_stencil_attachment = true,
		},
		width  = i32(viewport.base_size.x),
		height = i32(viewport.base_size.y),
		pixel_format = .DEPTH,
	})

	viewport.offscreen_pass.attachments.colors[0]     = sg.make_view({
		color_attachment = {
			image = viewport.offscreen_color_img
		},
	})

	viewport.offscreen_pass.attachments.depth_stencil = sg.make_view({
		depth_stencil_attachment = {
			image = viewport.offscreen_depth_img
		},
	})
}

viewport_destroy_offscreen_sizing :: proc(viewport : ^Viewport) {
	sg.destroy_view(viewport.offscreen_pass.attachments.colors[0])
	sg.destroy_view(viewport.offscreen_pass.attachments.depth_stencil)
	sg.destroy_image(viewport.offscreen_color_img)
	sg.destroy_image(viewport.offscreen_depth_img)
}

viewport_init :: proc(viewport : ^Viewport, base_size : [2]f32, window_size : [2]f32, clear_color : [4]f32) {
	viewport.base_size   = base_size

	// Offscreen pipeline & bindingns
	viewport_init_offscreen_size(viewport)
	viewport.offscreen_pass.action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {expand_values(clear_color)},
	}

	// Display pipeline & bindings
	{
		viewport.display_shader =	sg.make_shader(shaders.viewport_shader_desc(sg.query_backend()))
		viewport.display_pipeline = sg.make_pipeline({
			index_type = .NONE, // it's the default btw, just write to make it clearer
			shader = viewport.display_shader,
			layout = {
				attrs = {
					shaders.ATTR_viewport_pos =  {
						format = .FLOAT3,
					},
					shaders.ATTR_viewport_color0 = {
						format = .FLOAT4,
					},
					shaders.ATTR_viewport_texcoord0 = {
						format = .FLOAT2,
					},
				} 
			},
			depth = {
				write_enabled = false,
				compare       = .ALWAYS,
			},
			primitive_type = .TRIANGLES,
			cull_mode      = .NONE,
		})

		// the quad that covers the screen 
		// the uv is rotated since shader coordinate use bottom left as origin
		// while the image pixel data starts from top left 
		vertices : []struct {
			position : [3]f32,
			color    : [4]f32,
			uv 	     : [2]f32,
		} = {
			0 = { {-1, -1, 0}, 1, {0, 0} },
			1 = { {-1,  3, 0}, 1, {0, 2} },
			2 = { { 3, -1, 0}, 1, {2, 0} },
		}

		viewport.display_bindings.vertex_buffers[0] = sg.make_buffer({
			data = {
				ptr  = raw_data(vertices),
				size = cast(uint)slice.size(vertices), 
			}	
		})

		viewport.display_bindings.samplers[0] = sg.make_sampler({
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			wrap_u     = .CLAMP_TO_EDGE,
			wrap_v     = .CLAMP_TO_EDGE,
		})

		viewport.display_pass.action.colors[0] = {
			load_action = .CLEAR,
			clear_value = WINDOW_CLEAR_COLOR,
		}
	}

	// Apply view to offscreen texture
	viewport.display_bindings.views[0] = sg.make_view({
		texture = {
			image = viewport.offscreen_color_img
		},
	})

	// Some system relies on .scale or .dest_rect supper early on
	viewport_calculate_aspect(viewport, window_size)	

	viewport.gamma = 1.0
}

viewport_calculate_aspect :: proc(viewport : ^Viewport, window_size : [2]f32){
	// calculate destination rect
	// scale to the fitter axis
	viewport.scale = min(window_size.x / viewport.base_size.x, window_size.y / viewport.base_size.y)

	viewport.dest_rect.zw = {viewport.base_size.x, viewport.base_size.y} * viewport.scale
	viewport.dest_rect.xy = (window_size - viewport.dest_rect.zw) / 2
}

viewport_begin :: proc(viewport : ^Viewport, window_size : [2]f32) {
	if viewport.pending_base_size != 0 {
		// Destroy the old offscreen with old size
		viewport_destroy_offscreen_sizing(viewport)
		// Destroy to old view to old size
		sg.destroy_view(viewport.display_bindings.views[0])
		
		viewport.base_size = viewport.pending_base_size
		
		// Init new size
		viewport_init_offscreen_size(viewport)
		// Init new view to new size
		viewport.display_bindings.views[0] = sg.make_view({
			texture = {
				image = viewport.offscreen_color_img
			},
		})

		viewport.pending_base_size = 0
	}
	
	viewport_calculate_aspect(viewport, window_size)

	// Offscreen Pass
	sg.begin_pass(viewport.offscreen_pass)
}

viewport_end :: proc(viewport : ^Viewport) {
	// End offscreen pass
	sg.end_pass()
	
	// Display Pass
	// must be set every frame
	viewport.display_pass.swapchain = sglue.swapchain()
	
	sg.begin_pass(viewport.display_pass)
	// Apply viewport
	{
		// apply a scissor to crop the viewport
		// also apply viewport for matrix stuff that i don't understand
		sg.apply_viewportf(viewport.dest_rect.x, viewport.dest_rect.y, viewport.dest_rect.z, viewport.dest_rect.w, true)
		sg.apply_scissor_rectf(viewport.dest_rect.x, viewport.dest_rect.y, viewport.dest_rect.z, viewport.dest_rect.w, true)
	}
	sg.apply_pipeline(viewport.display_pipeline)
	sg.apply_bindings(viewport.display_bindings)

	params : shaders.Viewport_Fs_Params = {
		gamma = viewport.gamma
	}
	sg.apply_uniforms(shaders.UB_viewport_fs_params, {
		ptr = &params, size = size_of(params)
	})

	// Draw viewport triangle
	sg.draw(0, 3, 1)
	sg.end_pass()

	sg.commit()
}

viewport_destroy :: proc(viewport : ^Viewport) {
	viewport_destroy_offscreen_sizing(viewport)
	sg.destroy_view(viewport.display_bindings.views[0])

	sg.destroy_buffer(viewport.display_bindings.vertex_buffers[0])
	sg.destroy_sampler(viewport.display_bindings.samplers[0])
	
	sg.destroy_shader(viewport.display_shader)
	sg.destroy_pipeline(viewport.display_pipeline)
}

viewport_get_aspect :: proc(viewport : ^Viewport) -> f32 {
	return viewport.base_size.x / viewport.base_size.y
}

viewport_get_viewport_mouse_delta :: proc(viewport : ^Viewport, mouse_delta: [2]f32) -> [2]f32 {
	return mouse_delta / viewport.scale
}

viewport_confine_mouse_pos :: proc(viewport : ^Viewport, mouse_position: [2]f32) -> [2]f32 {
	return {clamp(mouse_position.x, 0, viewport.base_size.x), clamp(mouse_position.y, 0, viewport.base_size.y)}
}

viewport_set_gamma :: proc(viewport : ^Viewport, gamma : f32) {
	viewport.gamma = gamma
}

viewport_request_size :: proc(viewport : ^Viewport, size: [2]f32) {
	viewport.pending_base_size = size
}

viewport_get_mouse_world_position_on_zplane :: proc(viewport: ^Viewport, camera: ^Camera, mouse_position : [2]f32, z_plane: f32 = 0) -> [3]f32 {
	// llm made this i don't understand this
	
	// normalize screen space mouse position to ndc space
	ndc_x := (mouse_position.x / viewport.base_size.x) * 2.0 - 1.0
	ndc_y := 1.0 - (mouse_position.y / viewport.base_size.y) * 2.0
	
	inversed_viewport := linalg.matrix4_inverse(
		camera_view_projection_matrix(camera, viewport)
	)

	near_clip := inversed_viewport * [4]f32{ndc_x, ndc_y, -1.0, 1.0}
	far_clip  := inversed_viewport * [4]f32{ndc_x, ndc_y,  1.0, 1.0}

	p_near := near_clip.xyz / near_clip.w
	p_far  := far_clip.xyz  / far_clip.w

	ray_dir := linalg.normalize(p_far - p_near)
	if abs(ray_dir.z) < 0.0001 {
		return p_near
	}

	t := (z_plane - p_near.z) / ray_dir.z
	return p_near + ray_dir * t
}

viewport_set_clear_color :: proc(viewport : ^Viewport, color : [4]f32) {
	viewport.offscreen_pass.action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {expand_values(color)},
	}
}