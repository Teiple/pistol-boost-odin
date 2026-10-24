package main

import "core:slice"
import sg "sokol-odin/sokol/gfx"
import sglue "sokol-odin/sokol/glue"
import "shaders"

WINDOW_CLEAR_COLOR     : sg.Color : {0, 0, 0, 0}
VIEWPORT_CLEAR_COLOR   : sg.Color : {0.02, 0.078, 0.078, 1}

Viewport :: struct {
	base_size : [2]f32,
	pending_base_size : [2]f32,
	dest_rect : [4]f32,

	scale : f32,
	gamma : f32,

	display_pipeline : sg.Pipeline,
	display_shader   : sg.Shader,
	
	offscreen_pass      : sg.Pass,
	offscreen_color_img : sg.Image,
	offscreen_depth_img : sg.Image,

	display_pass   : sg.Pass,
	display_bindings : sg.Bindings,
}

viewport_init :: proc(vp : ^Viewport, base_size : [2]f32, window_size : [2]f32) {
	vp.base_size = base_size

	// Offscreen pipeline & bindingns
	{
		offscreen_size := cast([2]i32)vp.base_size
		vp.offscreen_color_img = sg.make_image({
			usage  = {
				color_attachment = true,
			},
			width  = offscreen_size.x,
			height = offscreen_size.y,
			pixel_format = .RGBA8,
		})

		vp.offscreen_depth_img = sg.make_image({
			usage  = {
				depth_stencil_attachment = true,
			},
			width  = offscreen_size.x,
			height =  offscreen_size.y,
			pixel_format = .DEPTH,
		})

		vp.offscreen_pass.attachments.colors[0]     = sg.make_view({
			color_attachment = {
				image = vp.offscreen_color_img
			},
		})

		vp.offscreen_pass.attachments.depth_stencil = sg.make_view({
			depth_stencil_attachment = {
				image = vp.offscreen_depth_img
			},
		})

		vp.offscreen_pass.action.colors[0] = {
			load_action = .CLEAR,
			clear_value = VIEWPORT_CLEAR_COLOR,
		}
	}

	// Display pipeline & bindings
	{
		vp.display_shader =	sg.make_shader(shaders.viewport_shader_desc(sg.query_backend()))
		vp.display_pipeline = sg.make_pipeline({
			index_type = .NONE, // it's the default btw, just write to make it clearer
			shader = vp.display_shader,
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

		vp.display_bindings.vertex_buffers[0] = sg.make_buffer({
			data = {
				ptr  = raw_data(vertices),
				size = cast(uint)slice.size(vertices), 
			}	
		})
		vp.display_bindings.samplers[shaders.SMP_unlit_smp] = sg.make_sampler({
			min_filter = .LINEAR,
			mag_filter = .LINEAR,
			wrap_u     = .CLAMP_TO_EDGE,
			wrap_v     = .CLAMP_TO_EDGE,
		})
		
		vp.display_bindings.views[shaders.VIEW_unlit_tex] = sg.make_view({
			texture = {
				image = vp.offscreen_color_img
			},
		})

		vp.display_pass.action.colors[0] = {
			load_action = .CLEAR,
			clear_value = WINDOW_CLEAR_COLOR,
		}
	}

	// Some system relies on .scale or .dest_rect supper early on
	viewport_calculate_aspect(vp, window_size)	

	vp.gamma = 1.0
}

viewport_calculate_aspect :: proc(vp : ^Viewport, window_size : [2]f32){
	// calculate destination rect
	// scale to the fitter axis
	vp.scale = min(window_size.x / vp.base_size.x, window_size.y / vp.base_size.y)

	vp.dest_rect.zw = {vp.base_size.x, vp.base_size.y} * vp.scale
	vp.dest_rect.xy = (window_size - vp.dest_rect.zw) / 2
}

viewport_begin :: proc(vp : ^Viewport, window_size : [2]f32) {
	if vp.pending_base_size != 0 {
		vp.base_size         = vp.pending_base_size
		vp.pending_base_size = 0
	}
	
	viewport_calculate_aspect(vp, window_size)

	// Offscreen Pass
	sg.begin_pass(vp.offscreen_pass)
}

viewport_end :: proc(vp : ^Viewport) {
	// End offscreen pass
	sg.end_pass()
	
	// Display Pass
	// must be set every frame
	vp.display_pass.swapchain = sglue.swapchain()
	
	sg.begin_pass(vp.display_pass)
	// Apply viewport
	{
		// apply a scissor to crop the viewport
		// also apply viewport for matrix stuff that i don't understand
		sg.apply_viewportf(vp.dest_rect.x, vp.dest_rect.y, vp.dest_rect.z, vp.dest_rect.w, true)
		sg.apply_scissor_rectf(vp.dest_rect.x, vp.dest_rect.y, vp.dest_rect.z, vp.dest_rect.w, true)
	}
	sg.apply_pipeline(vp.display_pipeline)
	sg.apply_bindings(vp.display_bindings)

	params : shaders.Viewport_Vs_Params = {
		gamma = vp.gamma
	}
	sg.apply_uniforms(shaders.UB_viewport_vs_params, {
		ptr = &params, size = size_of(params)
	})

	// Draw viewport triangle
	sg.draw(0, 3, 1)
	sg.end_pass()

	sg.commit()
}

viewport_destroy :: proc(vp : ^Viewport) {
	sg.destroy_image(vp.offscreen_color_img)
	sg.destroy_image(vp.offscreen_depth_img)
	
	sg.destroy_view(vp.offscreen_pass.attachments.colors[0])
	sg.destroy_view(vp.offscreen_pass.attachments.depth_stencil)
	sg.destroy_view(vp.display_bindings.views[shaders.VIEW_unlit_tex])

	sg.destroy_buffer(vp.display_bindings.vertex_buffers[0])
	sg.destroy_sampler(vp.display_bindings.samplers[shaders.SMP_unlit_smp])
	
	sg.destroy_shader(vp.display_shader)
	sg.destroy_pipeline(vp.display_pipeline)
}

viewport_get_aspect :: proc(vp : ^Viewport) -> f32 {
	return vp.base_size.x / vp.base_size.y
}

viewport_get_vp_mouse_delta :: proc(vp : ^Viewport, mouse_delta: [2]f32) -> [2]f32 {
	return mouse_delta / vp.scale
}

viewport_get_vp_confine_mouse_pos :: proc(vp : ^Viewport, mouse_position: [2]f32) -> [2]f32 {
	return {clamp(mouse_position.x, 0, vp.base_size.x), clamp(mouse_position.y, 0, vp.base_size.y)}
}

viewport_set_gamma :: proc(vp : ^Viewport, gamma : f32) {
	vp.gamma = gamma
}

viewport_request_size :: proc(vp : ^Viewport, size: [2]f32) {
	vp.pending_base_size = size
}